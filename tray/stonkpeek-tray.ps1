<#
  StonkPeek — Windows 트레이 아이콘 + 종목별 자동 회전 위젯 (화면형 싱크)

  계좌를 쳐다보지 말고, 느껴라. 시계 옆 점 하나가 등락 색으로 바뀐다.
  그 점에 마우스를 0.5초 올리고 있으면 작업표시줄 코너에 보유 종목이
  하나씩 자동으로 돌아가며 종목명/현재가/당일·누적 수익률/손익이 뜬다
  (날씨 위젯처럼) — 커서를 치우면 사라진다. 숫자만 보여주는 단순한
  정보 표시일 뿐, 별도 알림(풍선 등)은 전혀 띄우지 않는다. 데몬
  (`stonkpeek start` / `stonkpeek demo`)이 쓰는 ~/.stonkpeek/state.json을
  주기적으로 읽어 갱신하는 읽기 전용 소비자. API 호출 없음, 키 없음.

  직접 실행:
    powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
      -File tray\stonkpeek-tray.ps1
  보통은 `stonkpeek tray` 가 이 스크립트를 대신 띄운다.
#>
param(
  [int]$IntervalSec = 5,
  # 보스키: Ctrl+Alt+<BossKey> 전역 단축키로 즉시 회색(사장님 모드) 토글. 한 글자.
  [string]$BossKey = "H",
  [string]$StatePath = (Join-Path $env:USERPROFILE ".stonkpeek\state.json")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 전역 단축키(보스키)를 받는 메시지 전용 창. WM_HOTKEY 수신 시 .NET 이벤트를 쏜다.
Add-Type -ReferencedAssemblies System.Windows.Forms @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HotkeyWindow : NativeWindow, IDisposable {
  [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
  [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
  const int WM_HOTKEY = 0x0312;
  const int HWND_MESSAGE = -3;
  int _id;
  public event Action HotkeyPressed;
  public bool Registered { get; private set; }
  public HotkeyWindow(uint mods, uint vk, int id) {
    _id = id;
    var cp = new CreateParams();
    cp.Parent = (IntPtr)HWND_MESSAGE;   // 메시지 전용 창
    CreateHandle(cp);
    Registered = RegisterHotKey(this.Handle, _id, mods, vk);
  }
  protected override void WndProc(ref Message m) {
    if (m.Msg == WM_HOTKEY && (int)m.WParam == _id) {
      var h = HotkeyPressed; if (h != null) h();
    }
    base.WndProc(ref m);
  }
  public void Dispose() {
    try { UnregisterHotKey(this.Handle, _id); } catch { }
    DestroyHandle();
  }
}
"@

# NotifyIcon.MouseMove는 Windows 11의 새 트레이 UI에서 신뢰할 수 없다(실제로 안 붙는 경우가 흔함).
# 대신 Shell_NotifyIconGetRect로 우리 아이콘의 실제 화면 사각형을 얻어, 커서 위치를 직접
# 폴링해서 hover를 판정한다 (트레이 UI 버전과 무관하게 동작하는 공식 API).
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TrayIconRect {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct NOTIFYICONIDENTIFIER {
    public uint cbSize;
    public IntPtr hWnd;
    public uint uID;
    public Guid guidItem;
  }

  [DllImport("shell32.dll")]
  static extern int Shell_NotifyIconGetRect(ref NOTIFYICONIDENTIFIER identifier, out RECT iconLocation);

  public static bool TryGetRect(IntPtr hWnd, uint uID, out RECT rect) {
    var id = new NOTIFYICONIDENTIFIER();
    id.cbSize = (uint)Marshal.SizeOf(typeof(NOTIFYICONIDENTIFIER));
    id.hWnd = hWnd;
    id.uID = uID;
    id.guidItem = Guid.Empty;
    int hr = Shell_NotifyIconGetRect(ref id, out rect);
    return hr == 0;
  }
}
"@

$script:Boss     = $false
$script:Hotkey   = $null

# 무드 색 점을 16x16 PNG로 그려 ICO 컨테이너로 감싼 .NET Icon을 만든다.
# (Bitmap.GetHicon()으로 만든 아이콘은 시스템 트레이에서 빈 아이콘으로 렌더링되는 버그가 있어 PNG-ICO로 우회.)
function New-DotIcon([int]$r, [int]$g, [int]$b, [int]$alpha = 255) {
  $size = 16
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $gfx = [System.Drawing.Graphics]::FromImage($bmp)
  $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $gfx.Clear([System.Drawing.Color]::Transparent)
  $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($alpha, $r, $g, $b))
  $gfx.FillEllipse($brush, 1, 1, 14, 14)
  # 어두운/밝은 트레이 양쪽에서 떠 보이도록 얇은 흰 테두리.
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 255, 255, 255)), 1
  $gfx.DrawEllipse($pen, 1, 1, 13, 13)
  $gfx.Dispose(); $brush.Dispose(); $pen.Dispose()

  $png = New-Object System.IO.MemoryStream
  $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $pngBytes = $png.ToArray(); $png.Dispose()

  # 단일 PNG 엔트리 ICO 컨테이너 (ICONDIR + ICONDIRENTRY + PNG). Vista+ 트레이가 직접 디코드.
  $ms = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter $ms
  $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)   # reserved, type=icon, count=1
  $bw.Write([byte]$size); $bw.Write([byte]$size)                     # width, height
  $bw.Write([byte]0); $bw.Write([byte]0)                             # colorCount, reserved
  $bw.Write([uint16]1); $bw.Write([uint16]32)                       # planes, bitCount
  $bw.Write([uint32]$pngBytes.Length); $bw.Write([uint32]22)        # bytesInRes, imageOffset
  $bw.Write($pngBytes); $bw.Flush()
  $ms.Position = 0
  $icon = New-Object System.Drawing.Icon $ms
  $bw.Dispose(); $ms.Dispose()                                       # Icon이 스트림을 이미 복사함
  return $icon
}

