import { UIExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '@ohos/common';
import { VaultManager } from '@ohos/vault';

const LOG: Logger = new Logger('MySidianShare');

/** 分享面板扩展：把系统分享的内容存为 Markdown 笔记。 */
export default class ShareExtensionAbility extends UIExtensionAbility {
  onCreate(launchParam: AbilityConstant.LaunchParam): void {
    LOG.info('share extension created');
  }

  /** 接收到分享数据时保存为笔记。 */
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    const text: string = this.extractText(want);
    const title: string = this.extractTitle(want);
    if (text.length === 0) {
      LOG.info('share payload is empty');
      return;
    }
    this.saveAsNote(title, text);
  }

  onSessionDestroy(session: UIExtensionContentSession): void {
  }

  onDestroy(): void {
  }

  /** 从 want 参数中提取分享文本。 */
  private extractText(want: Want): string {
    const parameters = want.parameters;
    if (parameters === undefined) {
      return '';
    }
    const candidates: string[] = ['ohos.share.keyContent', 'keyContent', 'content', 'text'];
    for (const key of candidates) {
      const value: Object = parameters[key];
      if (value === undefined) {
        continue;
      }
      const text: string = String(value);
      if (text.length > 0) {
        return text;
      }
    }
    return '';
  }

  /** 从 want 参数中提取分享标题。 */
  private extractTitle(want: Want): string {
    const parameters = want.parameters;
    if (parameters === undefined) {
      return '';
    }
    const candidates: string[] = ['ohos.share.keyTitle', 'keyTitle', 'title', 'subject'];
    for (const key of candidates) {
      const value: Object = parameters[key];
      if (value === undefined) {
        continue;
      }
      const text: string = String(value);
      if (text.length > 0) {
        return text;
      }
    }
    return '';
  }

  /** 把分享内容写入当前仓库。 */
  private async saveAsNote(title: string, text: string): Promise<void> {
    const context = this.context;
    if (context === undefined) {
      return;
    }
    try {
      const manager: VaultManager = await VaultManager.create(context);
      const vaults = await manager.listVaults();
      if (vaults.length === 0) {
        LOG.warn('no vault available for share');
        return;
      }
      const vault = vaults[0];
      const now: Date = new Date();
      const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
      const stamp: string = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
        `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
      const name: string = title.length > 0 ? title.replace(/[\\/:*?"<>|]/g, '_') : '分享内容';
      const path: string = `${name}-${stamp}.md`;
      const content: string = `# ${name}\n\n${text}\n`;
      await manager.writeNote(vault, path, content);
      await manager.refreshNote(vault, path);
      LOG.info(`shared content saved: ${path}`);
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`save shared note failed, code=${err.code}, message=${err.message}`);
    }
  }
}
