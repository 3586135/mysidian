# AGENTS.md — AI 协作指南

本文档面向 AI 编码助手（及新成员），说明本项目的构建/验证工作流、代码规范与已知坑。项目概览见 `README.md`，开发状态见 `doc/DEVELOPMENT.md`。

## 构建与验证命令

```powershell
devecocli build                          # 构建（权威验证；成功才算完成）
devecocli check arkts <.ets 文件列表>      # 静态检查，build 前跑一次（非替代）
devecocli run --skip-build               # 装机运行（必须先 build 成功）
```

- `devecocli check arkts` 对 `"app.string.xxx"` 资源引用会报 "Unknown resource name" —— **已知误报**，以 `devecocli build` 为权威。
- 若 `C:\Users\song\.local\bin\deveco.exe` 被 Device Guard / WDAC 拦截（报 "blocked by your organization's Device Guard policy"），复制到 `C:\Users\song\AppData\Local\Temp\deveco\` 再以 `deveco2.exe __devecocli-proxy -- build` 调用。
- 单元测试位于 `features/markdown/src/test/LocalUnit.test.ets`（等），CLI 无 test 命令，只能在 DevEco Studio 内运行。

### 签名配置（不入库）

- git 跟踪的 `build-profile.json5` 的 `signingConfigs` 为空（签名材料不上传）。
- 本地 `build-profile.json5` 含签名材料，已设 `git update-index --skip-worktree` 隔离（`git ls-files -v` 显示 `S`）；签名版备份在 `build-profile.signed.json5`（已 gitignore）。
- 新克隆/换机后：复制 `build-profile.signed.json5` 覆盖 `build-profile.json5` 并重设 skip-worktree；或在 DevEco Studio（File → Project Structure → Signing Configs）重新自动签名。
- 无签名配置时 `devecocli build` 只产出 `default-default-unsigned.hap`（无法装机），必须带签名材料构建。

### 发布约定

- 发布新版本时，GitHub Release 上传**未签名**安装包（`default-default-unsigned.hap`，重命名为 `mysidian-x.y.z-unsigned.hap`），不再上传 signed hap（v0.2.0 是最后一个附带签名包的版本）。
- 创建 Release 走 GitHub REST API：`git credential fill`（输入需 LF 文件重定向，PowerShell 管道 CRLF 会报错）取 token；body 用 `[System.IO.File]::ReadAllText` 读入（PS 5.1 的 `Get-Content` 字符串带 PSPath 属性导致 422）。

## 测试设备环境

| 设备 | 连接 | 说明 |
|---|---|---|
| Mate X7 折叠屏模拟器 | `127.0.0.1:5555` | 2210x2416，展开 ~650vp（中等宽 600-900vp 区间的代表机型） |
| MatePad Pro 13 平板模拟器 | `127.0.0.1:5557` | 2880x1920，宽屏固定面板形态 |
| Mate 90 Pro 手机模拟器 | `127.0.0.1:5559` | 1280x2832，窄屏形态 |
| 真机（无线调试） | `192.168.3.149:42073` | 端口可能变化；`hdc tconn <ip:port>` 重连 |

- 启动应用：`hdc -t <dev> shell aa start -a DefaultAbility -b com.mrs.mysidian`（**没有** EntryAbility，用错报 10104001）。
- 多设备在线时 devecocli 子命令必须带 `--device`。
- 用户要求：**UI 功能验证尽量在三台模拟器上都做**。

### UI 自动化要点（devecocli ui）

- `ui layout --format json` 输出 a11y 树（数组，节点含 bounds[l,t,r,b]/text/clickable），用 PowerShell `ConvertFrom-Json` 解析定位坐标。
- `ui screenshot --path <目录或.png>`：路径必须是**已存在目录或 .png 文件**（.jpeg 后缀会报错）。
- `ui text <str>`：**不支持换行**（原始 LF 会拆参、字面 `\n` 按字面输入、uinput -K -t 拒绝 LF）；以 `-` 开头的文本需 `--` 分隔；输入前先点击目标输入框聚焦。
- TextArea 无法通过键值（2046/28）输入换行；多行文本编辑建议用 hdc 沙箱直推文件（仅模拟器）。
- 主模型无视觉能力时，用 `recognize_ui_components` 工具分析截图（它不返回精确像素坐标，需 a11y dump 配合）。

### 模拟器专属技巧（userdebug）

- 可直接访问应用沙箱：`hdc shell ls /data/app/el2/100/base/com.mrs.mysidian/haps/default/files/vaults/<id>_<name>/`；**真机不行**。
- 测试数据注入：`hdc file send 本地.md 沙箱内已有笔记路径` 覆盖内容 → `aa force-stop` → 重启应用。必须**覆盖 DB 中已登记的笔记**，新文件不会被索引。
- 真机锁屏自动解锁：power-shell wakeup + setmode 602 → 双击屏重试人脸 → 上滑。

## 代码规范（ArkTS 严格模式）

- 禁 `any`/`unknown`/`as` 断言（`JSON.parse` 后 cast 一次到命名 raw 模型除外）、禁索引签名（用 `Record<K,V>`）、禁解构、禁 `obj[key]` 动态取值、禁 `var`/`require`/动态 import。
- 对象字面量必须有显式类型上下文（类型化变量/参数/interface）。
- 状态管理按 struct 分代，**V1/V2 不得混用**：
  - V1 `@Component`：`@State/@Prop/@Link/@Provide/@Consume/@Observed+@ObjectLink` 等
  - V2 `@ComponentV2`：`@Local/@Param/@Once/@Event/@Provider/@Consumer/@Computed/@Monitor`，类装饰器 `@ObservedV2`+`@Trace`
- `build()` 与 `@Builder` 内只能放 UI 语法（属性值内三元可用，语句级 if/switch 禁止）；本地声明提升到文件作用域。
- 生命周期钩子（aboutToAppear 等）不得 private；V1 struct 不定义 getter 访问器。
- `@Param` 命名避开组件属性名（width/height/size 等）；跨文件引用必须 export，import 形式与 export 形式匹配。
- 深层状态突变不触发 V2 浅观察：用"突变 + 数组 slice()"或 key 含变化字段的 ForEach 强制重建。
- 动画统一 `Curve.Friction`；`hilog` 记日志（`@kit.PerformanceAnalysisKit`）；`BusinessError` 仅从 `@kit.BasicServicesKit` 导入。
- 深浅色双模式：颜色一律走 `app.color.*` 资源，禁止硬编码。

## 编辑文件注意

- **严禁用 PowerShell Set-Content/Out-File 重写含中文的源码/资源文件**（编码会破坏），必须用专用编辑工具。
- 中文资源统一在 `products/default/src/main/resources/base/element/string.json`；模块级资源在各自模块 resources 下。
- 需要新权限时在 `module.json5` 声明（user_grant 需 reason + usedScene）。

## 里程碑与当前状态

git 历史以 M0-M6 里程碑推进（见 `git log`）；近期开发（未提交部分）见 `doc/DEVELOPMENT.md` 的"近期变更"。完成功能后应主动询问用户是否提交。
