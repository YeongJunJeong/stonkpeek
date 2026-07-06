import type { Config } from "../config.js";
import { computeSignal } from "./mood.js";
import { writeState } from "./state.js";
import type { Sink, Source } from "./types.js";

export interface EngineHandle {
  stop(): Promise<void>;
}

/** 소스를 주기적으로 폴링해 Signal을 만들고 모든 싱크에 부채질한다. */
export async function runEngine(
  cfg: Config,
  source: Source,
  sinks: Sink[],
): Promise<EngineHandle> {
  const live: Sink[] = [];
  for (const sink of sinks) {
    try {
      await sink.init?.();
      live.push(sink);
    } catch (err) {
      console.error(`[tosspeek] 싱크 '${sink.name}' 초기화 실패 — 건너뜀:`, (err as Error).message);
    }
  }

  const tick = async () => {
    try {
      const snapshot = await source.fetch();
      const signal = computeSignal(snapshot, cfg);
      writeState(signal);
      const results = await Promise.allSettled(live.map((s) => s.apply(signal)));
      results.forEach((r, i) => {
        if (r.status === "rejected") {
          console.error(`[tosspeek] 싱크 '${live[i].name}' 적용 실패:`, r.reason?.message ?? r.reason);
        }
      });
    } catch (err) {
      console.error(`[tosspeek] 소스 '${source.name}' 조회 실패:`, (err as Error).message);
    }
  };

  await tick();
  const timer = setInterval(tick, cfg.pollIntervalSec * 1000);

  return {
    async stop() {
      clearInterval(timer);
      await Promise.allSettled(live.map((s) => s.close?.()));
    },
  };
}
