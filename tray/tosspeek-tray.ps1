<#
  TossPeek — Windows 트레이 아이콘 + 종목별 자동 회전 위젯 (화면형 싱크)

  계좌를 쳐다보지 말고, 느껴라. 시계 옆 점 하나가 등락 색으로 바뀐다.
  그 점에 마우스를 0.5초 올리고 있으면 작업표시줄 코너에 보유 종목이
  하나씩 자동으로 돌아가며 종목명/현재가/당일·누적 수익률/손익이 뜬다
  (날씨 위젯처럼) — 커서를 치우면 사라진다. 숫자만 보여주는 단순한
  정보 표시일 뿐, 별도 알림(풍선 등)은 전혀 띄우지 않는다. 데몬
  (`tosspeek start` / `tosspeek demo`)이 쓰는 ~/.tosspeek/state.json을
  주기적으로 읽어 갱신하는 읽기 전용 소비자. API 호출 없음, 키 없음.

  직접 실행:
    powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
      -File tray\tosspeek-tray.ps1
  보통은 `tosspeek tray` 가 이 스크립트를 대신 띄운다.
#>
param(
  [int]$IntervalSec = 5,
  # 보스키: Ctrl+Alt+<BossKey> 전역 단축키로 즉시 회색(사장님 모드) 토글. 한 글자.
  [string]$BossKey = "H",
  [string]$StatePath = (Join-Path $env:USERPROFILE ".tosspeek\state.json")
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

# 위젯용 커스텀 컨트롤:
#  - NoActivateForm: 보여줄 때 포커스를 뺏지 않는다(WS_EX_NOACTIVATE). 작업표시줄에도 안 뜬다.
#  - DoubleBufferedPanel: 커스텀 페인트 시 깜빡임 없도록 더블 버퍼링.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Windows.Forms;
public class NoActivateForm : Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams {
    get {
      const int WS_EX_NOACTIVATE = 0x08000000;
      const int WS_EX_TOOLWINDOW = 0x00000080;
      var cp = base.CreateParams;
      cp.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
      return cp;
    }
  }
}
public class DoubleBufferedPanel : Panel {
  public DoubleBufferedPanel() {
    DoubleBuffered = true;
    SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
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
    $titleItem.Text = "TossPeek — 사장님 모드 (단축키로 복귀)"
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
    $titleItem.Text = "TossPeek — 데몬 꺼짐"
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
$script:WidgetStale      = $false
$script:RotateIntervalMs = 4000
$script:TrayHwnd         = [IntPtr]::Zero   # Shell_NotifyIconGetRect용, 시작 시퀀스 끝에서 채움
$script:TrayUid          = 0
$script:HoverStartAt     = $null   # hover가 시작된 시각 — 이후 500ms 지나야 위젯을 띄운다
$script:HoverShowDelayMs = 500
$script:HoverMiss        = 0       # 연속 "안 올려짐" 카운트 — 깜빡임 방지용 유예
$script:TrayRectCache    = $null   # 마지막으로 성공한 아이콘 사각형 (일시적 조회 실패 대비)
$script:WidgetScale      = 1.0     # DPI 배율 (New-Widget에서 실제 값으로 갱신)
$script:WidgetPanel      = $null   # 커스텀 페인트 대상
# 현재 그릴 내용. Set-WidgetContent가 채우고 패널을 Invalidate한다.
$script:WidgetPaint      = @{
  Name = "TossPeek"; Price = $null; Day = ""; Sub = ""
  Accent = [System.Drawing.Color]::FromArgb(150, 150, 156); Index = 0; Total = 0
}

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

# 폼을 둥근 모서리로 클립한다. GraphicsPath로 라운드 사각형을 만들어 Region으로 지정.
function Set-RoundRegion($form, [int]$radius) {
  $d = $radius * 2
  $w = $form.Width; $h = $form.Height
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddArc(0, 0, $d, $d, 180, 90)
  $path.AddArc($w - $d, 0, $d, $d, 270, 90)
  $path.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
  $path.AddArc(0, $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  if ($form.Region) { $form.Region.Dispose() }
  $form.Region = New-Object System.Drawing.Region $path
  $path.Dispose()
}

# 위젯 한 프레임을 직접 그리는 페인트 핸들러. 장식(악센트 바·화살표·회전 점) 없이
# 텍스트만 — 두 줄, 좌: 종목명/당일% · 우: 현재가/누적·손익. 폰트·줄간격으로 정돈.
$script:WidgetPaintHandler = {
  param($sender, $e)
  $data = $script:WidgetPaint
  if (-not $data) { return }
  $g = $e.Graphics
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
  $s = $script:WidgetScale
  $W = $sender.ClientSize.Width
  $H = $sender.ClientSize.Height

  $g.Clear([System.Drawing.Color]::FromArgb(30, 30, 33))

  $padL = [int](15 * $s); $padR = [int](14 * $s)
  $contentX = $padL; $contentW = $W - $padL - $padR

  $nameFont = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5)
  $priceFont = New-Object System.Drawing.Font("Segoe UI", 9)
  $dayFont = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
  $subFont = New-Object System.Drawing.Font("Segoe UI", 8.5)

  $nameBrush   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 240, 243))
  $priceBrush  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(158, 158, 166))
  $subBrush    = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(140, 140, 148))
  $accentBrush = New-Object System.Drawing.SolidBrush $data.Accent

  $sfNear = New-Object System.Drawing.StringFormat
  $sfNear.Alignment = [System.Drawing.StringAlignment]::Near
  $sfNear.LineAlignment = [System.Drawing.StringAlignment]::Center
  $sfNear.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
  $sfNear.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
  $sfFar = New-Object System.Drawing.StringFormat
  $sfFar.Alignment = [System.Drawing.StringAlignment]::Far
  $sfFar.LineAlignment = [System.Drawing.StringAlignment]::Center
  $sfFar.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

  # 두 줄의 세로 리듬: 위/아래 여백을 두고 가운데 정렬로 그린다.
  $rowH = [int](21 * $s)
  $gapY = [int](3 * $s)
  $blockH = $rowH * 2 + $gapY
  $topY = [int](($H - $blockH) / 2)
  $row1Y = $topY; $row2Y = $topY + $rowH + $gapY
  $rect1 = New-Object System.Drawing.RectangleF $contentX, $row1Y, $contentW, $rowH
  $rect2 = New-Object System.Drawing.RectangleF $contentX, $row2Y, $contentW, $rowH

  # 우측(현재가/누적·손익)을 먼저 그리고, 남는 폭에 좌측(종목명/당일%)을 줄임말 처리해 그린다.
  $priceW = 0
  if ($data.Price) {
    $priceW = [int][Math]::Ceiling($g.MeasureString([string]$data.Price, $priceFont).Width)
    $g.DrawString([string]$data.Price, $priceFont, $priceBrush, $rect1, $sfFar)
  }
  $subW = 0
  if ($data.Sub) {
    $subW = [int][Math]::Ceiling($g.MeasureString([string]$data.Sub, $subFont).Width)
    $g.DrawString([string]$data.Sub, $subFont, $subBrush, $rect2, $sfFar)
  }
  $gapX = [int](12 * $s)
  $nameRect = New-Object System.Drawing.RectangleF $contentX, $row1Y, ([Math]::Max(1, $contentW - $priceW - $gapX)), $rowH
  $dayRect  = New-Object System.Drawing.RectangleF $contentX, $row2Y, ([Math]::Max(1, $contentW - $subW - $gapX)), $rowH
  $g.DrawString([string]$data.Name, $nameFont, $nameBrush, $nameRect, $sfNear)
  if ($data.Day) { $g.DrawString([string]$data.Day, $dayFont, $accentBrush, $dayRect, $sfNear) }

  $nameFont.Dispose(); $priceFont.Dispose(); $dayFont.Dispose(); $subFont.Dispose()
  $nameBrush.Dispose(); $priceBrush.Dispose(); $subBrush.Dispose(); $accentBrush.Dispose()
  $sfNear.Dispose(); $sfFar.Dispose()
}

