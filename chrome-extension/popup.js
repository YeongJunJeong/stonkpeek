// TossPeek 팝업 — 데몬의 localhost 피드에서 최신 Signal을 읽어 보유 종목 리스트를 그린다.
const ENDPOINT = "http://127.0.0.1:17654/signal";

function pct(v, d = 2) { return (v >= 0 ? "+" : "") + Number(v).toFixed(d) + "%"; }
function cls(v) { return v > 0 ? "up" : v < 0 ? "down" : "flat"; } // KR: 상승 빨강 / 하락 파랑
function won(n) { return Math.round(n).toLocaleString("ko-KR") + "원"; }
function qtyStr(q) {
  q = Number(q);
  return q >= 1 ? q.toLocaleString("ko-KR") : q.toFixed(4).replace(/0+$/, "").replace(/\.$/, "");
}

async function load() {
  const moodEl = document.getElementById("mood");
  const totalEl = document.getElementById("total");
  const listEl = document.getElementById("list");
  try {
    const res = await fetch(ENDPOINT, { cache: "no-store" });
    const sig = await res.json();
    if (!sig || !sig.at) throw new Error("no data");

    moodEl.textContent = `${sig.emoji || ""} ${sig.message || ""}  ${pct(sig.dayChangePct)}`;
    moodEl.className = "mood " + cls(sig.dayChangePct);
    totalEl.textContent = `누적 ${pct(sig.totalPnlPct, 1)}${sig.offDuty ? "  · 퇴근각" : ""}`;

    const hs = (sig.holdings || []).slice().sort((a, b) => b.value - a.value);
    if (hs.length === 0) {
      listEl.innerHTML = '<li class="empty">보유 종목 정보가 없습니다.</li>';
      return;
    }
    listEl.replaceChildren();
    for (const h of hs) {
      const li = document.createElement("li");

      const nm = document.createElement("span");
      nm.className = "nm";
      nm.textContent = h.name;
      const q = document.createElement("span");
      q.className = "qty";
      q.textContent = `  ${qtyStr(h.quantity)}주`;
      nm.appendChild(q);

      const day = document.createElement("span");
      day.className = "pct " + cls(h.dayChangePct);
      day.textContent = pct(h.dayChangePct);

      const tot = document.createElement("span");
      tot.className = "pct " + cls(h.totalPnlPct);
      tot.textContent = pct(h.totalPnlPct);

      li.append(nm, day, tot);
      li.title = `${h.name} · 평가 ${won(h.value)} · 당일 ${pct(h.dayChangePct)} · 누적 ${pct(h.totalPnlPct)}`;
      listEl.appendChild(li);
    }
  } catch {
    moodEl.textContent = "TossPeek";
    totalEl.textContent = "";
    listEl.innerHTML =
      '<li class="empty">데몬이 꺼져 있어요.<br>다른 창에서 <b>tosspeek start</b> 를 실행하세요.</li>';
  }
}

load();
