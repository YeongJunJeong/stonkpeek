// TossPeek — 크롬 툴바 확장 (화면형 싱크, 읽기 전용)
//
// 데몬의 HttpSink(localhost:17654)가 노출하는 최신 Signal을 폴링해
// 툴바 아이콘을 무드 색 점으로, 배지를 등락률로 칠한다. 옆 사람 눈엔 그냥 확장 아이콘.
//
// 보스키: 단축키(Ctrl+Shift+9, chrome://extensions/shortcuts 에서 변경) 또는 아이콘 클릭으로
// 즉시 회색/숨김 토글. 데몬·증권사 키는 이 확장 어디에도 없다.

const ENDPOINT = "http://127.0.0.1:17654/signal";
const POLL_ALARM = "tosspeek-poll";
const POLL_MINUTES = 0.5; // 30초
const STALE_MS = 10 * 60 * 1000;

// 서비스워커가 깰 때마다(설치·시작·알람) 폴링을 보장한다.
chrome.runtime.onInstalled.addListener(bootstrap);
chrome.runtime.onStartup.addListener(bootstrap);
bootstrap();

function bootstrap() {
  chrome.alarms.create(POLL_ALARM, { periodInMinutes: POLL_MINUTES });
  refresh();
}

chrome.alarms.onAlarm.addListener((a) => {
  if (a.name === POLL_ALARM) return refresh();
});

// 보스키 — 단축키로 회색/숨김 토글. (아이콘 클릭은 팝업이 열리므로 단축키 전용)
chrome.commands.onCommand.addListener((cmd) => {
  if (cmd === "toggle-stealth") return toggleStealth();
});

async function toggleStealth() {
  const { stealth } = await chrome.storage.session.get("stealth");
  await chrome.storage.session.set({ stealth: !stealth });
  return refresh();
}

async function refresh() {
  const { stealth } = await chrome.storage.session.get("stealth");
  if (stealth) {
    return paint({ gray: true, badge: "", title: "TossPeek — 숨김 (단축키로 복귀)" });
  }
  try {
    const res = await fetch(ENDPOINT, { cache: "no-store" });
    const sig = await res.json();
    if (!sig || !sig.at || Date.now() - Date.parse(sig.at) > STALE_MS) return offline();

    const day = Number(sig.dayChangePct) || 0;
    const tot = Number(sig.totalPnlPct) || 0;
    const badge = (day >= 0 ? "+" : "-") + Math.round(Math.abs(day));
    const title =
      `${pct(day)} ${sig.message || ""}  (누적 ${pct(tot, 1)})` +
      (sig.offDuty ? "  · 퇴근각" : "");
    return paint({ color: sig.color, badge, title });
  } catch {
    return offline();
  }
}

function offline() {
  return paint({ gray: true, badge: "", title: "TossPeek: 데몬 꺼짐 — tosspeek start" });
}

function pct(v, digits = 2) {
  return (v >= 0 ? "+" : "") + v.toFixed(digits) + "%";
}

async function paint({ color, gray, badge, title }) {
  const c = gray || !color ? { r: 128, g: 128, b: 128 } : color;
  await chrome.action.setIcon({ imageData: dotIcon(c) });
  await chrome.action.setBadgeText({ text: badge || "" });
  await chrome.action.setBadgeBackgroundColor({ color: "#333333" });
  if (chrome.action.setBadgeTextColor) {
    await chrome.action.setBadgeTextColor({ color: "#ffffff" });
  }
  await chrome.action.setTitle({ title: title || "TossPeek" });
}

// OffscreenCanvas로 무드 색 점을 그려 16/32px ImageData를 만든다 (PNG 파일 불필요).
function dotIcon(c) {
  const out = {};
  for (const s of [16, 32]) {
    const canvas = new OffscreenCanvas(s, s);
    const g = canvas.getContext("2d");
    g.clearRect(0, 0, s, s);
    const pad = s * 0.12;
    g.beginPath();
    g.arc(s / 2, s / 2, (s - pad * 2) / 2, 0, Math.PI * 2);
    g.fillStyle = `rgb(${c.r | 0}, ${c.g | 0}, ${c.b | 0})`;
    g.fill();
    g.lineWidth = Math.max(1, s * 0.06);
    g.strokeStyle = "rgba(255, 255, 255, 0.35)";
    g.stroke();
    out[s] = g.getImageData(0, 0, s, s);
  }
  return out;
}