function New-Widget {
  $w = New-Object NoActivateForm
  $w.FormBorderStyle = "None"
  $w.ShowInTaskbar = $false
  $w.TopMost = $true
  $w.StartPosition = "Manual"
  $w.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
  $w.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 33)
  $w.Opacity = 0.96

  [void]$w.Handle   # 핸들을 강제로 만들어 DeviceDpi를 읽는다
  $script:WidgetScale = [double]$w.DeviceDpi / 96.0
  if ($script:WidgetScale -le 0) { $script:WidgetScale = 1.0 }
  $w.Size = New-Object System.Drawing.Size ([int](244 * $script:WidgetScale)), ([int](58 * $script:WidgetScale))

  $panel = New-Object DoubleBufferedPanel
  $panel.Dock = "Fill"
  $panel.BackColor = $w.BackColor
  $panel.add_Paint($script:WidgetPaintHandler)
  $w.Controls.Add($panel)
  $script:WidgetPanel = $panel

  Set-RoundRegion $w ([int](8 * $script:WidgetScale))
  $w.Location = Get-WidgetLocation $w.Size
  return $w
}

# KR 관습(상승 빨강/하락 파랑) — Show-Holdings의 색 규칙과 동일하게 중복 구현.
# cfg.colorScheme("us")는 mood.ts에만 있고 Signal까지 안 넘어오므로 여기선 못 씀.
function Get-HoldingColor([double]$dayChangePct) {
  if ($dayChangePct -gt 0) { return [System.Drawing.Color]::FromArgb(255, 90, 90) }
  elseif ($dayChangePct -lt 0) { return [System.Drawing.Color]::FromArgb(90, 155, 255) }
  else { return [System.Drawing.Color]::FromArgb(180, 180, 182) }
}

