# MySidian — HarmonyOS 本地优先 Markdown 笔记应用

类 Obsidian 的鸿蒙原生笔记应用：本地 Markdown 仓库（Vault）、原生渲染引擎、任务管理（obsidian-tasks 兼容）、Dataview 查询块、WebDAV 同步、全文搜索。

## 基本信息

| 项 | 值 |
|---|---|
| 包名 | `com.mrs.mysidian` |
| Ability | `DefaultAbility`（注意：不是 EntryAbility） |
| targetSdkVersion | 26.0.0（compatible 6.1.1 / API 24） |
| 构建系统 | hvigor（DevEco Studio / devecocli） |
| 语言 | ArkTS（严格模式），状态管理 V1 + V2 混用（按 struct 分代） |

## 模块结构

```
AppScope/                  应用级配置与资源
common/                    HAR：常量、EmptyState、FileTreeView、BreakpointSystem、Logger
features/
  domain/                  HAR：纯模型层（MdModel/VaultModel/SyncModel）+ SyncProvider 接口
  markdown/                HAR：Markdown 引擎
    parser/                BlockParser / InlineParser / FrontmatterParser / MarkdownParser
                           TaskMetadata（obsidian-tasks 兼容）/ DataViewQuery（dataview 块解析）
    render/                MdBlockView / MdDocumentView / MdInlineText / MdInlineFlattener / MdWebFallback
  vault/                   HAR：存储层
    db/                    RDB DAO：Note/Block/Link/Prop/Search/Tag/Vault/SyncState
    manager/               VaultManager / VaultPath / ZipTransfer / NoteResolver / FuzzyMatcher
    indexer/               IndexPipeline / Tokenizer
  sync/                    HAR：SyncEngine / ConflictResolver / WebDavProvider
products/default/          主工程（entry）
  pages/Index.ets          唯一 @Entry，承载全部界面与响应式布局
  view/                    NoteInfoPanel / CommandPalette / QuickSwitcher / SearchOverlay
                           SettingsOverlay / SyncSettings / RecentNotesPanel
  viewmodel/               VaultViewModel / SearchViewModel / SyncViewModel / AppCommand
```

依赖方向：`default → markdown/vault/sync/domain/common`；`markdown/vault/sync → domain/common`；禁止反向依赖。

## 构建与运行

```powershell
devecocli build                 # 构建签名 HAP
devecocli check arkts <files>   # ArkTS 静态检查（"Unknown resource name" 类报错为已知误报）
devecocli run --skip-build      # 装机运行
hdc install -r <hap>            # 手动安装
```

产物：`products/default/build/default/outputs/default/default-default-signed.hap`（debug 签名）。

## 功能总览（截至 2026-11）

- **Vault 管理**：多仓库、zip 导入导出、沙箱文件存储 + RDB 索引
- **Markdown 渲染**：自研块级/行内解析器 + 原生 ArkUI 渲染；复杂 HTML 块走 MdWebFallback（ArkWeb）
- **编辑器**：TextArea 源码编辑、草稿保存、编辑/预览切换
- **obsidian-tasks 兼容**：`- [ ]` 任务、✅🛫⏫🔁 等元数据、点击勾选回写 `✅ YYYY-MM-DD`
- **Dataview 查询块**：```` ```dataview ```` 内 `TASK` 查询，支持 WHERE（completed / !completed / contains(tags) / contains(text) / file.name != this.file.name）与 GROUP BY file.link，渲染为可交互任务列表并支持跨笔记勾选回写
- **信息面板**：大纲 / 反链 / 标签 / 属性 四页签
- **搜索**：FTS 全文搜索、快速切换器、命令面板
- **WebDAV 同步**：manifest 协议、冲突副本、同步状态
- **响应式布局**：手机/折叠屏/平板三形态，600vp / 900vp 双断点
- **最近访问**：按打开时间排序的最近笔记面板

详细设计决策与开发状态见 `doc/DEVELOPMENT.md`；AI 协作规范见 `AGENTS.md`。
