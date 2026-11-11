# 开发状态与设计决策

> 最后更新：2026-11-11。本文档记录各里程碑的功能实现、关键设计决策、验证状态与已知问题，供后续开发（含 AI 协作）快速接续。

## 里程碑历史（git 提交）

| 里程碑 | 内容 |
|---|---|
| M0 | 模块化重构：domain/common/markdown/vault/sync HAR 结构 |
| M1 | Vault 存储层：RDB schema、沙箱文件 IO、zip 导入导出、文件树 UI |
| M2 | ArkTS Markdown 引擎：block/inline/frontmatter 解析器、原生渲染器、12 个单测 |
| M3 | 源码编辑器（TextArea）、增量索引管线（block/link/tag/prop）、大纲/反链/标签/属性面板 |
| M5-M6 | WebDAV 同步引擎（manifest 协议 + 冲突副本）、FTS 搜索、快速切换器、命令面板、设置、ArkWeb HTML 兜底、懒加载文件树 |
| v0.2.0 | 引导页重构（新建/导入/WebDAV 三入口）、新建仓库同时配置 WebDAV、首个仓库预填示例笔记、Dataview TABLE/LIST 查询、编辑格式工具栏 |

## 近期变更（v0.2.0，已发布）

### 引导页与首次体验（2026-11-10）

- **引导页**（`emptyVaultView` 重构）：欢迎徽章偏上布局（修复图标过靠下），下方三行操作卡片——新建仓库 / 导入仓库 / 配置 WebDAV 同步（已配置时显示"WebDAV 已配置"）。
- **新建仓库 + WebDAV 一步完成**：新建对话框新增"同时配置 WebDAV 同步"开关（默认开、预填已有配置），展开服务器/用户名/密码/远端目录四项；点「创建」后保存配置、开启自动同步并触发首次同步（`applyCreateSyncConfig`）。
- **首个仓库预填示例笔记**：`DemoVaultContent`（欢迎 / Markdown 语法示例 / 任务清单，含 frontmatter、标签、wiki 链接、dataview 任务查询）；`VaultViewModel.createVault` 判断 `vaults.length === 0` 走 `createDemoVault`，之后新建均为空仓库；对话框名称预填"示例仓库"。
- **流程**：全新安装 → 引导页 → 点"新建仓库" → 进入预填示例内容的仓库（Nova 14 真机验证）。

### Dataview TABLE/LIST 查询（2026-11-10）

- `DataViewQuery` 解析 TABLE（`FROM` 后列头 `|a|b|` + 数据行）与 LIST（逐行条目）；`parsedOk` 区分可执行查询。
- `MdBlockView` 新增 `dataViewTableView` / `dataViewListView` 渲染；TASK 查询行为不变。
- `MdWebFallback` 高度改为内容估算（`estimateHeight`，220-600vp 封顶），不再固定 220。

### 编辑格式工具栏（2026-11-10）

- 编辑模式底部工具栏（`editToolbar`）：标题/加粗/列表/任务/有序列表/分隔线快捷插入；TextArea 聚焦显示、失焦隐藏。

## 近期变更（未发布）

### 键盘避让重做：编辑工具栏紧贴键盘，底部导航栏沉到键盘下（2026-11-11）

- **问题**：原先全局 `KeyboardAvoidMode.RESIZE`，键盘弹出时整个页面压缩，底部「笔记 / 设置」悬浮导航栏被一起顶到键盘上方，挡住视线。
- **方案**（`Index.ets`）：窄屏且编辑区进入「键盘交互态」（`editorKeyboardMode`）时改用 `KeyboardAvoidMode.NONE`——页面不被压缩，底部导航栏沉到键盘下方不可见；编辑区按 `keyboardHeightChange` 事件抬升 `keyboardHeight`，使编辑格式工具栏紧贴键盘上沿。
  - 键盘高度：Index.ets 订阅 `window.on('keyboardHeightChange')`，`aboutToDisappear` 取消订阅。
  - 避让策略切换：编辑器 `onTouch`（先于聚焦）即切换为 NONE，避免键盘弹出瞬间页面跳动；切页签 / 取消保存时恢复 RESIZE。
  - 弹层让位：所有弹层统一包进一个 `Stack`，NONE 避让时按键盘高度 `padding` 上移，弹层不会被键盘遮挡。
  - 宽屏（≥600vp）无底部悬浮导航栏，保持 RESIZE 不变。

