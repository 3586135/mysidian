import { FlatFileNode } from '@ohos/domain';

/**
 * 文件树懒加载数据源。
 * LazyForEach 要求数据源不可重新赋值，只能通过数据变更通知刷新。
 */
export class FileTreeDataSource implements IDataSource {
  private items: FlatFileNode[] = [];
  private listeners: DataChangeListener[] = [];

  public totalCount(): number {
    return this.items.length;
  }

  public getData(index: number): FlatFileNode {
    return this.items[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 替换数据并通知刷新。 */
  public setItems(items: FlatFileNode[]): void {
    this.items = items;
    this.notifyDataReload();
  }

  private notifyDataReload(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}
