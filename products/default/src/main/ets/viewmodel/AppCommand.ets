/**
 * 应用命令（命令面板条目）。
 */
export class AppCommand {
  id: string = '';
  title: string = '';
  hint: string = '';
  action: () => void = (): void => {};
}
