# 开发状态与设计决策

> 最后更新：2026-11-19。本文档记录各里程碑的功能实现、关键设计决策、验证状态与已知问题，供后续开发（含 AI 协作）快速接续。

## 里程碑历史（git 提交）

| 里程碑 | 内容 |
|---|---|
| M0 | 模块化重构：domain/common/markdown/vault/sync HAR 结构 |
| M1 | Vault 存储层：RDB schema、沙箱文件 IO、zip 导入导出、文件树 UI |
| M2 | ArkTS Markdown 引擎：block/inline/frontmatter 解析器、原生渲染器、12 个单测 |
| M3 | 源码编辑器（TextArea）、增量索引管线（block/link/tag/prop）、大纲/反链/标签/属性面板 |
| M5-M6 | WebDAV 同步引擎（manifest 协议 + 冲突副本）、FTS 搜索、快速切换器、命令面板、设置、ArkWeb HTML 兜底、懒加载文件树 |
| v0.2.0 | 引导页重构（新建/导入/WebDAV 三入口）、新建仓库同时配置 WebDAV、首个仓库预填示例笔记、Dataview TABLE/LIST 查询、编辑格式工具栏 |
| v0.3.x | Material 3 首页 DesignIndex（四页签横滑 + 悬浮胶囊底栏 + FAB 气泡菜单 + Canvas 图谱） |
| v0.4.0 | **单页架构全量重构（7 阶段）**：DesignIndex 唯一 @Entry，旧 4160 行工作台 Index.ets 全部功能迁移为页内全屏子视图 + `view/design/` 组件群（21 文件），深浅双模式 design_ 色板 |
| v0.5.0 | **安全、性能与生产力增强**：Asset Store 密码硬件级加密、DB v4 同步哈希缓存、冲突处理中心、FTS5 自愈 + BM25 排序、未链接提及 RDB 化、页内查找替换、文件树节点操作菜单、图片全屏缩放预览、应用内主题切换 |
| v0.6.0 | **查询引擎 RDB 化、代码高亮、书签、本地快照备份与多端生态**：Dataview/日历 RDB 批量加速、列表项文本与标签入库、原生代码块语法着色、置顶书签、本地定时/一键快照备份恢复、2in1 键盘快捷键与桌面长按快捷方式 |
| v1.0.0 | **全端质感打磨、同步安全无感化、系统打开方式与 1.0 正式发布**：首页默认素雅 5 色莫兰迪纸感列表与原地目录穿透面包屑、透明毛玻璃三页签底栏、按年月分卷日记（`日记/YYYY-MM/YYYY-MM-DD.md`）、自适应大纲浮层与多行编辑工具栏、WebDAV 干跑安全闸门/断点落盘/`.trash/` 软删与新建仓库自签名开关、系统 `.md`「打开方式」只读预览与一键导入、Ceramic Washi 分层应用图标、`md_*` 资源解耦与全模块单测通过 |

## 近期变更（2026-11-19，基线弃用 API 清零：showToast / AlertDialog / getParams / getStringSync / packing）

清理构建输出中全部弃用警告（10 处，SDK `@deprecated`/`@useinstead` 逐一核对）：

- **AlertDialog.show → UIContext.showAlertDialog**（7 处）：DesignIndex（同步安全确认）/ NoteActionHelper（笔记+目录移入回收站确认，导出函数新增 `ui: UIContext` 首参，调用方 DesignIndex/WorkspaceView 传 `this.getUIContext()`）/ NoteInfoSheet（删属性）/ TrashSheet（清空回收站）/ VaultManagerSheet（删仓库）。
- **promptAction.showToast → this.toast()**（DesignIndex pickCertFile，复用既有 UIContext PromptAction 助手）；DesignIndex 顶部 `@kit.ArkUI` import 同步移除 `promptAction`/`router`。
- **router.getParams() → this.getUIContext().getRouter().getParams()**（DesignIndex handleLaunchParams，弃用于 API 18，官方 useinstead UIContext Router；调用点在 `vm.init().then()` 异步回调，UI 上下文已就绪）。
- **resourceManager.getStringSync(resource, ...args) → getStringSync(resource.id, ...args)**（SyncViewModel resText，Resource+args 重载弃用于 API 20，官方 useinstead resId+args 重载）。
- **ImagePacker.packing → packToData**（HandwriteSheet exportImage，弃用于 API 13，同为 `Promise<ArrayBuffer>` 签名零语义差异）。
- 验证：`devecocli check arkts`（8 文件）0 错误；`devecocli build` exitCode=0 且弃用警告清零。三台模拟器部署冒烟 PASS；5555 + 5557 实测长按笔记 → 移入回收站确认弹窗（新 showAlertDialog 路径）渲染/取消正常；5555 点「立即同步」后同步状态行「同步完成（上传 0 · 下载 0）」正常渲染（resText 新重载格式化输出）。

## 近期变更（2026-11-19，v1.5.0 发布前对抗性审查：同步丢失类缺陷 / 首页热路径性能）

三路对抗性审查（WYSIWYG / 同步引擎 / 首页索引性能）后的修复，同步侧与首页侧要点：