function Set-TrayIcon([int]$r, [int]$g, [int]$b, [int]$alpha = 255) {
  $old = $notify.Icon
  $notify.Icon = New-DotIcon $r $g $b $alpha
  if ($old) { $old.Dispose() }   # 갈아끼운 뒤 이전 아이콘 정리
}

function Read-Signal {
  if (-not (Test-Path $StatePath)) { return $null }
  try {
    # -Encoding UTF8 필수: Node가 BOM 없는 UTF-8로 쓰는데, Windows PowerShell 5.1의
    # Get-Content 기본 인코딩은 시스템 ANSI 코드페이지라 한글이 깨져 ConvertFrom-Json이 실패한다.
    $raw = Get-Content -Path $StatePath -Raw -Encoding UTF8 -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }   # 기록 중 부분 읽기 방지
    return $raw | ConvertFrom-Json
  } catch {
    return $null   # 데몬이 쓰는 중이면 다음 틱에 재시도
  }
}

function Update-Tray {
  # NotifyIcon.Text는 일부러 안 씀 — OS 기본 툴팁이 hover 위젯과 겹쳐 보이는 걸 막기 위함.
  # 대신 우클릭 메뉴 맨 위($titleItem)에 같은 정보를 담는다.

  # 보스키(사장님 모드): 신호 무관하게 무채색 점. 폴링은 계속 돈다.
  if ($script:Boss) {
    Set-TrayIcon 128 128 128 110
    $titleItem.Text = "StonkPeek — 사장님 모드 (단축키로 복귀)"
    return
  }

  $sig = Read-Signal

  $stale = $true
  if ($sig -and $sig.at) {
    try { $stale = ([datetime]::UtcNow - ([datetime]$sig.at).ToUniversalTime()).TotalMinutes -gt 10 }
    catch { $stale = $true }
  }

  if (-not $sig -or $stale) {
    Set-TrayIcon 128 128 128 110
    $titleItem.Text = "StonkPeek — 데몬 꺼짐"
    return
  }

  $r = [int]$sig.color.r; $g = [int]$sig.color.g; $b = [int]$sig.color.b
  Set-TrayIcon $r $g $b 255

  # 감정 실린 문구·이모지 없이 숫자만. 알림(풍선 등)은 아예 띄우지 않는다.
  $day = [double]$sig.dayChangePct
  $tot = [double]$sig.totalPnlPct
  $pct = if ($day -ge 0) { "+{0:N2}%" -f $day } else { "{0:N2}%" -f $day }
  $totStr = if ($tot -ge 0) { "+{0:N1}%" -f $tot } else { "{0:N1}%" -f $tot }
  $titleItem.Text = "당일 {0}  ·  누적 {1}" -f $pct, $totStr
}