### 六个「代码级断层」修补（2026-11-11）

1. **模板 `{{cursor}}` 少截 1 字符**：`TemplateEngine.render` 用 `+ 9` 截断占位符（实际长度 10），正文会残留 `}`。改为按 `CURSOR_TOKEN.length` 截断；并新增单测。
2. **模板光标位置未生效**：`createNoteWithTemplate` / `openDailyNote` / `openWeeklyNote` / `openDailyNoteByDate` 计算了 `cursorOffset` 却没用。现在置 `vm.pendingCaret` 并进入编辑态，页面在 `TextArea.onAppear` 里调用 `textEditorController.caretPosition()` 定位光标。
3. **编辑模式返回键丢弃草稿**：`onBackPress` 直接 `cancelEdit()`。改为 `exitEditWithSave()`——草稿有变化则自动保存并提示「已自动保存修改」，无变化才取消。
4. **编辑工具栏窄屏溢出**：15+ 个按钮塞在不可滚动 `Row` 里，撤销/重做/IMG 被裁切。改为 `Scroll`（横向）+ `scrollBar(BarState.Off)`，并新增 `[[`、`#` 快捷按钮（17 个按钮）。
5. **回收站无查看/恢复入口**：`listTrash()` / `restoreNote()` 已有实现但 UI 缺失。新增 `trashOverlay()` 浮层（逐条「恢复」+ 底部「清空回收站」），菜单新增「回收站」入口。
6. **未创建双链无响应 / 嵌入忽略锚点**：
   - `openLink` 解析不到笔记时自动创建同名笔记并打开（双链「先写链接，后填内容」），并提示「已创建新笔记」。
   - `loadEmbed` 支持 `![[笔记#章节]]`：新增 `extractSection()`，抽取目标标题到下一个同级/更高级标题之间的正文。

### 属性面板增删属性（2026-11-11）

- `NoteInfoPanel` 属性页签新增「+ 新增属性」表单（属性名 + 文本/开关/列表类型选择），每个属性行新增删除按钮。
- `VaultViewModel` 新增 `addProperty()` / `removeProperty()`，`updateProperty()` 改为「不存在则新建」；抽出 `currentProperties()` / `saveProperties()` 复用读写链路。

### Markdown 与编辑体验增强（2026-11-11）

- **==高亮==**：`MdInlineType.HIGHLIGHT` + InlineParser 解析 + `MdInlineSegment.highlight` + `MdInlineText` 用 `textBackgroundStyle` 着色（新增 `md_highlight_bg` 深浅色资源）。
- **宽表格横向滚动**：表格外包横向 `Scroll`，每列 `constraintSize({ minWidth: 96 })`，列多时不再被压成竖条。
- **补全增强**：`getWikiCompletionCandidates` 改为「前缀命中在前、包含命中在后」（输入 `[[读书` 可命中「2026-读书笔记」）；新增 `getTagCompletionCandidates`，输入 `#` 提示仓库内已有标签。候选项新增 `replaceFrom` 字段，补全时替换已输入的查询串。
- **点击标题重命名**：编辑器标题栏点击笔记标题直接打开重命名对话框。

### 验证状态（2026-11-11）

- `devecocli build` 通过；`devecocli check arkts` 仅剩已知的资源名误报。
- 新增单测：`TemplateEngine` 光标/占位符 4 例、补全前缀/包含与标签补全 3 例（hypium 仅能在 DevEco Studio 内运行）。
- **UI 交互验证受阻**：三台模拟器（5555/5557/5559）的触摸注入（`devecocli ui click` / `uitest uiInput click` / `uinput -T -c`）全部无响应（命令返回成功但界面无变化，a11y 树与实际渲染不一致），本轮只能完成构建级与代码级验证，交互项需在模拟器恢复后补验。

### 代码走查后的加固（2026-11-11）

对本次改动做了独立代码走查，发现并修复以下问题：