- **A2 PULL_NEW 拉取文件不落盘基线与清单（丢失类）**：`persistSyncState` 只合并规划快照内的本地条目，远端新增（本地规划时不存在）的成功拉取文件被遗漏——全量覆写的远端 manifest 丢失这些条目、本地基线缺失，窗口期内远端删除该文件会被 `PUSH_NEW` 推回复活。修复：`succeededPulls` 命中但不在快照的落盘文件 stat+重哈希后并入 finalEntries（SyncEngine.ets）。
- **A1 TRASH_LOCAL 跨同步目标误删本地文件（丢失类）**：`decideLocalEntry` 对「远端消失 + 基线 synced 未改」一律回收站本地，但基线 targetKey 为空（历史遗留）或属于其他服务器/目录时不能证明当前远端删过它——切换同步目标后远端暂缺的文件会被整批误判为「他端删除」。修复：新增 `currentTargetKey` 参数，TRASH_LOCAL 要求非空且 `baseline.targetKey === currentTargetKey`，否则 fail-safe 走 PUSH_NEW（一轮成功后基线自动补全 targetKey 自愈）；SyncEngine.test.ets 补 4 个守卫用例。
- **A3 冲突「保留本地」静默覆盖远端并发修改（丢失类）**：`pushConflictKeepLocal` 推送前 `provider.stat()` 比对 ETag 与 `conflict.remoteServerTag`，不一致中止并保留冲突，交由下轮重新决策。
- **B1/B2 错误分级过宽**：引擎 `isFatalSyncError` 移除 `(400)`、`SyncViewModel.isAuthOrConfigError` 移除 `(403)/(400)/无权限`——PROPFIND 已成功后这些只是文件级错误，不应中止整轮或把自动同步打入冷却期。
- **B3/C1 同步文件体积上限**：新增 `MAX_SYNC_FILE_BYTES=64MB`，collectLocalEntries 超限跳过、executePulls 超限记 itemError 跳过，防单个超大文件拖死整库哈希/拉取。
- **G1 423 Locked 入瞬态码**：`WebDavProvider.isTransientHttpCode` 加 423（部分服务器并发写入期短暂返回），不再被吞成永久跳过。
- **F3 根级 conflicts/ 不入笔记索引**：`VaultManager.scanVault` 跳过 `conflicts/` 前缀，冲突副本不再混入列表/搜索/统计（trashFolder 与文件树不受影响）。
- **Hot#1 同步后全量重建改增量刷新**：`onSyncComplete` 从 `rescanVault`（735 篇全量重建十几秒）改为新方法 `VaultViewModel.refreshAfterSyncChanges()`（refreshTree + syncIndex 增量 + 打开笔记刷新 + 最近 + 图谱）；rescanVault 中打开笔记刷新块提取为 `refreshOpenNoteFromDisk()` 复用。
- **Hot#2 返回首页同仓库短路**：`restoreSession` 在 `currentVault.id > 0` 时只刷最近列表与收藏，跳过 selectVault 全链（全库 statSync 比对）。
- **Hot#3 目录计数单遍缓存**：新增 `folderCounts`（vaultFiles 单遍派生 path→{notes,attachments}，refreshTree 置空惰性重建），`countMarkdownFilesUnder/countAttachmentsUnder` 从 O(F) 线性扫描降为 O(1) 查表——抽屉/根目录求值从 O(2×D×F) 降为 O(F) 一次性。
- **syncIndex 批量块计数**：新增 `BlockDao.countsForVault`（一次 GROUP BY），替换逐篇 `countOfNote` 串行查询（735 次 → 1 次）。
- **E1 reindexPaths 循环外建解析表**：`buildResolverFromNotes` 提到循环前一次传入 indexNote。
- **loadBookmarks Set 化**：`vaultFiles.includes`（O(B×F)）改 Set 查找。
- **首页 Repeat key 修正**：文件/书签/宫格三处列表 key 追加 `openedAt`（同路径重开后强制重建卡片）；标签 chip key 移除 `activeTag`（此前每次点选标签全网格销毁重建，滚动位置丢失——V2 细粒度更新可保证高亮刷新）。
- **6 处 fire-and-forget 补 .catch**：DesignIndex loadVaultGraph×2 / createNote×2 / openDailyNote / restoreSession。
- 验证：`devecocli check arkts`（10 文件）0 错误；`devecocli build` exitCode=0（签名构建成功）。

## 近期变更（2026-11-19，WYSIWYG 编辑器 v1.4.0 评审修复：粘贴数据损坏 / 表格位图泄漏 / 按键全篇扫描）

严格代码评审后修复 Top 3 缺陷（WysiwygEditorEngine.ets / WysiwygCodec.ets）：

- **D1 粘贴/回车插入空行数据损坏**：运行时新建段落默认 `tightBreakAfter=false`，多行粘贴后导出时每行之间被插入空行（5000 行笔记粘贴即损坏）。修复：`spliceMetasMultiLine` 内部行强制 tight、旧尾行的块边界紧凑标志迁移到新序列末行；Enter 拆行各路径（HR/段落/标题/连续列表/通用）统一「新行继承旧行 gap、旧行变 tight」语义，列表内回车不再产生松散空行。
- **M1 撤销/重做表格 PixelMap 泄漏**：`applySnapshotPatch` 增量补丁给重渲染表格分配新 `blockGroupId`，旧表格位图（2-6MB/张）在 Map 中永久滞留。修复：补丁完成后新增 `releaseStaleTablePixelMaps()`，比对当前 metas 引用的 tableId，释放并删除全部孤儿位图。
- **P1 按键热路径 O(n) 全篇扫描**：`syncMetaCountToPlainText` 的 `split('\n')` 与 `countNewlines` 前缀字符循环每按键执行 6-8 次。修复：新增 `lineStarts` 行起始偏移索引缓存（`ensureLineIndex` 惰性构建、同一字符串引用 O(1) 命中），热路径 `lineIndexAt`（二分）/`lineRangeAt`（O(1)）替换 IME 输入前/删除前/变更/选区/格式态/补全查询等全部逐键调用点。
- **P2 源码→所见切换光标映射 O(k²)**：`WysiwygCodec.wysiwygOffsetFromSource` 逐段线性调用 O(k) 的 `sourceOffsetFromWysiwyg`。修复：段行首源码偏移单调不减，改二分定位目标段落，降为 O(k·log k)。
- 验证：`devecocli check arkts`（2 文件）0 错误；`devecocli build` exitCode=0（签名构建成功）。

## 近期变更（2026-11-17，搜索页标签面板改固定五行横向滑动网格）

- 痛点：标签模式原用 `Flex(wrap)` 平铺全部标签（355 个），面板随页面无限撑高，选完标签要滚很久才能看到筛选结果。
- 改造：标签区改为 **Grid `rowsTemplate('1fr 1fr 1fr 1fr 1fr')` 固定 5 行、左右滑动**（高 212vp，列宽自适应内容），配 `Repeat virtualScroll` 懒加载，几百标签内存恒定；排序切换（数量↓/名称）、清除筛选、计数徽标全部保留。
- 效果：面板总高固定约 300vp，选中标签后筛选结果紧跟其后立即可见（实测 #google「找到 4 篇笔记」直接可见，无需滚动）；三台模拟器部署冒烟 PASS，5555 实测横向滑动/点选筛选全通过。

## 近期变更（2026-11-17，更多页新增「关于」页）

- 设置组新增第 5 行「关于」（m_about，`sys.symbol.info_circle`，副标题「GitHub 开源项目」），复用 SettingsSheet 浮层新增 `SettingsSheetMode.ABOUT` 模式。
- 关于页内容：应用图标（startIcon）+ 名称 + **动态版本号**（`bundleManager.getBundleInfoForSelfSync` 读 versionName，替换原硬编码 v1.2.0）；简介与数据说明；开源分组三行（GitHub 仓库 / 检查更新→Releases / 开源许可→LICENSE，点击经 `openExternalLink` 跳系统浏览器）；MIT 版权行。
- 清理：删除外观 sheet 底部 `settings_about` 硬编码版本文案及其字符串资源（版本信息统一由关于页动态展示，避免双份维护）。

