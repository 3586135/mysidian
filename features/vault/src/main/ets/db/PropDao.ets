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
      const value: string = property.type === MdPropType.LIST ? property.listValue.join(',') : property.value;
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
        const property: MdProperty = new MdProperty();
        property.key = result.getString(0);
        property.value = result.getString(1);
        const vtype: string = result.getString(2);
        if (vtype === 'list') {
          property.type = MdPropType.LIST;
          property.listValue = property.value.split(',');
        } else if (vtype === 'number') {
          property.type = MdPropType.NUMBER;
        } else if (vtype === 'boolean') {
          property.type = MdPropType.BOOLEAN;
        } else {
          property.type = MdPropType.STRING;
        }
        properties.push(property);
      } while (result.goToNextRow());
    }
    result.close();
    return properties;
  }
}
