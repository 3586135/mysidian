import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 轻量日志封装，tag 可自定义，默认 MySidian。
 */
export class Logger {
  private readonly prefix: string;
  private readonly domain: number = 0xFF00;
  private readonly format: string = '%{public}s';

  constructor(tag: string = 'MySidian') {
    this.prefix = tag;
  }

  public debug(...args: string[]): void {
    hilog.debug(this.domain, this.prefix, this.format, args.join(' '));
  }

  public info(...args: string[]): void {
    hilog.info(this.domain, this.prefix, this.format, args.join(' '));
  }

  public warn(...args: string[]): void {
    hilog.warn(this.domain, this.prefix, this.format, args.join(' '));
  }

  public error(...args: string[]): void {
    hilog.error(this.domain, this.prefix, this.format, args.join(' '));
  }
}