## 近期变更（2026-11-17，首页/工作台交互重构：更多页瘦身、FAB 语义统一、新建即编辑）

### 1. 更多页签重构（移除低价值模块，收敛层级）
- 删除「知识库四联统计卡」（moreStatsCard，笔记/收藏/标签/快照数字入口）与「最近笔记足迹卡」（moreHistoryCard）——统计可从文件页段栏直接看到，足迹与文件页时间线重复。
- 工具组删除「标签管理」入口（m_tags）——标签浏览已在搜索页标签模式（modeChips 全文/标签/属性）全覆盖；`openTagSearch()` 方法随之删除（工作台标签芯片跳转 `openWorkspaceTagSearch` 保留）。
- 新结构仅两层白卡：**笔记工具**（今日日记/模板库）+ **设置与数据**（仓库管理/WebDAV 同步/外观与阅读/备份与维护）。

### 2. 工作台 FAB：新建笔记 → 进入编辑模式（WorkspaceView/EditorPane）
- `newNoteFab` 重命名 `editFab`：点击 `vm.startEdit()` 进入当前笔记编辑态；显示条件收紧为 `!editMode && selectedPath 非空 && 非外部只读模式`（无选中笔记/外部预览不再显示）。
- **顶部编辑按钮移除**（决策：与 FAB 功能重复，精简阅读态顶栏为 收藏星标 + 信息面板 + 三点菜单）；`promptImportBeforeEdit()` 一并删除（外部预览导入走横幅按钮）。
- 快捷键迁移：Ctrl+E → editFab；Ctrl+N（新建笔记）保留为 notesHeader 隐藏热区（与 Ctrl+P/Ctrl+O 同款 Blank 挂载方式）。

### 3. 首页新建与编辑界面统一（移除简陋快速编辑器半模态）
- 首页 FAB **短按**：原打开 editorSheet 快速笔记半模态 → 改为 `createNoteAndJump()` 直接新建并跳入工作台**编辑态**（与编辑现有笔记完全同一界面，消除割裂感）；长按气泡菜单（今日日记/新建笔记/模板库）不变。
- 关键修正：`createNoteAndJump()`/`openDailyAndJump()`/`quick_note` 桌面快捷方式均改为 `openWorkspace({})` **不传 openPath**——`openNote→applyDocument` 会复位 `editMode=false`，而 `vm.createNote()` 内部已 openNote+startEdit，重复传 openPath 会把编辑态打回阅读态（旧 bug：气泡新建后落到阅读模式）。
- 整体删除：editorSheet Builder、showQuickEditor/draftTitle/draftBody 状态、openQuickEditor/closeQuickEditor/saveQuickEditor、DesignInsertChip 类与 insertChips 数组、VaultViewModel.createQuickNote()（无调用方）；返回键链、外部打开前弹层清理同步更新。

### 4. 验证
- `devecocli check arkts`（4 文件）仅剩已知 app.string 误报；`devecocli build` exitCode=0。
- 三台模拟器（5555 Mate 90 Pro kk 库 / 5557 Mate X7 / 5559 MatePad）部署冒烟 PASS；5555 a11y 树确认首页结构完好（736 篇段栏/三页签/FAB）。
- 触摸注入受已知模拟器环境问题限制，更多页新结构与 FAB 新交互未做点击走查（触摸不可用），待模拟器重启后可人工或授权 `verify_ui` 验证。

## 近期变更（2026-11-17，文件页懒加载重构：修复大仓库卡顿与内存暴涨闪退）

### 1. 根因定位（Mate 90 Pro kk 库 735 篇实测）
- 旧实现：文件页笔记/收藏两分段在非懒加载 `Scroll` 中用 `ForEach` 一次性构建全部笔记卡片（列表/时间线/宫格三种视图均如此），735 张卡片 → 冷启动 RSS **690MB**（`hidumper --mem` 显示 native heap 446MB，ArkTS 堆仅 45MB）、首帧后主线程阻塞 **3.18s**（`recv vsync timeout` 日志）；真机内存吃紧被系统查杀即"闪退"。小仓库（12 篇）对照 RSS 仅 231MB，差值随笔记数线性增长。

### 2. 重构方案（DesignIndex.ets）
- **列表/时间线模式**：`Scroll + ForEach` → `List({space,scroller}) + Repeat<RecentNoteItem>().virtualScroll({totalCount}).key().each()`，`.cachedCount(6)`，仅构建可见+缓存卡片，滚动内存恒定；底部用 `.contentEndOffset(胶囊底栏高度)` 预留避让。
- **书架宫格模式**：`Grid(undefined, {regularSize:[1,1], irregularIndexes, onGetIrregularSizeByIndex}) + Repeat().virtualScroll()`，首项精选大卡用 `irregularIndexes:[0]` + `[1,2]` 跨双列，`templateId/template('featured')` 双模板区分精选大卡与便签卡。
- 排序/文件夹筛选工具行改为固定 `filesToolbarRow`/`bookmarksToolbarRow`（不再随列表滚动），空态保留 Scroll 壳。
- 删除废弃的 `noteGridThreeCol`/`gridNoteRows`（行拆分全量构建路径）。

### 3. 验证（三台模拟器实测）
- Mate 90 Pro（735 篇）：冷启动 RSS **690MB → 283MB（-59%）**，vsync timeout（3.18s 主线程阻塞）消除；a11y 树仅含 ~8 张可见卡片（旧实现 ~735 张全量挂载），卡片标题/文件夹徽章/路径/排序胶囊/底部导航渲染完整。
- Mate X7、MatePad Pro 13：安装冒烟 PASS，RSS 231~234MB 无回归。
- 触摸注入受已知模拟器环境问题限制，时间线/宫格深滚动未实际驱动（结构同构、构建通过）；`verify_ui` 未执行（待用户授权后可做 UI 走查）。

## 近期变更（2026-11-17，标签系统对齐 Obsidian 规范）

### 1. 标签合法性单源收敛（TagRules）
- 新建 `features/markdown/.../parser/TagRules.ets`，四处字符集重复实现（InlineParser/SearchTextParser/DataViewQuery/IndexPipeline）收敛为一份：标签体允许 ASCII 字母数字 + `_-/` + CJK 文字（汉字/假名/谚文/々〆〇 白名单区间），拒绝 CJK 标点（`）、`，`等全角字符）、纯数字（`#2026`）与 3/4/6/8 位十六进制色值（`#1A1A2E` 设计令牌误报源）；`#0day`、`#6g` 等含非 hex 字母的仍为合法标签。
- frontmatter 显式 tags 同样走 `TagRules.isTagBody` 校验（`IndexPipeline.addTag`），非法值（如 `192.168.3.115`）不入索引，属性卡仍按原文展示。