# 종목 한 건 → 위젯 페인트용 필드 묶음. 부호 있는 % 로만 표기(화살표 없음).
#   Day: "+6.76%" / Sub: "누적 +85.04%  ·  +684원"
function Format-HoldingLines([psobject]$h) {
  $day = [double]$h.dayChangePct
  $tot = [double]$h.totalPnlPct
  $pnl = [double]$h.pnl

  $dayStr = "{0:+0.00;-0.00}%" -f $day
  $sub = "누적 {0:+0.00;-0.00}%   ·   {1:+#,##0;-#,##0}원" -f $tot, $pnl

  $priceStr = $null
  if ($null -ne $h.price) {
    $price = [double]$h.price
    $priceStr = if ($h.country -eq "KR") { "{0:N0}원" -f $price } else { "{0:N2}" -f $price }
  }
  return @{ Name = [string]$h.name; Price = $priceStr; Day = $dayStr; Sub = $sub; Accent = (Get-HoldingColor $day) }
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
    $script:WidgetStale = $true
    $script:WidgetFrames = @()
    $script:WidgetIdx = 0
    return
  }

  $script:WidgetStale = $false
  $script:WidgetFrames = Get-WidgetFrames $sig
  if ($script:WidgetFrames.Count -gt 0) {
    $script:WidgetIdx = $script:WidgetIdx % $script:WidgetFrames.Count
  } else {
    $script:WidgetIdx = 0
  }
}

# 보스/데몬꺼짐 같은 무채색 안내 프레임을 그린다.
function Set-WidgetPlaceholder([string]$title, [string]$sub) {
  $script:WidgetPaint = @{
    Name = $title; Price = $null; Day = ""; Sub = $sub
    Accent = [System.Drawing.Color]::FromArgb(150, 150, 156); Index = 0; Total = 0
  }
  if ($script:WidgetPanel) { $script:WidgetPanel.Invalidate() }
}