function Toggle-Boss {
  $script:Boss = -not $script:Boss
  Update-Tray
  Set-WidgetContent   # 회전 타이머의 다음 틱(최대 4초)을 기다리지 않고 즉시 반영
}

# ── 회전 위젯 (작업표시줄 코너에 붙는 종목별 자동 순환 창) ──────────
# OS 작업표시줄 내부에 직접 그리는 공개 API가 없어, 작업표시줄 바로 위
# 화면 우하단 코너에 붙는 테두리 없는 always-on-top 창으로 근사한다.

$script:WidgetFrames     = @()
$script:WidgetIdx        = 0
$script:WidgetOn         = $true
$script:RotateIntervalMs = 4000
$script:TrayHwnd         = [IntPtr]::Zero   # Shell_NotifyIconGetRect용, 시작 시퀀스 끝에서 채움
$script:TrayUid          = 0
$script:HoverStartAt     = $null   # hover가 시작된 시각 — 이후 500ms 지나야 위젯을 띄운다
$script:HoverShowDelayMs = 500

# 트레이 점 바로 위에 붙는 위치. Shell_NotifyIconGetRect로 얻은 실제 아이콘 사각형의
# 중앙 X를 기준으로 삼고, 못 얻으면 커서 위치로 근사한다.
function Get-WidgetLocation([System.Drawing.Size]$size) {
  $rect = New-Object TrayIconRect+RECT
  if ($script:TrayHwnd -ne [IntPtr]::Zero -and [TrayIconRect]::TryGetRect($script:TrayHwnd, [uint32]$script:TrayUid, [ref]$rect)) {
    $anchorX = [int](($rect.Left + $rect.Right) / 2)
    $anchorPoint = New-Object System.Drawing.Point $anchorX, $rect.Top
  } else {
    $anchorPoint = [System.Windows.Forms.Cursor]::Position
    $anchorX = $anchorPoint.X
  }
  $wa = [System.Windows.Forms.Screen]::FromPoint($anchorPoint).WorkingArea
  $margin = 8
  $x = [Math]::Min($anchorX, $wa.Right - $size.Width - $margin)
  $x = [Math]::Max($x, $wa.Left + $margin)
  $y = $wa.Bottom - $size.Height - $margin
  return New-Object System.Drawing.Point $x, $y
}

function New-Widget {
  $w = New-Object System.Windows.Forms.Form
  $w.FormBorderStyle = "None"
  $w.ShowInTaskbar = $false
  $w.TopMost = $true
  $w.StartPosition = "Manual"
  $w.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
  $w.Size = New-Object System.Drawing.Size(220, 56)
  $w.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 30)
  $w.Opacity = 0.92
  $w.Location = Get-WidgetLocation $w.Size

  $line2 = New-Object System.Windows.Forms.Label
  $line2.AutoSize = $false
  $line2.Dock = "Top"
  $line2.Height = 22
  $line2.AutoEllipsis = $true
  $line2.Padding = New-Object System.Windows.Forms.Padding(10, 0, 10, 4)
  $line2.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)

  $line1 = New-Object System.Windows.Forms.Label
  $line1.AutoSize = $false
  $line1.Dock = "Top"
  $line1.Height = 26
  $line1.AutoEllipsis = $true
  $line1.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 0)
  $line1.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
  $line1.ForeColor = [System.Drawing.Color]::FromArgb(232, 232, 234)

  $w.Controls.Add($line2)   # Dock=Top 순서상 Line2를 먼저 넣어야 Line1이 위에 온다
  $w.Controls.Add($line1)
  $w | Add-Member -NotePropertyName Line1 -NotePropertyValue $line1
  $w | Add-Member -NotePropertyName Line2 -NotePropertyValue $line2
  return $w
}

# KR 관습(상승 빨강/하락 파랑) — Show-Holdings의 색 규칙과 동일하게 중복 구현.
# cfg.colorScheme("us")는 mood.ts에만 있고 Signal까지 안 넘어오므로 여기선 못 씀.
function Get-HoldingColor([double]$dayChangePct) {
  if ($dayChangePct -gt 0) { return [System.Drawing.Color]::FromArgb(255, 90, 90) }
  elseif ($dayChangePct -lt 0) { return [System.Drawing.Color]::FromArgb(90, 155, 255) }
  else { return [System.Drawing.Color]::FromArgb(180, 180, 182) }
}