### 2. 大小写不敏感、下划线与嵌套标签
- 标签允许 `_`（`#to_do` 完整解析）；索引时统一小写归一，查询侧 SQL `COLLATE NOCASE` + LIKE（过渡期旧混合大小写行无需等重索引即可命中）。
- 嵌套标签层级匹配：搜 `#项目` 命中 `#项目/进行中`——TagDao/SearchDao 用 `tag = ? COLLATE NOCASE OR tag LIKE 'xx/%' ESCAPE '\'`；DataViewQuery 边界扫描（后继为非标签字符或 `/` 才命中，避免 `#项目2` 误报）。

### 3. `tag:` 搜索语法
- 新建 `SearchTextParser`（markdown/parser）：`tag:#x`/`#x` 包含、`-tag:#x`/`-#x` 排除、`OR` 同组备选、`AND`/相邻分别要求，剩余词保留为关键词；`SearchQuery` 新增 `tagGroups/tagExcludes`，`SearchDao.search` 解析并拼 SQL（含 LIKE `ESCAPE '\'` 转义）。

### 4. DB 迁移 v7 + 全量重索引 + 孤儿行清理
- `CURRENT_VERSION` 6→7（v6 仅为过渡版未发布）：迁移块 `version < 7` 设 `pendingFullReindex` 标记并 `DELETE FROM tag WHERE note_id NOT IN (SELECT id FROM note)` 清理已删笔记遗留的孤儿标签行（kk 库实测清出 40+ 行）；`VaultViewModel.ensureIndexed` 消费标记后 fire-and-forget `rescanVault()`，升级用户自动全量重索引清除旧规则误报。
- 新增单测：`rejectsCjkPunctuationInTag`、`rejectsNumericAndHexColorAsTag`、`parsesUnderscoreTag`、`matchesNestedTagHierarchy`、`matchesTagCaseInsensitive`、`parsesSearchTextTagClauses`。

### 5. 验证（三台模拟器实测）
- Mate 90 Pro（kk 库 735 篇）：v7 迁移日志 + 全量重索引完成，标签 394→353，`#10）`/`#1a1a2e）导航`/`#9，deepseek`/`#192.168.3.115` 等残留全部清除（sqlite3 直查 DB 确认零残留），合法标签（`#/plan/26`/`#0day`/`#ai` 43/`#task`/`#开源情报`/嵌套 `#ai/*`）全保留且全部小写。
- `tag:` 语法 SQL 语义在设备 DB 实测：`tag:#ai`=55（含 `ai/deepseek` 等子标签嵌套命中）、大写 `tag:#AI` 同为 55（NOCASE 生效）、`tag:#开源情报`=14、排除子句 NOT IN 正常；搜索框 UI 文本注入受已知模拟器环境问题限制未驱动，解析逻辑由单测覆盖。
- Mate X7（示例仓库 12 标签）与 MatePad Pro 13（6 标签）均迁移 v7、标签列表干净无垃圾。

## 近期变更（2026-11-17）

### 1. 阅读态正文顶部渲染 frontmatter 属性卡（问题 1+2）
- 新增 `MdPropertiesView`（markdown 模块）：阅读态正文顶部以圆角卡片展示 YAML frontmatter 属性行（key 次要色 + 值），`tags`/`tag` 属性渲染为可点击胶囊芯片（去 `#` 展示、点击跳转标签检索，与正文行内标签一致），列表值渲染为普通芯片，嵌套 map 以等宽字体原文保留，空值显示 `—`；芯片分词与 `FrontmatterParser` 一致（空白/逗号/`#` 分界）。
- `MdDocumentView` 在块列表前插入属性卡 `ListItem`（仅 `frontmatter.properties` 非空时），`scrollToBlock` 大纲定位按属性卡占位 +1 偏移修正；工作台阅读态与编辑器预览态共用生效。
- 已在 Mate 90 Pro（kk 库 737 篇）、Mate X7 与 MatePad Pro 13（示例仓库，含宽屏三栏）实测：属性卡渲染、标签芯片点击跳转标签检索均正常。

### 2. 工作台新建笔记直接进入编辑态（问题 3）
- `VaultViewModel.createNote` 在 `openNote` 后调用 `startEdit()`：FAB / 菜单 / Ctrl+N 新建笔记不再停留在阅读态，直接进入编辑器（模板路径原本即进编辑态，行为统一）。
- Mate 90 Pro 实测：FAB 新建 → 编辑器（标题栏取消/保存 + TextArea）→ 输入 → 保存 → 阅读态渲染正常，测试笔记已清理。

### 3. 修复跨设备删除后笔记"自动恢复"（同步引擎核心缺陷，已提交 2af939c）
- **根因**（模拟器持久 hilog 实锤）：`decideLocalEntry` 对"本地存在 + 远端消失"一律返回 `PUSH_NEW`，即使本地基线 synced 且内容未变。多设备同库时，A 端删除笔记（远端 MOVE 至 `.trash/`）后，B 端下一轮同步把该文件**重新推回远端**，A 端再按 serverTag 变化 `PULL_NEW` 拉回——删除在 10 分钟被动同步周期内"自动恢复"（实测日志：2026-11-16 22:13 `real 731→729` 后模拟器 `sync push` 重传手机端刚删的 2 篇笔记）。
- **修复**：`decideLocalEntry` 在 `remote === undefined` 且基线 `synced`、`baseline.fileHash === local.etag`（本地未改）时返回新增决策 `TRASH_LOCAL`；新增 `executeLocalTrashes` 经 `VaultManager.trashNote` 把本地文件移入仓库回收站并清理索引，执行前用 `WebDavProvider.stat()` 独立 HEAD 探测二次确认远端确实已不存在（防部分列举/竞态误删），远端仍存在则跳过等待下轮自愈。本地已改（哈希与基线不符）仍走 `PUSH_NEW` 保留用户修改。
- 远端软删与本地传播统一计入 `evaluateSafetyGate` 批量删除闸门（≥10 个或 ≥30% 需确认），`SyncPlanSummary.trashes` 合并两侧计数，确认卡片与样例路径（`collectSamplePaths`）覆盖 `localTrashes`。
- 单测：`SyncEngine.test.ets` 新增 synced/已改/conflict/local_deleted/无基线 五分支决策断言。