| 问题 | 修复 |
|---|---|
| 前缀补全会把已输入的前缀丢掉（`[[读书` → `[[笔记]]`） | 候选项统一「整体替换查询串」：`insertText = 完整标题 + ']]'`，`replaceFrom` 指向查询起点 |
| 自动建笔记可能覆盖同名文件 | 建前先查 `NoteDao.findByPath`，命中则直接打开，不写文件 |
| 历史回滚会被旧草稿覆盖 | 回滚前 `cancelEdit()`；切换笔记前自动落盘草稿（新增保护） |
| `replaceEditorText` 的中间空串回调污染撤销栈（首次撤销清空正文） | 新增 `programmaticEdit` 标志，程序化写入期间屏蔽 onChange |
| 退出编辑后避让策略未复位 | `exitEditWithSave` / `onBlur` / 键盘收起事件统一重新评估策略 |
| 点工具栏按钮会让输入框失焦、工具栏消失 | 17 个工具栏按钮加 `focusable(false)` |
| 工具栏横向滚动被编辑器侧滑手势抢走 | 横向 PanGesture 从编辑器容器移到正文（编辑区 / 预览区） |
| 返回键未关闭回收站等新弹层 | `onBackPress` 补齐全部弹层（回收站/重命名/新建目录/移动/日历/历史/模板/闪念/手写） |
| 属性写回会丢失嵌套 map / 注释等未识别内容 | `FrontmatterSerializer` 改为「按 key 合并」：只替换被改属性块，其余原样保留 |
| 属性面板顺序与写回不一致（DB 排序 vs 文件顺序） | 面板改用文件解析结果（与写回同源） |
| 删除属性立即落盘不可撤销 | 删除前弹二次确认；属性列表 ForEach key 改用属性名 |
| `==高亮==` 可匹配空内容（`====` 被吞） | 要求高亮体非空 |
| 章节锚点会误判代码块内的 `#` 注释行 | `extractSection` 跳过 ``` 围栏 |
| 周报跨年周命名与 Obsidian 不一致 | `weekKey` 改用 ISO 周年（2024-12-30 → 2025-W01） |
| 标签补全会命中 `C#` / URL 片段 | `#` 必须是标签起始（前面为空白/行首/`(`/`[`） |

### 待办（下一轮，按优先级）

1. 文件树长按菜单：目录（在此新建/新建子目录/重命名/删除）、文件（重命名/移动/回收站/分屏打开）。
2. 页内查找 & 替换（当前只有全库搜索）。
3. 图片点击全屏预览 + 双指缩放；代码块语法着色。
4. Dataview TABLE/LIST（`collectEntries`）、未链接提及（`unlinkedMentions`）、日历统计（`calendarMonth`）仍逐篇 `readNote` + `MarkdownParser.parse`，大仓库需改走 RDB 索引。
5. 书签（★ 置顶区）与全屏全局图谱入口。

### Dataview live TABLE/LIST + 勾选实时消失（2026-11-10，TODO #4/#5 完成）

- TABLE/LIST 查询由静态解析升级为**联动索引数据**：`DataViewQuery` 解析列/条件，`VaultViewModel` 基于索引实时求值（不依赖 Web 兜底）。
- Dataview 任务**勾选后实时从列表消失**（符合查询条件即重新求值），对齐 Obsidian live query 行为。
- `LocalUnit.test.ets` 扩至 32 测（DataViewQuery 相关 8 测）；5559 验证 TABLE/LIST 渲染与勾选实时消失通过。

### 编辑工具栏两项修复（2026-11-10）

- **输入法遮挡修复**：`DefaultAbility` 在 loadContent 后设置 `setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)`（官方 FAQ faqs-arkui-53 推荐做法）。键盘弹出时页面整体压缩，编辑工具栏自然贴在键盘上方，不再被遮挡。
- **insertFormat 失效修复**：`draftBuffer` 非响应式导致程序化更新不触发 TextArea 重渲染，且 `cursorPos` 仅在 onFocus 时记录（过期）。改为 Index.ets 持有 `TextAreaController`，`insertFormat` 用 `getCaretOffset().index` 取实时光标 + `addText(syntax, {offset: caret})` 原生插入；保留 `updateDraft` 拼接兜底防 draftBuffer 失同步。
- 三台模拟器验证通过：5559 窄屏（含保存落盘 + 文件内容复核）、5557 宽屏平板、5555 折叠屏（真实仓库上以插入后取消方式验证，未触碰用户数据）。

## v0.1.x 设计要点（历史参考）

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

### 四大功能批次 + P1/P2 增强（2026-11-11，未发布）