function Format-HoldingLines([psobject]$h) {
  $day = [double]$h.dayChangePct
  $tot = [double]$h.totalPnlPct
  $pnl = [double]$h.pnl
  $dayStr = "{0:+0.00;-0.00}%" -f $day
  $totStr = "누적 {0:+0.00;-0.00}%" -f $tot
  $pnlStr = "{0:+#,##0;-#,##0}원" -f $pnl
  $line2 = "{0}  {1}  {2}" -f $dayStr, $totStr, $pnlStr

  if ($null -eq $h.price) {
    return @{ Line1 = [string]$h.name; Line2 = $line2; Color = (Get-HoldingColor $day) }
  }
  $price = [double]$h.price
  $priceStr = if ($h.country -eq "KR") { "{0:N0}원" -f $price } else { "{0:N2}" -f $price }
  $line1 = "{0}  {1}" -f $h.name, $priceStr
  return @{ Line1 = $line1; Line2 = $line2; Color = (Get-HoldingColor $day) }
}

# 종목 정보가 없으면 포트폴리오 합계 프레임 1개로 대체 → 회전은 자연히 정적이 된다.
function Get-WidgetFrames([psobject]$sig) {
  $rows = @($sig.holdings)
  if ($rows.Count -gt 0) {
    return @($rows | Sort-Object -Property { [double]$_.value } -Descending)
  }
  return @([pscustomobject]@{
    name         = "포트폴리오"
    country      = "KR"
    price        = $null
    dayChangePct = [double]$sig.dayChangePct
    totalPnlPct  = [double]$sig.totalPnlPct
    pnl          = [double]$sig.dayPnl
  })
}

# 데이터 폴링 타이머에서 호출 — Read-Signal + stale 판정을 자체적으로 다시 한다
# (Update-Tray 시그니처는 건드리지 않기 위한 짧은 중복).
function Update-WidgetData {
  $sig = Read-Signal
  $stale = $true
  if ($sig -and $sig.at) {
    try { $stale = ([datetime]::UtcNow - ([datetime]$sig.at).ToUniversalTime()).TotalMinutes -gt 10 }
    catch { $stale = $true }
  }

  if (-not $sig -or $stale) {
    $script:WidgetFrames = @([pscustomobject]@{
      name = "StonkPeek"; country = "KR"; price = $null
      dayChangePct = 0; totalPnlPct = 0; pnl = 0
    })
    $script:WidgetIdx = 0
    return
  }

  $script:WidgetFrames = Get-WidgetFrames $sig
  if ($script:WidgetFrames.Count -gt 0) {
    $script:WidgetIdx = $script:WidgetIdx % $script:WidgetFrames.Count
  } else {
    $script:WidgetIdx = 0
  }
}

function Set-WidgetContent {
  if (-not $widget) { return }

  if ($script:Boss) {
    $widget.Line1.Text = "StonkPeek"
    $widget.Line2.Text = "사장님 모드"
    $widget.Line1.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 182)
    $widget.Line2.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 182)
    return
  }

  if ($script:WidgetFrames.Count -eq 0) { return }
  $frame = $script:WidgetFrames[$script:WidgetIdx]
  $fmt = Format-HoldingLines $frame
  $widget.Line1.Text = $fmt.Line1
  $widget.Line2.Text = $fmt.Line2
  $widget.Line1.ForeColor = [System.Drawing.Color]::FromArgb(232, 232, 234)
  $widget.Line2.ForeColor = $fmt.Color
}

function Advance-Widget {
  if (-not $script:WidgetOn) { return }
  if ($script:Boss) { return }
  if ($script:WidgetFrames.Count -eq 0) { return }
  $script:WidgetIdx = ($script:WidgetIdx + 1) % $script:WidgetFrames.Count
  Set-WidgetContent
}

# 커서가 지금 트레이 점 위에 있는지 Shell_NotifyIconGetRect로 판정 (MouseMove 이벤트에 의존하지 않음).
function Test-CursorOverTrayIcon {
  if ($script:TrayHwnd -eq [IntPtr]::Zero) { return $false }
  $rect = New-Object TrayIconRect+RECT
  if (-not [TrayIconRect]::TryGetRect($script:TrayHwnd, [uint32]$script:TrayUid, [ref]$rect)) { return $false }
  $c = [System.Windows.Forms.Cursor]::Position
  return ($c.X -ge $rect.Left -and $c.X -le $rect.Right -and $c.Y -ge $rect.Top -and $c.Y -le $rect.Bottom)
}