### 4. 修复空笔记推送失败被误判为认证故障（WebDAV 空请求体缺陷，已提交 2af939c）
- `sendOnce` 对空字符串 body 也设置 `options.extraData = ''`，OH http 模块抛 BusinessError 401 "Parameter error"（本地参数校验错误，非 HTTP 401），经 3 次重试后进入 `isAuthOrConfigError` 的 `(401)` 匹配 → `sync partial failure` → **300s 认证冷却**，期间一切自动同步静默停摆（新建笔记 1 秒后的首次推送即触发）。空字符串 body 现直接省略 `extraData`（0 字节 PUT 正常发送）。
- `WebDavProvider.stat()` 由全量 `list('')` 重查改为单路径 HEAD 探测（原实现与列举同源，无法防部分列举误判；该方法此前无调用方，语义安全变更）。

### 5. 验证（Mate 90 Pro 模拟器 + 真实 fnOS WebDAV 实测，同步修复部分）
- 工作台 FAB 新建空笔记 → 2 秒后自动同步推送 0 字节文件一次成功（旧版必报 `Parameter error (401)` 并进入冷却；远端 HEAD 确认 `200 len=0`）。
- PowerShell 模拟另一设备将远端文件 MOVE 至 `.trash/` → 模拟器下轮 `sync trash local`（无 `sync push`），本地文件入 `1794886649221_未命名-*.md` 回收站、DB 行清理；再下一轮 737/737/737 全一致无复活。
- 三台模拟器（Mate 90 Pro / Mate X7 / MatePad Pro 13）安装启动无异常。

## 近期变更（v1.0.0，2026-11-15）

### 1. 首页质感重构、透明毛玻璃与原地目录穿透
- 首页「笔记」默认采用列表视图，引入 5 组低饱和莫兰迪纸色令牌（浅/深双主题 `design_tint_*`），移除单行横向溢出（搜索标签与编辑器 17 项工具栏统一 `FlexWrap.Wrap` 自动换行，解决浅色模式下编辑工具栏按钮文字对比问题）。
- 顶栏、分段胶囊、搜索框与悬浮分离式底栏统一采用半透明毛玻璃（`BlurStyle.Thin` + `design_glass_*`），内容滚动经过控件下方实时变色。
- 「更多」与设置中心按单一职责去重（移除鸡肋「工作台」与重复快捷按钮，设置分为「外观与阅读」/「备份与维护」两张紧凑卡片）；隐藏 `NoteInfoPanel` 默认知识图谱入口（代码完整保留）。
- 首页「笔记 / 文件夹」列表改为原地逐级穿透浏览，顶部展示可点击面包屑（`全部目录 › 父目录 › 当前目录`），列表/宫格双视图切换且不误开正文文档，系统返回键逐级向上退出。

### 2. 日记年月分卷与全场景形态自适应
- 将每日日记、闪念追加、日历跳转与桌面服务卡片统一收口至 `VaultPath.dailyNotePath`（`日记/YYYY-MM/YYYY-MM-DD.md`），兼容历史根目录日记，并修复 `VaultPath.dirname` 对多层目录创建的前导斜杠 bug。
- 解耦窄屏/折叠屏（`< 900vp`）浮动信息抽屉与宽屏平板固定三栏，避免打开笔记时误弹右侧大纲遮挡正文。

### 3. WebDAV 无感安全同步与自签名开关
- `SyncEngine` 升级为干跑规划 + `evaluateSafetyGate` 安全闸门 + `persistPartialCheckpoint` 逐文件断点落盘：零差异或纯拉取静默通过，本地删除改为 `WebDAV MOVE` 至 `.trash/` 软删除（服务端不支持 MOVE 时写墓碑保留远端），并绑定 `targetKey` 防止换库/换目录误删。
- 新建仓库配置（`DialogHost`）与同步设置（`SyncSettingsSheet`）提供独立的「跳过证书校验」开关（默认关闭），适配自签名内网 WebDAV。

### 4. 系统 `.md`「打开方式」与 Share URI 支持
- `module.json5` 新增 `FileOpen` skill（`entity.system.default` + `viewData`/`editData`，匹配 `general.markdown`、`text/markdown` 及 `.md`/`.markdown`），支持文件管理器及其他应用冷/热启动打开外部 Markdown（`DefaultAbility` + `AbilityContextHolder`）。
- 外部文件以只读原生预览呈现（顶部提示条 + 内存提取大纲/标签 + 编辑防误改引导弹窗），支持一键导入当前仓库（含无库时建库导入），并补齐 `ShareExtensionAbility` 对文件 URI 的文本读取。

### 5. 全新分层应用图标、测试与代码规范收尾
- 重绘 `Ceramic Washi & Obsidian Prism Fold` 鸿蒙分层应用图标（`$media:layered_image` `1024×1024`）及浅/深双主题 `256×256` 冷启动图标（`startIcon.png`），同步统一桌面与应用内显示名称为 `MySidian` 及关于页 `v1.0.0` 版本信息。
- 将 `features/markdown` 内 `MdBlockView` / `MdMermaidView` 的 `app.color.design_*` 跨模块引用迁移为模块自有 `app.color.md_*`，消除 `md_dataview_empty` 重复声明告警，修复 `CodeHighlighter` 缺少 Python `'def'` 关键字及补全单测索引断言、`HighFrequencyLog` 等 CodeLinter 问题。

## 近期变更（v0.6.0，2026-11-15）

### 1. 查询引擎 RDB 加速与列表项索引闭环（完成原待办 #4）
- **列表/任务块全文与标签入库**：修复 `BlockDao.plainTextOfBlock` 对 `LIST` 块（`block.inlines` 为空、文本存于 `block.items`）返回空串的缺陷，新增 `itemsText` 递归提取列表文本入库 `block.block_text` 与 `note_fts`；`IndexPipeline` 新增 `collectItemTags` 递归提取列表项内 `#tag` 入库 `tag` 表。
- **Dataview TABLE/LIST 与 TASK 查询 RDB 化**：`TagDao.tagsByVault` 与 `PropDao.propsByVault` 单次 SQL 批量拉取全库笔记的标签与属性；`VaultViewModel.collectEntries` 在无正文 `contains(text, ...)` 过滤时零磁盘 I/O 直接从 RDB 组装 `NoteEntry`；`runDataViewQuery` 对 `TASK` 查询支持按 `TagDao.notesByTag` 预过滤候选笔记。
- **日历月度统计批量 SQL 化**：新增 `BlockDao.listBlocksByPaths`（200 条分批 `IN` 查询），`VaultViewModel.calendarMonth` 不再逐篇读取磁盘 Markdown 文件解析未完成任务数。

