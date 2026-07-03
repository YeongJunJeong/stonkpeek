import { createServer, type Server } from "node:http";
import type { Signal, Sink } from "../core/types.js";

export interface HttpSinkOptions {
  port: number;
}

/**
 * localhost에 최신 Signal을 JSON으로 노출하는 읽기 전용 피드.
 * 크롬 확장 배지·웹 위젯 등 샌드박스라 state.json을 직접 못 읽는 화면형 소비자를 위한 수도꼭지.
 * 127.0.0.1에만 바인딩 — 같은 기기 밖으로는 안 나간다. 키·주문은 데몬에만 남는다.
 */
export class HttpSink implements Sink {
  name = "http";

  private server: Server | null = null;
  private latest: Signal | null = null;

  constructor(private opts: HttpSinkOptions) {}

  async init(): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      this.server = createServer((req, res) => {
        res.setHeader("Access-Control-Allow-Origin", "*");
        res.setHeader("Cache-Control", "no-store");
        if (req.method === "OPTIONS") {
          res.writeHead(204);
          res.end();
          return;
        }
        if (req.url?.startsWith("/signal")) {
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify(this.latest));
          return;
        }
        res.writeHead(404);
        res.end();
      });
      this.server.on("error", reject);
      this.server.listen(this.opts.port, "127.0.0.1", () => resolve());
    });
  }

  async apply(sig: Signal): Promise<void> {
    this.latest = sig;
  }

  async close(): Promise<void> {
    await new Promise<void>((resolve) => {
      if (!this.server) return resolve();
      this.server.close(() => resolve());
    });
  }
}