# 데이터 폴링과 별개로 짧은 주기로 돌며 hover 진입/이탈을 이 함수 하나로 판정한다.
# 진입은 바로 뜨지 않고 $script:HoverShowDelayMs(500ms)만큼 계속 올라가 있어야 뜬다
# (툴팁처럼 스쳐 지나갈 때 깜빡이지 않도록).
function Update-WidgetHover {
  if (-not $script:WidgetOn) { $script:HoverStartAt = $null; return }
  $hovering = Test-CursorOverTrayIcon

  if (-not $hovering) {
    $script:HoverStartAt = $null
    if ($widget.Visible) { $widget.Visible = $false }
    return
  }

  if ($widget.Visible) { return }
  if (-not $script:HoverStartAt) { $script:HoverStartAt = [DateTime]::UtcNow; return }
  if ((([DateTime]::UtcNow) - $script:HoverStartAt).TotalMilliseconds -ge $script:HoverShowDelayMs) {
    $widget.Location = Get-WidgetLocation $widget.Size
    Set-WidgetContent
    $widget.Visible = $true
  }
}

function Hide-Widget {
  if (-not $widget) { return }
  $widget.Visible = $false
}

# 더블클릭/메뉴: state.json의 holdings를 작은 창에 표로 띄운다. (KR: 상승 빨강 / 하락 파랑)
function Show-Holdings {
  $sig = Read-Signal
  $form = New-Object System.Windows.Forms.Form
  $form.Size = New-Object System.Drawing.Size(470, 340)
  $form.StartPosition = "CenterScreen"
  $form.TopMost = $true
  $form.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 30)

  $lv = New-Object System.Windows.Forms.ListView
  $lv.View = "Details"
  $lv.FullRowSelect = $true
  $lv.Dock = "Fill"
  $lv.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 30)
  $lv.ForeColor = [System.Drawing.Color]::FromArgb(232, 232, 234)
  [void]$lv.Columns.Add("종목", 160)
  $c1 = $lv.Columns.Add("수량", 80);     $c1.TextAlign = "Right"
  $c2 = $lv.Columns.Add("평가금액", 120); $c2.TextAlign = "Right"
  $c3 = $lv.Columns.Add("당일", 70);     $c3.TextAlign = "Right"
  $c4 = $lv.Columns.Add("누적", 70);     $c4.TextAlign = "Right"

  $rows = @($sig.holdings)
  if ($sig -and $rows.Count -gt 0) {
    foreach ($h in ($rows | Sort-Object -Property { [double]$_.value } -Descending)) {
      $q = [double]$h.quantity
      $qStr = if ($q -ge 1) { "{0:N0}" -f $q } else { ("{0:N4}" -f $q).TrimEnd('0').TrimEnd('.') }
      $item = New-Object System.Windows.Forms.ListViewItem([string]$h.name)
      [void]$item.SubItems.Add($qStr)
      [void]$item.SubItems.Add("{0:N0}원" -f [double]$h.value)
      [void]$item.SubItems.Add("{0:+0.00;-0.00}%" -f [double]$h.dayChangePct)
      [void]$item.SubItems.Add("{0:+0.00;-0.00}%" -f [double]$h.totalPnlPct)
      $d = [double]$h.dayChangePct
      $item.ForeColor =
        if ($d -gt 0) { [System.Drawing.Color]::FromArgb(255, 90, 90) }
        elseif ($d -lt 0) { [System.Drawing.Color]::FromArgb(90, 155, 255) }
        else { [System.Drawing.Color]::Gray }
      [void]$lv.Items.Add($item)
    }
    $form.Text = "StonkPeek — 보유 종목 ({0}개)" -f $rows.Count
  } else {
    $form.Text = "StonkPeek — 데몬 꺼짐 (보유 정보 없음)"
  }
  $form.Controls.Add($lv)
  $form.Show()
}