**A 文件树管理**：新建文件夹 / 重命名 / 移动到… / 移入回收站 / 清空回收站（`.trash` + 时间戳防重名，可恢复）；`NoteDao.updatePath/removeByPath/listByPathPrefix`（保 id，不 delete+insert）；`LinkRewriter`（`[[旧名]]`、`|别名`、`#锚点` 精确重写，lookahead 匹配）；`AttachmentResolver`。

**B 双链闭环与嵌入**：锚点链接（`[[笔记#标题]]`）可点击跳转（`openLink` 拆锚点 + 360ms `scrollToBlock`）；外链走 `AbilityContextHolder` + `startAbility(Want{uri})` 拉起浏览器；`![[笔记]]` 嵌入块递归渲染（depth ≤ 2，只读）。

**C 图片附件全链路**：`![[x.png]]` / `![](path)` 独占行识别为图片块（支持 `|300` 像素宽）；`![[笔记]]` 为嵌入块；工具栏 IMG → PhotoViewPicker → 拷入 `attachments/` → 插入引用；同步层新增 `pushBinary/pullBinary/mkdirRemote`，WebDAV 支持二进制与 MKCOL，`SyncFileFilter` 分流，冲突 local-wins。

**D 编辑器生产力**：Wiki 补全浮层（光标跟随 + 候选过滤）、列表续行、撤销/重做（600ms 合并、50 步上限、`expectedText` 守卫防 onChange 递归）、工具栏 ↶ ↷ IMG。

**P1**：模板系统（`TemplateEngine`：`{{title}}/{{date}}/{{date:FMT}}/{{time}}/{{week}}/{{cursor}}`，支持默认/日记/周报模板）；属性面板交互式编辑（BOOLEAN→Toggle、LIST→标签胶囊增删、日期→日期选择器、标量→行内编辑，回写并重索引）；Dataview `SORT field ASC|DESC` / `LIMIT n` / 日期比较（`due` vs `today`/`now()`）；Callout 折叠（`> [!NOTE]- 标题`）；原生 LaTeX 渲染（`MathRenderer.toPlain`，Unicode 上下标）与原生 Mermaid 渲染（`MermaidFlow` 分层布局 + Canvas 绘图）；文件历史（`.history/` 快照 ≤ 20、LCS 行级 Diff、回滚）；日历面板（月历网格、有日记圆点、未完成角标、本周周报、日记创建）。

**P2**：局部图谱（1~2 跳 outgoing+backlinks，力导向布局，信息面板第 5 页签）；分屏双开（宽屏第二栏只读预览 + 关闭按钮）；服务卡片（`FormExtensionAbility` + `form_config.json`）；分享面板（`ShareExtensionAbility`，外部 Markdown 转笔记）；手写速记（Canvas 采集 → PixelMap → PNG → `attachments/` → 插入引用）；反链面板增加「未链接提及」与一键转双链。

### 验证阶段修复的缺陷（2026-11-11）

1. **Mermaid 解析崩溃（App 闪退）**：`MermaidFlow.parse` 正则捕获组编号错位（`edge[3]` 当作 label、`edge[4]` 当作目标节点），目标节点为 `undefined` → `node.label` 为 `undefined` → `.length` 抛 TypeError，含 Mermaid 图的笔记一打开即崩。已修正捕获组并捕获两端节点形状，另加 `try/catch` 兜底降级为展示源码。
2. **数学公式渲染空白**：块级公式走 ArkWeb（`loadData` 未生效）渲染为空盒；行内公式只剥离 `$` 不排版。改为原生渲染：`MathRenderer.toPlain` 输出 Unicode 上下标文本（`a²`、`E = mc²`、`(1)/(2)`、`√(x)`），块级居中显示、行内走 `MdInlineFlattener`。
3. **列表型属性之后的键被丢弃**：`FrontmatterParser` 在解析列表属性后仍自增游标，导致 `tags:` 之后的 `due:` 等属性既不显示也会在属性回写时丢失。已修正游标推进逻辑并补单测。
4. **外部改动不入索引**：应用只索引「无 block 的笔记」，被外部修改（同步 / 手动覆盖）的笔记其属性、大纲、反链长期为旧值。新增 `VaultViewModel.syncIndex()`：按 mtime + size 增量比对，仅重建变化笔记（启动与同步完成后调用）。
5. **宽屏缺少笔记级菜单**：平板/折叠宽屏布局没有笔记列表头部，重命名/回收站/日历/模板/历史/分屏双开等入口不可达。已在编辑器标题栏补 `sys.symbol.more` 按钮（`bindMenu(moreMenuBuilder)`），分屏时自动收起右侧信息面板。
6. **改名后反链未重写**：`IndexPipeline.collectLinks` 只遍历 `block.inlines`，漏掉列表项中的链接。已补 `collectItemLinks` 递归列表项，并在 `renameNote` 保留文件扫描兜底 `rewriteLinksByScan`。