### 2. 原生代码块语法着色（完成原待办 #3）
- 新增 `features/markdown/src/main/ets/render/CodeHighlighter.ets`：零正则回溯风险的线性扫描词法分析器，识别行/块注释（`//`、`/* */`、`#`）、字符串（`"`、`'`、`` ` ``）、数字字面量、ArkTS/TS/JS/Python/Java/Go/Rust/C/SQL 关键字与常见类型名。
- 深浅双色板新增 `md_code_keyword`、`md_code_string`、`md_code_comment`、`md_code_number`、`md_code_type`；`MdBlockView.codeView` 使用多色 `Span` 渲染，并新增 `CodeHighlighter.test.ets`（4 项单测）。

### 3. 书签置顶系统（`★ 书签`，完成原待办 #5）
- `VaultViewModel` 新增按仓库持久化的 `@Trace bookmarks: string[]`（支持 `isBookmarked`、`toggleBookmark`，并在笔记重命名/移动/移入回收站时自动同步或清理书签路径）。
- 三处 UI 联动：编辑器顶栏预览态星标按钮（`sys.symbol.star` / `star_fill`）、文件树节点菜单（`TreeItemMenuSheet` 加入/取消书签）、工作台侧栏顶部「★ 书签」置顶区与首页「文件」页签顶部「★ 书签」卡片区。

### 4. 定期与一键本地快照备份恢复
- `ZipTransfer` 新增沙箱直写 `compressToFile` / `decompressFromFile`；`VaultManager` 新增 `createBackup`、`listBackups`、`restoreBackup`（存于 `<filesDir>/backups/vault_<id>_<timestamp>.zip`，自动轮转最多保留 5 份）。
- `VaultViewModel` 在打开仓库时按 24 小时周期自动创建本地快照备份（`autoBackupIfNeeded`）；`SettingsSheet` 新增「本地快照备份」专区，支持一键创建快照、查看快照时间与体积、一键恢复任意快照并自动重建索引。

### 5. 2in1 / 平板键盘快捷键与桌面长按快捷方式
- **2in1 键盘快捷键**：`EditorPane` 与 `WorkspaceView` 挂载 `.keyboardShortcut`——`Ctrl+S` 保存草稿、`Ctrl+E` 切换编辑/阅读、`Ctrl+F` 页内查找替换、`Ctrl+N` 新建笔记、`Ctrl+P` 命令面板、`Ctrl+O` 快速切换器。
- **桌面长按快捷方式（App Shortcuts）**：新增 `shortcuts_config.json` 与 `module.json5` `ohos.ability.shortcuts` 元数据，提供「新建闪念」「今日日记」「全局搜索」三项桌面快捷入口，支持冷启动与热启动（`DefaultAbility` + `AbilityContextHolder` + `DesignIndex.consumeShortcutAction`）。
- 应用版本号升至 `v0.6.0`（`versionCode: 1000008`）。

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

## 近期变更（未发布，v0.4.0）

### 审美、架构安全与生产力全方位优化（2026-11-15）

- **安全与同步层加固**：
  - **WebDAV 密码硬件级加密（Asset Store Kit）**：新增 `common/src/main/ets/utils/SecretStore.ets`（`@kit.AssetStoreKit`，`DEVICE_FIRST_UNLOCKED` 访问控制）；`SyncViewModel` 启动自动将旧版 `preferences` 明文密码迁移至 `SecretStore` 并清空明文残留（真机/模拟器 hilog 与 preferences XML 实测验证）。
  - **证书校验风险警示与状态本地化**：`SyncSettingsSheet` 开启「跳过证书验证」时展示 `$r('app.color.design_danger')` 红色安全提示；`SyncViewModel.statusText` 全面接入 `$r('app.string.sync_status_*')`。
  - **同步冲突处理中心（Conflict Center）**：`SyncSettingsSheet` 与 `SyncViewModel` 新增冲突逐条「对比差异」（内联展开 LCS 行级 Diff）、「保留本地」（清理冲突副本）、「采用远端」（先调用 `FileHistory.snapshot` 保护本地，再覆盖并重索引）。
  - **同步本地哈希缓存（DB v4）与决策单测**：`DbHelper` 升至 v4（`sync_state` 新增 `size` 列，平滑 `ALTER TABLE` 迁移）；`SyncEngine.isHashReusable` 对 `mtime` 与 `size` 未变且早于上次同步 2 秒以上的文件直接复用基线 SHA-256，消除大库同步全量重算；抽出 `SyncEngine.decideLocalEntry` / `decideRemoteOnlyEntry` 纯函数并新增 `SyncEngine.test.ets`（9 项单测）。
- **搜索、索引与大库性能**：
  - **FTS5 自愈与 BM25 相关性排序**：`DbHelper` 每次打开探测 `FTS_V1`，`VaultViewModel.syncIndex` 对比 `listFtsRowIds` 自动补建缺失的全文索引；`SearchDao.searchByFts` 引入 `bm25(note_fts, 10.0, 1.0)` 标题高权重排序；`SearchDao.fillSnippets` 改为 200 条分批 `note_id IN (...)` + `ESCAPE '\'`，消除 `N+1` 查询。
  - **未链接提及 RDB 化**：`BlockDao.findMentions` 直接在 `block` 表按 `LIKE ... ESCAPE '\'` 检索正文块，消除逐篇读取磁盘 Markdown 文件的开销。
- **编辑器、文件树与阅读体验（完成原待办 #1/#2/#3/#4）**：
  - **页内查找与替换**：新增 `FindReplaceUtils`、`FindReplaceBar` 与 `FindReplace.test.ets`（7 项单测）；编辑态顶栏放大镜按钮展开查找/替换栏，支持匹配计数、上下跳转（`setTextSelection` + `MenuPolicy.HIDE`）、单次替换与全部替换（自动记入撤销栈）。
  - **文件树节点操作菜单**：`FileTreeView` 新增行尾 `⋯` 按钮与 `onItemAction` 回调；新增 `TreeItemMenuSheet`（文件夹：在此新建笔记 / 新建子文件夹；笔记：打开 / 分屏双开 / 重命名 / 移动到… / 移入回收站）。
  - **图片全屏预览与双指缩放**：新增 `ImagePreviewOverlay`（`PinchGesture` 1x–5x 缩放、`PanGesture` 拖拽、双击 1x/2.5x 切换、返回键关闭），点击笔记内任意图片即可全屏查看。
  - **全库图谱手势增强**：`DesignIndex` 图谱页支持双指捏合缩放（1x–16x）、单指平移、缩放按钮及按节点度数动态分级显示标签。