function Set-WidgetContent {
  if (-not $widget) { return }

  if ($script:Boss) { Set-WidgetPlaceholder "TossPeek" "사장님 모드"; return }
  if ($script:WidgetStale -or $script:WidgetFrames.Count -eq 0) {
    Set-WidgetPlaceholder "TossPeek" "데몬 꺼짐 — tosspeek start"; return
  }

  $frame = $script:WidgetFrames[$script:WidgetIdx]
  $fmt = Format-HoldingLines $frame
  $script:WidgetPaint = @{
    Name = $fmt.Name; Price = $fmt.Price; Day = $fmt.Day; Sub = $fmt.Sub
    Accent = $fmt.Accent; Index = $script:WidgetIdx; Total = $script:WidgetFrames.Count
  }
  if ($script:WidgetPanel) { $script:WidgetPanel.Invalidate() }
}

function Advance-Widget {
  if (-not $script:WidgetOn) { return }
  if ($script:Boss) { return }
  if ($script:WidgetFrames.Count -eq 0) { return }
  $script:WidgetIdx = ($script:WidgetIdx + 1) % $script:WidgetFrames.Count
  Set-WidgetContent
}

# 커서가 지금 트레이 점 위에 있는지 Shell_NotifyIconGetRect로 판정 (MouseMove 이벤트에 의존하지 않음).
# 조회가 일시적으로 실패하면(아이콘 갱신 순간 등) 마지막 성공한 사각형을 재사용하고,
# 경계 흔들림을 흡수하려고 약간의 여유 마진을 둔다 — 위젯이 깜빡이지 않도록.
function Test-CursorOverTrayIcon {
  if ($script:TrayHwnd -eq [IntPtr]::Zero) { return $false }
  $rect = New-Object TrayIconRect+RECT
  if ([TrayIconRect]::TryGetRect($script:TrayHwnd, [uint32]$script:TrayUid, [ref]$rect)) {
    $script:TrayRectCache = $rect
  } elseif ($null -ne $script:TrayRectCache) {
    $rect = $script:TrayRectCache
  } else {
    return $false
  }
  $m = 4   # 여유 마진(px)
  $c = [System.Windows.Forms.Cursor]::Position
  return ($c.X -ge $rect.Left - $m -and $c.X -le $rect.Right + $m -and $c.Y -ge $rect.Top - $m -and $c.Y -le $rect.Bottom + $m)
}

# 데이터 폴링과 별개로 짧은 주기로 돌며 hover 진입/이탈을 이 함수 하나로 판정한다.
# 진입은 바로 뜨지 않고 $script:HoverShowDelayMs(500ms)만큼 계속 올라가 있어야 뜨고,
# 이탈은 연속 3회(≈300ms) 놓쳐야 숨긴다 — 스쳐 지나갈 때/조회 실패 순간에 깜빡이지 않도록.
function Update-WidgetHover {
  if (-not $script:WidgetOn) { $script:HoverStartAt = $null; $script:HoverMiss = 0; return }

  if (Test-CursorOverTrayIcon) {
    $script:HoverMiss = 0
    if (-not $widget.Visible) {
      if (-not $script:HoverStartAt) { $script:HoverStartAt = [DateTime]::UtcNow; return }
      if ((([DateTime]::UtcNow) - $script:HoverStartAt).TotalMilliseconds -ge $script:HoverShowDelayMs) {
        $widget.Location = Get-WidgetLocation $widget.Size
        Set-WidgetContent
        $widget.Visible = $true
      }
    }
    return
  }

  # 커서가 아이콘 밖 — 유예 후 숨김
  $script:HoverStartAt = $null
  if ($widget.Visible) {
    $script:HoverMiss++
    if ($script:HoverMiss -ge 3) { $widget.Visible = $false; $script:HoverMiss = 0 }
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
    $form.Text = "TossPeek — 보유 종목 ({0}개)" -f $rows.Count
  } else {
    $form.Text = "TossPeek — 데몬 꺼짐 (보유 정보 없음)"
  }
  $form.Controls.Add($lv)
  $form.Show()
}