# ── 트레이 구성 ────────────────────────────────────────────────
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$titleItem = New-Object System.Windows.Forms.ToolStripMenuItem("StonkPeek")
$titleItem.Enabled = $false
$menu.Items.Add($titleItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$holdingsItem = New-Object System.Windows.Forms.ToolStripMenuItem("보유 종목…  (더블클릭)")
$holdingsItem.add_Click({ Show-Holdings }) | Out-Null
$menu.Items.Add($holdingsItem) | Out-Null

$widgetItem = New-Object System.Windows.Forms.ToolStripMenuItem("시세 위젯 (트레이 점에 마우스 올리면 표시)")
$widgetItem.CheckOnClick = $true
$widgetItem.Checked = $script:WidgetOn
$widgetItem.add_Click({
  $script:WidgetOn = $widgetItem.Checked
  if (-not $script:WidgetOn) { Hide-Widget }
}) | Out-Null
$menu.Items.Add($widgetItem) | Out-Null

# 보스키 폴백 (단축키가 다른 앱과 충돌할 때를 대비한 수동 토글).
$bossItem = New-Object System.Windows.Forms.ToolStripMenuItem(
  ("사장님 모드  (Ctrl+Alt+{0})" -f $BossKey.ToUpper()))
$bossItem.add_Click({ Toggle-Boss }) | Out-Null
$menu.Items.Add($bossItem) | Out-Null

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem("종료")
$exitItem.add_Click({
  $timer.Stop()
  $rotateTimer.Stop()
  $hoverTimer.Stop()
  $notify.Visible = $false
  $notify.Dispose()
  if ($widget) { $widget.Close(); $widget.Dispose() }
  if ($script:Hotkey) { $script:Hotkey.Dispose() }
  $appContext.ExitThread()
}) | Out-Null
$menu.Items.Add($exitItem) | Out-Null
$notify.ContextMenuStrip = $menu
$notify.add_MouseDoubleClick({ Show-Holdings }) | Out-Null

# NotifyIcon의 실제 hWnd/uID를 리플렉션으로 꺼낸다 (Shell_NotifyIconGetRect 호출에 필요).
# Visible=true로 이미 네이티브 윈도우/아이콘이 등록된 뒤라야 유효한 값이 나온다.
$niWindowField = [System.Windows.Forms.NotifyIcon].GetField("window", [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
$niIdField = [System.Windows.Forms.NotifyIcon].GetField("id", [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
try {
  $script:TrayHwnd = ($niWindowField.GetValue($notify)).Handle
  $script:TrayUid = [uint32]$niIdField.GetValue($notify)
} catch { $script:TrayHwnd = [IntPtr]::Zero }

$widget = New-Widget
$widget.Visible = $false   # 마우스를 올리기 전까지는 숨김

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [Math]::Max(1, $IntervalSec) * 1000
$timer.add_Tick({ try { Update-Tray; Update-WidgetData; if ($widget.Visible) { Set-WidgetContent } } catch { } }) | Out-Null

$rotateTimer = New-Object System.Windows.Forms.Timer
$rotateTimer.Interval = $script:RotateIntervalMs
$rotateTimer.add_Tick({ try { Advance-Widget } catch { } }) | Out-Null

# hover 상태 폴링 (진입·이탈 둘 다 이걸로 판정 — Shell_NotifyIconGetRect 기반, MouseMove 불필요).
# 100ms로 짧게 돌아야 500ms 지연이 매끄럽게 느껴진다 (300ms면 오차가 최대 +300ms까지 남음).
$hoverTimer = New-Object System.Windows.Forms.Timer
$hoverTimer.Interval = 100
$hoverTimer.add_Tick({ try { Update-WidgetHover } catch { } }) | Out-Null

# 전역 단축키 등록 (MOD_CONTROL | MOD_ALT = 0x2 | 0x1 = 3). 충돌 시 메뉴 폴백 사용.
try {
  $vk = [uint32][int]([char]([string]$BossKey).ToUpper()[0])
  $script:Hotkey = New-Object HotkeyWindow ([uint32]3), $vk, 1
  $script:Hotkey.add_HotkeyPressed({ Toggle-Boss })
} catch { }

Update-Tray          # 첫 화면을 5초 기다리지 않도록 즉시 1회
Update-WidgetData
$timer.Start()
$rotateTimer.Start()
$hoverTimer.Start()

$appContext = New-Object System.Windows.Forms.ApplicationContext
[System.Windows.Forms.Application]::Run($appContext)