- **审美、深浅色切换与无障碍**：
  - **设计令牌与语义色收敛**：新增 `DesignTokens.ets`；新增 `design_on_accent`（浅色 `#FFFFFF` / 深色 `#141211`），清除 9 个视图文件中的 `Color.White` 与硬编码十六进制色值。
  - **应用内主题模式切换**：`SettingsSheet` 新增「主题模式」（跟随系统 / 浅色 / 深色）胶囊选择器，联动 `ApplicationContext.setColorMode` 并持久化，解锁模拟器的深色模式实机验证。
  - **无障碍基线**：为 `EditorPane` 与 `WorkspaceView` 核心纯图标按钮补齐 `.accessibilityText(...)`。

### 单页架构 Material 3 全量重构（2026-11-15，7 阶段）

以 DesignIndex 为**唯一 @Entry**，旧 4160 行工作台 `pages/Index.ets` 全部功能等价迁移为**页内全屏子视图**，删除 router 跳转与旧组件群（净删 ~5400 行）。

- **阶段 1**（75e75b7）：design_ 色板深浅双模式（base/dark 两份 color.json，跟随系统）；`DesignPalette` 运行时取色；drawGraph design 化。
- **阶段 2**（cfaf906）：单页状态机——DesignIndex 内 HOME（四页签）/WORKSPACE 两模式切换（viewMode + animateTo 进出场）；键盘避让策略迁移（窄屏编辑态 NONE、其余 RESIZE）；`WorkspaceView` 骨架。
- **阶段 3**（d220aa7）：工作台核心迁移——`CompletionPopup`/`EditorToolbar`/`NoteInfoSheet`/`EditorPane` 新建，WorkspaceView 重写（文件树/编辑器/信息面板三区）；`sys.symbol.sidebar_left` 不存在，以 SDK `id_defined.json` 查证换 `rectangle_lefthalf_inset_filled`。
- **阶段 4**（9a90423）：弹层 A——`DialogHost`（新建仓库/删除确认/重建索引/创建请求四场景）、`TrashSheet`/`HistorySheet`/`TemplateSheet`。
- **阶段 5**（8642f62）：弹层 B 与全局浮层——`CalendarSheet`/`HandwriteSheet`/`QuickNoteSheet`/`CommandPalette`/`QuickSwitcher`/`RecentNotesPanel`/`SearchOverlay`/`OnboardView`/`SyncSettingsSheet`/`SettingsSheet`/`VaultManagerSheet` 共 11 件；WorkspaceView 全量接线（17 项 moreMenu、handleBack 全链、命令表、手写插入桥接、快切分屏）；DesignIndex 顶层 Stack 挂全局浮层。
- **阶段 6**（387fbc9）：删除 `pages/Index.ets` 与 8 个已替换旧组件（CalendarPanel/CommandPalette/HandwritePanel/QuickSwitcher/RecentNotesPanel/SearchOverlay/SettingsOverlay/SyncSettings）；`main_pages.json` 只留 DesignIndex；外部启动参数迁移至 DesignIndex（`handleLaunchParams`：openPath/expandPath/action→工作台或全局浮层）。**保留** `view/NoteInfoPanel.ets` + `GraphView.ets`——design 层 `NoteInfoSheet` 是其 Material 3 包装层（五页签数据引擎），后续如需彻底收编可把二者内联进 design。
- **阶段 7**：验证与文档（本节）。

**验证状态（2026-11-15，阶段 6 后）**：`devecocli build` 成功（24s）；三台模拟器（5555 Mate 90 Pro / 5559 Mate X7 / 5557 MatePad）签名包安装启动成功、Smoke PASS，截图像素分析 avgRGB≈245-247 且文件 235-346KB（浅色主题、内容丰富、非白屏）；faultlog 仅存 2026-11-11 旧 jscrash（重构前遗留），本轮零新增。真机（nova 14 Ultra，192.168.3.149:42073）签名包安装启动成功、Smoke PASS。深色模式运行时验证受阻：该模拟器镜像不支持 `persist.ace.darkmode` 参数（errNum 1002），settings 表无 dark/theme 键，无法 hdc 强切；dark 色板正确性以构建期资源校验为准，待模拟器设置界面手动切换或真机补验。

关键机制：

- **返回键下探**：onBackPress 无法直达子组件——`WorkspaceBackSignal`（@ObservedV2+@Trace count）信号对象，DesignIndex onBackPress→request()，WorkspaceView @Monitor('backSignal.count') 消费，链序 dialog→trash→…→sideBar→exit。
- **弹层按需挂载**：父级 if 条件渲染→每次打开全新实例，内部 @Local 在 aboutToAppear 按场景预填。
- **手写插入桥接**：`VaultViewModel.onInsertTextAtCaret` 钩子 + EditorPane 生命周期注册 + WorkspaceView.saveHandwrite 分流（编辑态直插/预览态 startEdit+150ms 延迟+atEnd）。
- **状态分代纪律**：WorkspaceView 为 @ComponentV2（@Local/@Param/@Event/@Monitor），深层突变配 slice()/key 重建；Vm 均 @ObservedV2+@Trace。

### Material 3 首页改版：DesignIndex（2026-11-14）

- **新首页 `pages/DesignIndex.ets`**（约 1785 行，`@Entry`）：Material 3 悬浮分离式胶囊底栏（左侧胶囊页签含滑块指示器 + 右侧 FAB），四个页签——文件（根级目录卡片 + 最近笔记）、搜索（全文/标签/属性三模式 chips，头/命中/尾三段高亮拼接，250ms 防抖）、图谱（力导向布局 Canvas 绘制，选中节点放大加光晕、关联边高亮，再点选中节点跳工作台打开）、更多（同步/导出/模板等入口）。
- **入口切换**：`DefaultAbility.loadContent` 改为 `pages/DesignIndex`；原 `pages/Index` 降级为编辑工作台，经 `router.pushUrl` 携参进入。`main_pages.json` 注册两个页面。
- **首页→工作台路由参数**（`Index.handleLaunchParams`，`vm.init` 完成后处理、防重入）：`openPath` 直接打开笔记、`expandPath` 展开目录、`action`（`templates`/`vaults`/`settings`）打开指定面板。
- **VaultViewModel 扩展**：`RootFolderSummary`（根级目录笔记数摘要 `rootFolders`，`refreshRootFolders` 在 `refreshTree` 后汇总）、`restoreSession()`（从工作台返回首页后恢复上次会话）、`createQuickNote()`（首页闪念/快速笔记：标题非法字符过滤、同名追加时间戳、空标题用「闪念-时间戳」）。
- **资源**：string.json +452 行；color.json 深浅色各 +48 行（design_* 系列）；版本 0.3.1 → 0.4.0（versionCode 1000007）；`.gitignore` 增加 `/dist/`。
- **验证**（2026-11-14）：`devecocli check arkts` 无真实错误（仅剩已知资源名误报）；`devecocli build` 成功；三台模拟器（5555 Mate 90 Pro / 5559 Mate X7 / 5557 MatePad）装机启动成功，无 faultlog，hilog 确认 "Succeeded in loading the content"，截图像素分析为暗色主题且内容丰富（非白屏）。a11y 树仍只返回根节点（已知模拟器环境问题），点击级交互验证待模拟器恢复后补验；多模态截图识别工具本轮 400 报错不可用。

