# 开发状态与设计决策

> 最后更新：2026-11-09。本文档记录各里程碑的功能实现、关键设计决策、验证状态与已知问题，供后续开发（含 AI 协作）快速接续。

## 里程碑历史（git 提交）

| 里程碑 | 内容 |
|---|---|
| M0 | 模块化重构：domain/common/markdown/vault/sync HAR 结构 |
| M1 | Vault 存储层：RDB schema、沙箱文件 IO、zip 导入导出、文件树 UI |
| M2 | ArkTS Markdown 引擎：block/inline/frontmatter 解析器、原生渲染器、12 个单测 |
| M3 | 源码编辑器（TextArea）、增量索引管线（block/link/tag/prop）、大纲/反链/标签/属性面板 |
| M5-M6 | WebDAV 同步引擎（manifest 协议 + 冲突副本）、FTS 搜索、快速切换器、命令面板、设置、ArkWeb HTML 兜底、懒加载文件树 |

## 近期变更（未提交部分）

### 响应式布局改造（适配 Mate X7 折叠屏）

- **断点**：`isWide = contentWidth >= 600vp`；`fixedPanelEnabled = contentWidth >= 900vp`。
- 窄屏（<600vp）：抽屉式文件树 + 底部 miniBar（半圆悬浮按钮 + 菜单：新建笔记/最近访问等）。
- 中等宽（600-900vp，如 Mate X7 展开 ~650vp）：文件树固定 250vp，**信息面板不挤压编辑区**，以 360vp 右侧悬浮层呈现（position/markAnchor x=100%、translate 过渡、左边框+阴影、自带关闭按钮、返回键可关）。
- 宽屏（≥900vp，如平板）：文件树 280vp + 固定信息面板 300vp。
- `onAreaChange` 宽窄切换时 `showRightPanel` 默认值 = `width >= 900`，不覆盖用户手动切换状态。
- **历史教训**：曾因宽屏分支固定宽度叠加（树 280 + 面板 300 + navRail 88）把 650vp 的 X7 编辑器挤到 0px——中等宽必须走悬浮层而非三栏并排。

### obsidian-tasks 兼容

- `TaskMetadata`（features/markdown/parser）：`- [ ]` 语法、✅ done / 🛫 start / ⏫⏬ priority / 🔁 recurrence / 📅 due 等 emoji 元数据的解析与回写。
- 勾选回写：`[ ]→[x]` 追加 `✅ YYYY-MM-DD`；取消勾选移除 ✅ 日期。
- 渲染在 MdBlockView 任务行：SymbolGlyph 复选框 + 行内文本 + 元数据 chips（task 标签、优先级、截止等）。

### Dataview 查询块（TASK 查询）

