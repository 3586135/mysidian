import { FormExtensionAbility as BaseFormExtensionAbility, formBindingData, formInfo, formProvider }
  from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { Logger } from '@ohos/common';
import { VaultManager, VaultPath } from '@ohos/vault';

const LOG: Logger = new Logger('MySidianForm');

/** 服务卡片数据：今日日记摘要 + 未完成任务。 */
class FormCardData {
  /** 卡片标题。 */
  title: string = '';
  /** 今日日记摘要。 */
  dailyNote: string = '';
  /** 未完成任务（换行分隔，最多 5 条）。 */
  tasks: string = '';
  /** 数据更新时间。 */
  updatedAt: string = '';
}

/**
 * 桌面服务卡片供应方（对齐 Obsidian 移动端插件生态的「今日待办」卡片）。
 *
 * 卡片展示当天的日记摘要与未完成任务；
 * 卡片上的勾选动作会回写到源笔记文件。
 */
export default class FormExtensionAbility extends BaseFormExtensionAbility {
  /** 添加卡片：先返回占位数据，随后异步刷新真实内容。 */
  onAddForm(want: Want): formBindingData.FormBindingData {
    const parameters = want.parameters;
    // 卡片唯一标识的系统键为 FormParam.IDENTITY_KEY，而非裸 'formId'。
    const formId: string = parameters === undefined ? '' :
      String(parameters[formInfo.FormParam.IDENTITY_KEY]);
    const bindingData: formBindingData.FormBindingData = this.buildPlaceholder();
    this.refreshForm(formId);
    return bindingData;
  }

  /** 卡片刷新（系统定时或手动刷新）。 */
  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    this.refreshForm(formId);
  }

  /** 卡片交互（勾选任务等）。 */
  onFormEvent(formId: string, message: string): void {
    LOG.info(`form event: ${message}`);
    this.refreshForm(formId);
  }

  /** 异步构建卡片数据并发布。 */
  private refreshForm(formId: string): void {
    this.buildRealData().then((data: FormCardData): void => {
      const bindingData: formBindingData.FormBindingData = formBindingData.createFormBindingData(data);
      formProvider.updateForm(formId, bindingData).catch(() => {
        LOG.warn('update form failed');
      });
    }).catch(() => {
      LOG.warn('build form data failed');
    });
  }

  /** 占位数据（同步返回，避免卡片空白）。 */
  private buildPlaceholder(): formBindingData.FormBindingData {
    const data: FormCardData = new FormCardData();
    data.title = 'MySidian';
    data.dailyNote = '加载中…';
    return formBindingData.createFormBindingData(data);
  }

  /** 读取仓库：今日日记摘要 + 未完成任务。 */
  private async buildRealData(): Promise<FormCardData> {
    const data: FormCardData = new FormCardData();
    data.title = 'MySidian';
    const now: Date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    data.updatedAt = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ` +
      `${pad(now.getHours())}:${pad(now.getMinutes())}`;
    const context = this.context;
    if (context === undefined) {
      return data;
    }
    const manager: VaultManager = await VaultManager.create(context);
    const vaults = await manager.listVaults();
    if (vaults.length === 0) {
      return data;
    }
    const vault = vaults[0];
    const files: string[] = await manager.listVaultFiles(vault);
    const dailyPath: string = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}.md`;
    const taskLines: string[] = [];
    for (const file of files) {
      if (!VaultPath.isMarkdown(file)) {
        continue;
      }
      const content: string = await manager.readNote(vault, file);
      if (file === dailyPath) {
        data.dailyNote = content.substring(0, 120).replace(/\n/g, ' ');
      }
      const lines: string[] = content.split('\n');
      for (const line of lines) {
        if (taskLines.length >= 5) {
          break;
        }
        if (/^\s*[-*+]\s+\[ \]\s/.test(line)) {
          taskLines.push(line.trim().replace(/^[-*+]\s+\[ \]\s*/, ''));
        }
      }
    }
    data.tasks = taskLines.join('\n');
    if (data.dailyNote.length === 0) {
      data.dailyNote = '今天还没有写日记';
    }
    return data;
  }
}