### 全面 bug 排查修复（2026-11-12）

三个并行探查（存储/同步、Markdown 引擎、UI 层）共审出约 40 项问题，全部修复：

- **同步/存储**：`SyncStateDao` 重写（vault 维度 + 事务化）+ DB v3 迁移；`SyncProvider` 补 `deleteRemote`；WebDavProvider 逐级 MKCOL / 幂等删除 / 临时文件 + rename 原子写；SyncEngine 删除传播、pull 前快照、etag 统一 sha256、冲突副本走 `readRemote`；NoteDao FTS 清理；回收站序号防覆盖；FileHistory 新编码 + 旧编码兼容 + 回滚前快照；LinkRewriter 路径限定；`{{cursor}}` 截断修正。
- **Markdown 引擎**：有序列表保留源码序号（M10）；闭合围栏须纯围栏字符（M8）；URL 自动链接括号配平（InlineParser `findUrlEnd`）；frontmatter 嵌套 map 以 `MdPropType.MAP` + `rawBlock` 原样保留、可删除（M7）；DataView 日期比较改算子模型（dueOp/startOp/scheduledOp，M4）；`FROM #tag` 统一笔记级语义；Mermaid 双圆/边正则交替修复（M11）；数学公式脚本递归深度防护。
- **UI 层**：任务勾选按行号定位替换（`MdListItem.lineNumber`，失配回退首处匹配，U12/M2）；`syncIndex` 清幽灵行（U8）；`openToken` 防打开笔记竞态（U9）；重命名/移动改写历史与最近路径引用（U13）；快速追加补末行换行（U14）；切笔记/编辑态切换清撤销栈与补全（`@Monitor`，U1/U11）；非编辑态手写先入编辑（U5）；4 处 ForEach key 改稳定唯一值（U3）；分享扩展按官方 Share Kit 重写（`getSharedData` + `terminateSelfWithResult`）；卡片 formId 改 `FormParam.IDENTITY_KEY`（U10）；`CopyOptions.Default` → `LocalDevice`。

### v0.3.0 触摸全死回归：根因与修复（2026-11-12）

- **现象**：v0.3.0 所有界面触摸完全无响应（仅系统返回键可用），三台模拟器与真机一致；v0.2.0 正常。最初疑似"模拟器触摸注入失效"，实为应用自身回归。
- **根因**：4b71a43（键盘避让重做）把全部弹层统一包进一个**常驻全屏 `Stack`**（`Index.ets` `build()` 根 Stack 的最后一个子节点，见上文"弹层让位"设计）。无弹层激活时该 Stack 虽为空，但仍占满 100%×100% 且位于最上层——ArkUI 容器按 bounds 参与命中测试，视觉为空并不豁免——**拦截了整屏触摸**。
- **定位**：hap 级/字段级/环境级排查（签名、pack.info、AOT、install 幻影）逐一排除后，源码二分锁定 4b71a43；再对 Index.ets 做 hunk 级二分（dbacd36 基底 + 子集 patch + 编译桩），单 hunk（overlays 包裹 Stack）即可复现触死。
- **修复**：该 overlays Stack 追加 `.hitTestBehavior(HitTestMode.Transparent)`——空态时触摸穿透到底层内容；弹层出现后其子节点自身（Default 模式）照常消费触摸，弹层交互不受影响。
- **验证**（三台模拟器）：5559 全流程（欢迎页点击 → 新建仓库对话框聚焦输入「示例仓库修复测试仓」→ 创建成功进入主界面）；5555 点击打开笔记、5557 文件树展开均正常（真实仓库 `install -r` 保数据升级，零改动）。键盘避让的 padding 上移逻辑不受影响（创建对话框聚焦时正常上移让位键盘）。

### 验证状态（2026-11-12）

- `devecocli check arkts` 通过（仅剩已知资源名误报，真实错误 6 处已修：SharedRecord 可空字段、`SyncBaselineRow` 未导出、CopyOptions 枚举值）；`devecocli build` 成功。
- 三台模拟器（5555/5557/5559）安装新版启动正常、无新增 crash（a11y 渲染验证：5555 任务清单、5557/5559 目录树均正常）。
- 5559 内容注入回归测试通过：有序列表源码序号（5/6/10）、含括号 URL 自动链接、live dataview `TABLE ... FROM #tag WHERE due < date(today) AND start <= date(today)` 正确渲染出该笔记行（页面级 FROM #tag + 日期算子端到端生效）。
- **交互项验证受阻**：三台模拟器触摸注入再次全部失效（含重启后仍无效，5557 重启后 file 通道恢复正常、5559 重启后触摸仍失效），任务勾选、撤销清理、手写保存、分享/卡片扩展等交互行为本轮无法驱动，待模拟器恢复或真机补验。

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

1. ~~文件树长按菜单：目录（在此新建/新建子目录/重命名/删除）、文件（重命名/移动/回收站/分屏打开）。~~ → 已完成（`TreeItemMenuSheet` + `FileTreeView.onItemAction`）。
2. ~~页内查找 & 替换（当前只有全库搜索）。~~ → 已完成（`FindReplaceBar` + `FindReplaceUtils`）。
3. ~~图片点击全屏预览 + 双指缩放；代码块语法着色。~~ → 已全部完成（`ImagePreviewOverlay` + `CodeHighlighter`）。
4. ~~未链接提及（`unlinkedMentions`）、Dataview TABLE/LIST（`collectEntries`）、日历统计（`calendarMonth`）改走 RDB 索引。~~ → 已全部完成（`BlockDao.findMentions`、`TagDao.tagsByVault`、`PropDao.propsByVault`、`BlockDao.listBlocksByPaths`）。
5. ~~书签（★ 置顶区）与全屏全局图谱入口。~~ → 已全部完成（`VaultViewModel.bookmarks` + 首页/工作台书签区 + `DesignIndex` 图谱页）。

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

1. **CLI 单元测试命令**：`common`、`markdown`、`vault`、`default` 四模块均可通过 DevEco Studio 安装目录 `hvigorw.js test --mode module -p "module=common@default,markdown@default,vault@default,default@default"` 在本地命令行直接执行。
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