# ── 설정 (배포용: 사용자가 CLI/JSON을 직접 안 만져도 되게) ──────────
# config.ts의 탐색 순서(cwd → 프로젝트 루트 → ~/.tosspeek) 중 트레이 입장에서
# 결정적인 두 곳만 그대로 따라간다 — cwd는 로그인 자동실행 땐 System32라 의미 없음.
function Get-ProjectRoot { Split-Path -Parent $PSScriptRoot }

function Get-ConfigPath {
  $projectConfig = Join-Path (Get-ProjectRoot) "tosspeek.config.json"
  if (Test-Path $projectConfig) { return $projectConfig }
  return (Join-Path $env:USERPROFILE ".tosspeek\config.json")
}

function Get-NodeExe {
  $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return "node.exe"   # PATH에 맡긴다
}

function Get-DistCli { Join-Path (Get-ProjectRoot) "dist\cli.js" }

# 설정 파일을 읽어 PSCustomObject로 반환 (없으면 빈 객체 — 없는 필드는 데몬 쪽 기본값이 채운다).
function Read-ConfigJson {
  $path = Get-ConfigPath
  if (Test-Path $path) {
    try {
      $raw = Get-Content -Path $path -Raw -Encoding UTF8
      if (-not [string]::IsNullOrWhiteSpace($raw)) { return $raw | ConvertFrom-Json }
    } catch { }
  }
  return [pscustomobject]@{}
}

# 폼에서 편집하는 필드만 기존 JSON 위에 덮어써서 저장한다 — 안 건드리는 필드(salary/기타 싱크
# 등)는 그대로 보존된다. Node가 쓰는 것과 동일하게 BOM 없는 UTF-8로 쓴다.
function Save-ConfigJson([psobject]$cfg, [hashtable]$edits) {
  foreach ($key in $edits.Keys) {
    if ($key -eq "toss") {
      if (-not $cfg.PSObject.Properties["toss"]) { $cfg | Add-Member -NotePropertyName toss -NotePropertyValue ([pscustomobject]@{}) }
      foreach ($tk in $edits["toss"].Keys) {
        if ($cfg.toss.PSObject.Properties[$tk]) { $cfg.toss.$tk = $edits["toss"][$tk] }
        else { $cfg.toss | Add-Member -NotePropertyName $tk -NotePropertyValue $edits["toss"][$tk] }
      }
    } elseif ($cfg.PSObject.Properties[$key]) {
      $cfg.$key = $edits[$key]
    } else {
      $cfg | Add-Member -NotePropertyName $key -NotePropertyValue $edits[$key]
    }
  }
  $path = Get-ConfigPath
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $json = $cfg | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
  return $path
}

# 실행 중인 데몬(dist/cli.js ... start)을 찾아 죽이고, 숨김창으로 다시 띄운다.
# cli.ts의 spawnDetachedViaStart와 동일한 원리(-WindowStyle Hidden) — 창이 전혀 안 보인다.
function Restart-Daemon {
  $cli = Get-DistCli
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like ("*" + [regex]::Escape($cli) + "*start*") } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 400
  Start-Process -FilePath (Get-NodeExe) -ArgumentList @($cli, "start") -WindowStyle Hidden
}

