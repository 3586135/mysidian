import { common } from '@kit.AbilityKit';
import { NoteRow } from '@ohos/domain';
import { NoteDao } from '../db/NoteDao';
import { VaultPath } from './VaultPath';

/**
 * Wiki 链接解析：在仓库内按路径或文件名查找目标笔记。
 */
export class NoteResolver {
  /**
   * 解析链接目标。
   * @param context 应用上下文
   * @param vaultId 仓库 id
   * @param target 链接目标（文件名或相对路径）
   * @returns 命中的笔记，未命中返回 null
   */
  public static async resolve(context: common.Context, vaultId: number,
    target: string): Promise<NoteRow | null> {
    const trimmed: string = target.trim();
    if (trimmed.length === 0) {
      return null;
    }
    const notes: NoteRow[] = await NoteDao.listByVault(context, vaultId);
    for (const note of notes) {
      if (note.path === trimmed || note.path === `${trimmed}.md`) {
        return note;
      }
    }
    const lower: string = trimmed.toLowerCase();
    for (const note of notes) {
      if (VaultPath.basenameWithoutExt(note.path).toLowerCase() === lower) {
        return note;
      }
    }
    return null;
  }
}
