/**
 * 预置示例仓库内容：首次启动（无任何仓库）时写入，帮助新用户了解应用功能。
 */

/** 单篇示例笔记（相对路径 + Markdown 内容）。 */
export class DemoNote {
  path: string = '';
  content: string = '';
}

/** 示例笔记清单。 */
export class DemoVaultContent {
  /** 全部示例笔记。 */
  public static notes(): DemoNote[] {
    const welcome: DemoNote = new DemoNote();
    welcome.path = '欢迎.md';
    welcome.content = [
      '---',
      'tags: [欢迎, 指南]',
      'author: mysidian',
      '---',
      '',
      '# 欢迎使用 mysidian',
      '',
      '这是一个预置的示例仓库，帮助你快速上手。你可以随意编辑或删除这些笔记。',
      '',
      '## 快速上手',
      '',
      '- 在左侧文件树中点击笔记即可打开',
      '- 点击编辑按钮进入编辑模式，保存后自动重建索引',
      '- 顶部的放大镜图标可全文搜索，支持标签与属性两种筛选方式',
      '- 在「设置 → 同步设置」中配置 WebDAV 服务器，即可在多台设备间同步笔记',
      '',
      '## 内置示例',
      '',
      '- [[示例/Markdown 语法示例]]：标题、列表、任务、代码块等常用语法',
      '- [[示例/任务清单]]：可勾选的任务列表与跨笔记任务查询',
      '',
      '> 提示：仓库数据保存在应用沙箱中，可在「仓库管理」里导出 zip，用桌面 Obsidian 直接打开。',
      '',
      '#欢迎 #指南'
    ].join('\n');

    const syntax: DemoNote = new DemoNote();
    syntax.path = '示例/Markdown 语法示例.md';
    syntax.content = [
      '---',
      'tags: [语法, 示例]',
      '---',
      '',
      '# Markdown 语法示例',
      '',
      '## 文字样式',
      '',
      '支持 **加粗**、*斜体*、~~删除线~~ 和 `行内代码`。',
      '',
      '## 列表',
      '',
      '无序列表：',
      '',
      '- 苹果',
      '- 香蕉',
      '- 樱桃',
      '',
      '有序列表：',
      '',
      '1. 第一项',
      '2. 第二项',
      '3. 第三项',
      '',
      '## 引用',
      '',
      '> 这是一段引用文字。',
      '> 引用可以有多行。',
      '',
      '## 代码块',
      '',
      '```ts',
      'function greet(name: string): string {',
      '  return "Hello, " + name + "!";',
      '}',
      '```',
      '',
      '## 表格',
      '',
      '| 语法 | 效果 |',
      '| --- | --- |',
      '| `**粗体**` | **粗体** |',
      '| `*斜体*` | *斜体* |',
      '',
      '## 链接',
      '',
      '- 站内链接：[[欢迎]]',
      '- 外部链接：https://developer.huawei.com',
      '',
      '#语法'
    ].join('\n');

    const tasks: DemoNote = new DemoNote();
    tasks.path = '示例/任务清单.md';
    tasks.content = [
      '---',
      'tags: [任务, 示例]',
      '---',
      '',
      '# 任务清单',
      '',
      '## 今日待办',
      '',
      '- [ ] 阅读「欢迎」笔记 #task',
      '- [ ] 试试编辑与保存 #task',
      '- [ ] 配置 WebDAV 同步 #task',
      '- [x] 安装 mysidian #task',
      '',
      '## 跨笔记任务查询',
      '',
      '下面的代码块会汇总整个仓库中带 #task 标签的未完成任务：',
      '',
      '```dataview',
      'TASK',
      'WHERE !completed AND contains(tags, "#task")',
      '```',
      '',
      '#任务'
    ].join('\n');

    return [welcome, syntax, tasks];
  }
}
