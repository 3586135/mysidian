import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { MdPropType, MdProperty } from '@ohos/domain';
import { DbHelper } from './DbHelper';

/** 属性（frontmatter）索引数据访问。 */
export class PropDao {
  /** 覆盖写入一篇笔记的属性。 */
  public static async replaceForNote(context: common.Context, noteId: number,
    properties: MdProperty[]): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [noteId];
    await store.executeSql('DELETE FROM prop WHERE note_id = ?', args);
    for (const property of properties) {
      let value: string = property.value;
      if (property.type === MdPropType.LIST) {
        // 列表值以逗号连接存储：值内字面逗号会破坏还原。写入前转义
        // （`\`→`\\`、`,`→`\,`），读取时反转义；历史未转义行按裸逗号
        // 切分，行为与旧版一致（字面 `\,` 序列属极罕见边界，索引可重建）。
        const escaped: string[] = [];
        for (const item of property.listValue) {
          escaped.push(PropDao.escapeListItem(item));
        }
        value = escaped.join(',');
      }
      const insertArgs: Array<relationalStore.ValueType> = [noteId, property.key, value, property.type];
      await store.executeSql(
        'INSERT OR REPLACE INTO prop (note_id, prop_key, prop_value, vtype) VALUES (?, ?, ?, ?)',
        insertArgs);
    }
  }

  /** 查询一篇笔记的属性。 */
  public static async ofNote(context: common.Context, noteId: number): Promise<MdProperty[]> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [noteId];
    const result = await store.querySql(
      'SELECT prop_key, prop_value, vtype FROM prop WHERE note_id = ? ORDER BY prop_key ASC', args);
    const properties: MdProperty[] = [];
    if (result.goToFirstRow()) {
      do {
        properties.push(PropDao.parseRow(
          result.getString(0), result.getString(1), result.getString(2)));
      } while (result.goToNextRow());
    }
    result.close();
    return properties;
  }

  /** 批量查询指定仓库下每篇笔记的 frontmatter 属性（noteId -> properties）。 */
  public static async propsByVault(context: common.Context,
    vaultId: number): Promise<Map<number, MdProperty[]>> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId];
    const result = await store.querySql(
      'SELECT p.note_id, p.prop_key, p.prop_value, p.vtype FROM prop p ' +
      'JOIN note n ON n.id = p.note_id WHERE n.vault_id = ? ORDER BY p.note_id ASC', args);
    const map: Map<number, MdProperty[]> = new Map<number, MdProperty[]>();
    if (result.goToFirstRow()) {
      do {
        const noteId: number = result.getLong(0);
        const prop: MdProperty = PropDao.parseRow(
          result.getString(1), result.getString(2), result.getString(3));
        let list: MdProperty[] | undefined = map.get(noteId);
        if (list === undefined) {
          list = [];
          map.set(noteId, list);
        }
        list.push(prop);
      } while (result.goToNextRow());
    }
    result.close();
    return map;
  }

  private static parseRow(key: string, value: string, vtype: string): MdProperty {
    const property: MdProperty = new MdProperty();
    property.key = key;
    property.value = value;
    if (vtype === 'list') {
      property.type = MdPropType.LIST;
      property.listValue = value.length > 0 ? PropDao.splitListValue(value) : [];
    } else if (vtype === 'number') {
      property.type = MdPropType.NUMBER;
    } else if (vtype === 'boolean') {
      property.type = MdPropType.BOOLEAN;
    } else {
      property.type = MdPropType.STRING;
    }
    return property;
  }

  /** 列表项写入转义：先转义反斜杠再转义逗号，保证连接/切分往返无损。 */
  private static escapeListItem(item: string): string {
    return item.split('\\').join('\\\\').split(',').join('\\,');
  }

  /** 列表值还原切分：`\,` 还原为逗号、`\\` 还原为反斜杠、裸逗号切分。 */
  private static splitListValue(value: string): string[] {
    const items: string[] = [];
    let current: string = '';
    let index: number = 0;
    while (index < value.length) {
      const ch: string = value.charAt(index);
      const next: string = index + 1 < value.length ? value.charAt(index + 1) : '';
      if (ch === '\\' && (next === ',' || next === '\\')) {
        current += next;
        index += 2;
        continue;
      }
      if (ch === ',') {
        items.push(current);
        current = '';
        index++;
        continue;
      }
      current += ch;
      index++;
    }
    items.push(current);
    return items;
  }
}