function Test-AutostartInstalled {
  Test-Path (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\tosspeek-autostart.vbs")
}

# install-startup/uninstall-startup은 cli.ts에 이미 있는 로직 — 여기서 중복 구현하지 않고
# 그대로 호출한다(짧게 끝나는 명령이라 -Wait로 완료를 기다린 뒤 메뉴 체크 상태만 갱신).
function Set-AutostartRegistration([bool]$enable) {
  $cmd = if ($enable) { "install-startup" } else { "uninstall-startup" }
  Start-Process -FilePath (Get-NodeExe) -ArgumentList @((Get-DistCli), $cmd) -WindowStyle Hidden -Wait
}

# 배포용 설정 창: 데모/실계좌 전환, 토스 API 키 등록, 색 스킴·폴링 주기. 저장 시 원본 JSON의
# 다른 필드(salary·hue·openrgb 등)는 건드리지 않는다 — 고급 설정은 여전히 JSON 직접 편집.
function Show-Settings {
  $cfg = Read-ConfigJson
  $toss = if ($cfg.PSObject.Properties["toss"]) { $cfg.toss } else { [pscustomobject]@{} }

  $f = New-Object System.Windows.Forms.Form
  $f.Text = "TossPeek 설정"
  $f.Size = New-Object System.Drawing.Size(400, 400)
  $f.StartPosition = "CenterScreen"
  $f.FormBorderStyle = "FixedDialog"
  $f.MaximizeBox = $false; $f.MinimizeBox = $false
  $f.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 33)
  $f.ForeColor = [System.Drawing.Color]::FromArgb(230, 230, 233)
  $f.Font = New-Object System.Drawing.Font("Segoe UI", 9)

  $y = 15
  function Add-Label($text, $yPos) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point(15, $yPos); $l.AutoSize = $true
    $f.Controls.Add($l); return $l
  }
  function Add-TextBox($yPos, [bool]$masked = $false) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point(15, ($yPos + 18)); $t.Width = 355
    $t.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 49)
    $t.ForeColor = [System.Drawing.Color]::White
    $t.BorderStyle = "FixedSingle"
    if ($masked) { $t.PasswordChar = '*' }
    $f.Controls.Add($t); return $t
  }

  Add-Label "데이터 소스" $y | Out-Null
  $y += 20
  $rbMock = New-Object System.Windows.Forms.RadioButton
  $rbMock.Text = "Mock (데모, 키 불필요)"; $rbMock.Location = New-Object System.Drawing.Point(15, $y); $rbMock.AutoSize = $true
  $rbToss = New-Object System.Windows.Forms.RadioButton
  $rbToss.Text = "토스증권 (실계좌 조회)"; $rbToss.Location = New-Object System.Drawing.Point(170, $y); $rbToss.AutoSize = $true
  $f.Controls.Add($rbMock); $f.Controls.Add($rbToss)
  if ($cfg.source -eq "toss") { $rbToss.Checked = $true } else { $rbMock.Checked = $true }
  $y += 32

  Add-Label "토스 Client ID" $y | Out-Null
  $tbClientId = Add-TextBox $y
  $tbClientId.Text = [string]$toss.clientId
  $y += 44

  Add-Label "토스 Client Secret" $y | Out-Null
  $tbSecret = Add-TextBox $y $true
  $tbSecret.Text = [string]$toss.clientSecret
  $y += 44

  Add-Label "계좌번호 (비우면 첫 계좌 자동 사용)" $y | Out-Null
  $tbAccount = Add-TextBox $y
  $tbAccount.Text = [string]$toss.accountNo
  $y += 44

  Add-Label "색 스킴" $y | Out-Null
  $cmbScheme = New-Object System.Windows.Forms.ComboBox
  $cmbScheme.Location = New-Object System.Drawing.Point(15, ($y + 18)); $cmbScheme.Width = 170
  $cmbScheme.DropDownStyle = "DropDownList"
  [void]$cmbScheme.Items.Add("한국 (빨강=상승)")
  [void]$cmbScheme.Items.Add("미국 (초록=상승)")
  $cmbScheme.SelectedIndex = if ($cfg.colorScheme -eq "us") { 1 } else { 0 }
  $f.Controls.Add($cmbScheme)

  $lbl2 = New-Object System.Windows.Forms.Label
  $lbl2.Text = "폴링 주기(초)"; $lbl2.Location = New-Object System.Drawing.Point(200, $y); $lbl2.AutoSize = $true
  $f.Controls.Add($lbl2)
  $numPoll = New-Object System.Windows.Forms.NumericUpDown
  $numPoll.Location = New-Object System.Drawing.Point(200, ($y + 18)); $numPoll.Width = 80
  $numPoll.Minimum = 3; $numPoll.Maximum = 3600
  $numPoll.Value = if ($cfg.pollIntervalSec) { [Math]::Max(3, [Math]::Min(3600, [int]$cfg.pollIntervalSec)) } else { 60 }
  $f.Controls.Add($numPoll)
  $y += 50

  $lblStatus = New-Object System.Windows.Forms.Label
  $lblStatus.Location = New-Object System.Drawing.Point(15, $y); $lblStatus.Size = New-Object System.Drawing.Size(355, 20)
  $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 158)
  $lblStatus.Text = "설정 파일: {0}" -f (Get-ConfigPath)
  $lblStatus.AutoEllipsis = $true
  $f.Controls.Add($lblStatus)
  $y += 34

  $btnSave = New-Object System.Windows.Forms.Button
  $btnSave.Text = "저장"; $btnSave.Location = New-Object System.Drawing.Point(95, $y); $btnSave.Size = New-Object System.Drawing.Size(80, 30)
  $btnSaveRestart = New-Object System.Windows.Forms.Button
  $btnSaveRestart.Text = "저장 후 재시작"; $btnSaveRestart.Location = New-Object System.Drawing.Point(180, $y); $btnSaveRestart.Size = New-Object System.Drawing.Size(110, 30)
  $btnCancel = New-Object System.Windows.Forms.Button
  $btnCancel.Text = "취소"; $btnCancel.Location = New-Object System.Drawing.Point(295, $y); $btnCancel.Size = New-Object System.Drawing.Size(75, 30)
  foreach ($b in @($btnSave, $btnSaveRestart, $btnCancel)) {
    $b.BackColor = [System.Drawing.Color]::FromArgb(55, 55, 60)
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatStyle = "Flat"
    $f.Controls.Add($b)
  }

  $doSave = {
    $edits = @{
      source = if ($rbToss.Checked) { "toss" } else { "mock" }
      colorScheme = if ($cmbScheme.SelectedIndex -eq 1) { "us" } else { "kr" }
      pollIntervalSec = [int]$numPoll.Value
      toss = @{ clientId = $tbClientId.Text.Trim(); clientSecret = $tbSecret.Text.Trim(); accountNo = $tbAccount.Text.Trim() }
    }
    Save-ConfigJson $cfg $edits | Out-Null
  }
  $btnSave.add_Click({ & $doSave; $f.Close() })
  $btnSaveRestart.add_Click({ & $doSave; Restart-Daemon; $f.Close() })
  $btnCancel.add_Click({ $f.Close() })

  $f.ShowDialog() | Out-Null
}

# ── 트레이 구성 ────────────────────────────────────────────────
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$titleItem = New-Object System.Windows.Forms.ToolStripMenuItem("TossPeek")
$titleItem.Enabled = $false
$menu.Items.Add($titleItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$settingsItem = New-Object System.Windows.Forms.ToolStripMenuItem("설정…")
$settingsItem.add_Click({ Show-Settings }) | Out-Null
$menu.Items.Add($settingsItem) | Out-Null

$restartItem = New-Object System.Windows.Forms.ToolStripMenuItem("데몬 재시작")
$restartItem.add_Click({ Restart-Daemon }) | Out-Null
$menu.Items.Add($restartItem) | Out-Null

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

$autostartItem = New-Object System.Windows.Forms.ToolStripMenuItem("컴퓨터 켤 때 자동 실행")
$autostartItem.CheckOnClick = $true
$autostartItem.Checked = Test-AutostartInstalled
$autostartItem.add_Click({
  $autostartItem.Enabled = $false
  Set-AutostartRegistration $autostartItem.Checked
  $autostartItem.Checked = Test-AutostartInstalled
  $autostartItem.Enabled = $true
}) | Out-Null
$menu.Items.Add($autostartItem) | Out-Null

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
