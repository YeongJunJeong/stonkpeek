import type { Config } from "../config.js";
import type { Signal, Sink } from "../core/types.js";

/**
 * OpenRGB SDK 서버 싱크 — 키보드/마우스/RAM 등 RGB 장치 전체를 무드 색으로.
 * OpenRGB를 "SDK Server" 모드로 켜두어야 한다 (기본 포트 6742).
 * openrgb-sdk는 optionalDependency라 설치 실패해도 다른 싱크는 동작한다.
 */
export class OpenRgbSink implements Sink {
  name = "openrgb";

  private client: any = null;

  constructor(private cfg: Config["sinks"]["openrgb"]) {}

  async init(): Promise<void> {
    const sdk: any = await import("openrgb-sdk").catch(() => {
      throw new Error("openrgb-sdk 패키지가 없습니다. `npm install openrgb-sdk` 후 다시 시도하세요.");
    });
    const Client = sdk.Client ?? sdk.default?.Client;
    this.client = new Client("tosspeek", this.cfg.port, this.cfg.host);
    await this.client.connect();
  }

  async apply(sig: Signal): Promise<void> {
    if (!this.client) return;
    const scale = sig.brightness;
    const color = {
      red: Math.round(sig.color.r * scale),
      green: Math.round(sig.color.g * scale),
      blue: Math.round(sig.color.b * scale),
    };
    const count: number = await this.client.getControllerCount();
    for (let i = 0; i < count; i++) {
      const device = await this.client.getControllerData(i);
      const ledCount: number = device.colors?.length ?? device.leds?.length ?? 0;
      if (ledCount > 0) {
        await this.client.updateLeds(i, Array(ledCount).fill(color));
      }
    }
  }

  async close(): Promise<void> {
    await this.client?.disconnect?.();
  }
}