- **解析**：`DataViewQuery.ets`——```` ```dataview ```` 代码块内 `TASK` 类型 + `WHERE` 子句（AND 连接：`completed` / `!completed` / `contains(tags, "#x")` / `contains(text, "y")` / `file.name != this.file.name`）+ `GROUP BY file.link`。非 TASK 查询仍按普通代码块渲染。
- **渲染**：MdBlockView `dataViewTaskView()`——按来源文件分组（分组头 = 文件名）、任务行（复选框 + 文本 + chips）、空态文案 `md_dataview_empty`。
- **数据流**：MdBlockView `aboutToAppear` 解析查询 → `onLoadDataView(query, onResult)` 事件 → Index.ets 接线 → `VaultViewModel.runDataViewQuery()`（`dataViewCache: Map<string, DataViewTask[]>`，key = `query|selectedPath`，写操作后清缓存）。
- **勾选回写**：MdBlockView `toggleDataViewTask`（本地 checked 突变 + `slice()` 强制 ForEach key `dv_${index}_${task.item.checked}` 重建）→ `onToggleDataViewTask(task, checked)` → `VaultViewModel.toggleTaskInNote()`：
  - 来源笔记 = 当前笔记：复用 `toggleTask()`（noteContent 替换 + 重解析）。
  - 跨笔记：readNote → replace → writeNote → 清缓存 → refreshNote。
  - **关键修复（2026-11-09）**：勾选后必须同步 `task.item.rawLine = nextLine`，否则二次勾选（取消）基于旧行文本计算无 diff 而提前 return，无法还原。
- 已在真机 + 三台模拟器验证：渲染、过滤（`WHERE !completed` 排除已完成）、勾选往返回写均正常。

### 信息面板页签调整（2026-11-09）

- 大纲/反链/标签/属性页签字号 13fp → 15fp，选中页签 Medium 字重，页签栏高 42 → 48（NoteInfoPanel.ets）。

### 其他近期功能

- **最近访问**：RecentNotesPanel，按最近打开排序。
- **miniBar 菜单**：窄屏底部半圆悬浮按钮展开菜单（新建笔记等）。
- **信息面板右滑呼出**：宽屏从屏幕右缘右滑打开信息面板。
- **导航栏**：NavRail（宽屏侧栏）+ 底部 Tabs（窄屏）双形态。

## 关键架构决策

### 存储与索引

- 笔记文件存应用沙箱 `files/vaults/<vaultId>_<name>/`；元数据入 RDB（relationalStore）。
- DAO 层：Note/Block/Link/Prop/Search(FTS)/Tag/Vault/SyncState。**直接向沙箱推新文件不会入索引**——必须经 VaultManager 写入或覆盖 DB 已登记笔记后 refreshNote。
- IndexPipeline 增量索引：block/link/tag/prop 表随笔记保存更新，支撑大纲/反链/标签/属性面板与搜索。

### Markdown 管线

```
raw → FrontmatterParser → BlockParser（块级：标题/列表/任务/代码/引用/表格/dataview…）
    → InlineParser（行内：强调/链接/标签/wikilink/行内代码…）
    → MdDocument 模型
渲染：MdDocumentView → MdBlockView（按块分发）→ MdInlineText（行内）
兜底：MdWebFallback（ArkWeb 渲染复杂 HTML 块）
```

### 状态管理约定

- ViewModels（VaultViewModel/SearchViewModel/SyncViewModel）用 `@ObservedV2` + `@Trace`。
- 页面 Index.ets 为 V1 `@Component`（历史原因），通过事件回调与 V2 组件（MdBlockView、NoteInfoPanel 等）交互。
- 跨层异步数据用回调式事件（如 `onLoadDataView(query, onResult)`），避免 V1/V2 观察模型混用。

## 已知问题与 TODO

1. **单测无法 CLI 运行**：hypium 测试只在 DevEco Studio 内可跑；`features/markdown/src/test/LocalUnit.test.ets` 含 Markdown 引擎 12 测 + DataViewQuery 3 测。
2. `devecocli check arkts` 资源引用误报（见 AGENTS.md）。
3. `C:\Users\song\.local\bin\deveco.exe` 可能被 WDAC 拦截，用 Temp 副本 workaround（见 AGENTS.md）。
4. Dataview 目前仅支持 TASK 查询；TABLE/LIST 查询未实现（按代码块显示）。
5. Dataview 勾选后任务不实时从列表消失（本地翻转保留显示；重启或重渲染后按查询条件刷新）——与 Obsidian live query 行为略有差异，属有意取舍。
6. 真机验证遗留：`2026-10-15.md` Gemini OAuth 任务曾被勾选、`Hermes记录.md` 有一行误插 `验证任务A`，待用户在应用内手动处理（用户数据，非代码问题）。

## 验证环境备注

- 三台模拟器形态覆盖：窄屏（5559）/ 中等宽折叠（5555）/ 宽屏平板（5557），UI 改动应三机回归。
- 测试数据注入与 UI 自动化技巧见 AGENTS.md"模拟器专属技巧"与"UI 自动化要点"。
