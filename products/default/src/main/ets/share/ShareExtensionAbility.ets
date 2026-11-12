import { ShareExtensionAbility as BaseShareExtensionAbility, UIExtensionContentSession, Want }
  from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '@ohos/common';
import { VaultManager } from '@ohos/vault';

const LOG: Logger = new Logger('MySidianShare');

/** 分享面板扩展：把系统分享的内容存为 Markdown 笔记。 */
export default class ShareExtensionAbility extends BaseShareExtensionAbility {
  onCreate(): void {
    LOG.info('share extension created');
  }

  /** 接收到分享数据时保存为笔记，随后关闭分享面板（不留空白会话）。 */
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    systemShare.getSharedData(want).then((data: systemShare.SharedData): void => {
      const records: Array<systemShare.SharedRecord> = data.getRecords();
      let title: string = '';
      let text: string = '';
      for (const record of records) {
        const recordContent: string = record.content ?? '';
        const recordTitle: string = record.title ?? '';
        if (text.length === 0 && recordContent.length > 0) {
          text = recordContent;
        }
        if (title.length === 0 && recordTitle.length > 0) {
          title = recordTitle;
        }
      }
      if (text.length === 0) {
        // 兜底：旧版分享方直接塞 want 参数的场景。
        text = this.extractText(want);
        title = title.length > 0 ? title : this.extractTitle(want);
      }
      this.saveAsNote(title, text).then((): void => {
        session.terminateSelfWithResult({
          resultCode: systemShare.ShareAbilityResultCode.CLOSE
        });
      });
    }).catch((error: BusinessError) => {
      LOG.error(`getSharedData failed, code=${error.code}, message=${error.message}`);
      session.terminateSelfWithResult({
        resultCode: systemShare.ShareAbilityResultCode.CLOSE
      });
    });
  }

  onSessionDestroy(session: UIExtensionContentSession): void {
  }

  onDestroy(): void {
  }

  /** 从 want 参数中提取分享文本（getSharedData 失败时的兜底）。 */
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

  /** 从 want 参数中提取分享标题（getSharedData 失败时的兜底）。 */
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
    if (text.length === 0) {
      LOG.info('share payload is empty');
      return;
    }
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