### 三机验证记录（2026-11-11）

| 设备 | 形态 | 验证内容 | 结果 |
|---|---|---|---|
| 127.0.0.1:5559 | 窄屏手机 1280×2832 | 改名→双链自动重写、回收站、日历、属性面板、局部图谱、Callout/数学/Mermaid/Dataview SORT+LIMIT | 通过（测试仓库已还原为空） |
| 127.0.0.1:5557 | 宽屏平板 2880×1920 | 三栏布局、笔记级菜单、分屏双开第二栏 | 通过 |
| 127.0.0.1:5555 | 折叠屏 2210×2416 | 宽屏布局、笔记级菜单入口 | 通过 |

> 5555 / 5557 为用户真实仓库，验证仅只读（打开笔记、切换面板、进入菜单），未写入任何内容。

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
- 页面 Index.ets 及 products/default 下全部组件均为 V2（`@ComponentV2` + `@Local/@Param/@Event` 等），通过事件回调与子组件交互。
- 跨层异步数据用回调式事件（如 `onLoadDataView(query, onResult)`）。
- `VaultViewModel.draftBuffer` 刻意保持非响应式（非 `@Trace`），避免输入时重建 TextArea 造成光标跳动；程序化更新须走 `TextAreaController`（见"编辑格式工具栏"）。

## 已知问题与 TODO

1. **单测无法 CLI 运行**：hypium 测试只在 DevEco Studio 内可跑；`features/markdown/src/test/LocalUnit.test.ets` 现含 32 测（Markdown 引擎 + DataViewQuery）。
2. `devecocli check arkts` 资源引用误报（见 AGENTS.md）。
3. `C:\Users\song\.local\bin\deveco.exe` 可能被 WDAC 拦截，用 Temp 副本 workaround（见 AGENTS.md）。
4. ~~Dataview TABLE/LIST 为静态解析渲染~~ → 已完成 live 化（见"近期变更"）。
5. ~~Dataview 勾选后任务不实时从列表消失~~ → 已完成实时消失（见"近期变更"）。
6. 真机验证遗留：`2026-10-15.md` Gemini OAuth 任务曾被勾选、`Hermes记录.md` 有一行误插 `验证任务A`，待用户在应用内手动处理（用户数据，非代码问题）。
7. 5555（折叠屏模拟器）UI 自动化偶发 a11y 树与实际渲染不一致、Toggle 点击不生效（"设置→仓库管理→新建"对话框），根因未明；屏幕熄灭也会导致点击失效（先 `power-shell wakeup; power-shell setmode 602`）。
8. **服务卡片为静态视图**：本 SDK 卡片应用禁 `@StorageLink/@StorageProp`（`'StorageLink' can't support form application`）且未提供 `FormComponent`，卡片页无法取动态数据；真实数据由 `formProvider.updateForm` 发布（卡片侧渲染未验证）。可在设置里手动添加卡片。
9. **分享面板**已注册为 `entity.system.share` 扩展（`skills`），需从第三方应用分享 Markdown 才会触发；系统分享面板的实测触发路径未覆盖。
10. **数学公式为 Unicode 近似**：分数渲染为 `(a)/(b)`（非堆叠），复杂公式（矩阵、多行对齐）不支持；如需专业排版需引入 KaTeX/Web 方案。
11. **宽屏分屏时右侧信息面板自动收起**：分屏 + 信息面板同时展开会把正文挤得过窄，故分屏时优先收起信息面板（可手动再打开）。

## 验证环境备注

- 三台模拟器形态覆盖：窄屏（5559）/ 中等宽折叠（5555）/ 宽屏平板（5557），UI 改动应三机回归。
- 测试数据注入与 UI 自动化技巧见 AGENTS.md"模拟器专属技巧"与"UI 自动化要点"。
