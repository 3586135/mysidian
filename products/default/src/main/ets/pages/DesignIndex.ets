import { curves, KeyboardAvoidMode, mediaquery, promptAction, router, window } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SyncState, TagRef } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { SettingsSheet, SettingsSheetMode } from '../view/design/SettingsSheet';
import { SyncSettingsSheet } from '../view/design/SyncSettingsSheet';
import { VaultManagerSheet } from '../view/design/VaultManagerSheet';
import { TreeItemMenuSheet } from '../view/design/TreeItemMenuSheet';
import {
  confirmTrashFolderAction,
  confirmTrashNoteAction,
  ItemLongPressModifier,
  noteTitleFromPath as resolveNoteTitle,
  ThreeDotsIcon
} from '../view/design/NoteActionHelper';
import { WorkspaceView, DesignViewMode, WorkspaceBackSignal } from '../view/design/WorkspaceView';
import { CreateVaultRequest, DesignDialogKind, DialogHost } from '../view/design/DialogHost';
import { GraphLayout, GraphLayoutStats } from '../viewmodel/GraphLayout';
import { DesignPalette } from '../viewmodel/DesignPalette';
import { SearchViewModel } from '../viewmodel/SearchViewModel';
import { SyncViewModel } from '../viewmodel/SyncViewModel';
import { RecentNoteItem, RootFolderSummary, VaultViewModel } from '../viewmodel/VaultViewModel';
import { AbilityContextHolder } from '../defaultability/AbilityContextHolder';

const LOG: Logger = new Logger('DesignIndex');

// ===== Material 3 悬浮分离式胶囊底栏尺寸常量（vp） =====
const BAR_SIDE_VP: number = 16;               // 底栏左右外边距
const BAR_BOTTOM_VP: number = 16;             // 底栏距屏幕底部
const CAPSULE_HEIGHT_VP: number = 64;         // 左侧胶囊高度
const FAB_SIZE_VP: number = 64;               // 右侧 FAB 边长
const BAR_GAP_VP: number = 12;                // 胶囊与 FAB 间距
const SLIDER_WIDTH_VP: number = 76;           // 滑块指示器宽度（适配三页签底栏）
const SLIDER_HEIGHT_VP: number = 54;          // 滑块指示器高度
const SLIDER_RADIUS_VP: number = 27;          // 滑块指示器圆角
const GRAPH_CANVAS_HEIGHT_VP: number = 340;   // 图谱画布高度
const GRAPH_MAX_SCALE: number = 16;            // 图谱双指缩放上限倍数（足够把最密的簇完全展开）
const GRAPH_ZOOM_STEP: number = 1.3;          // 缩放按钮单步倍率
const GRAPH_PINCH_COOLDOWN_MS: number = 300;  // 捏合结束后抑制误触点击的窗口期
const DOUBLE_PI: number = Math.PI * 2;
const SEARCH_DEBOUNCE_MS: number = 250;       // 搜索防抖时长
const TINT_BG_PALETTE: Resource[] = [
  $r('app.color.design_tint_sage_bg'),
  $r('app.color.design_tint_ochre_bg'),
  $r('app.color.design_tint_rose_bg'),
  $r('app.color.design_tint_violet_bg'),
  $r('app.color.design_tint_sky_bg')
];
const TINT_PILL_PALETTE: Resource[] = [
  $r('app.color.design_tint_sage_pill'),
  $r('app.color.design_tint_ochre_pill'),
  $r('app.color.design_tint_rose_pill'),
  $r('app.color.design_tint_violet_pill'),
  $r('app.color.design_tint_sky_pill')
];
const TINT_FG_PALETTE: Resource[] = [
  $r('app.color.design_tint_sage_fg'),
  $r('app.color.design_tint_ochre_fg'),
  $r('app.color.design_tint_rose_fg'),
  $r('app.color.design_tint_violet_fg'),
  $r('app.color.design_tint_sky_fg')
];

// ===== 页签定义 =====
class DesignTabDef {
  keyId: string;
  label: Resource;
  symbol: Resource;

  constructor(keyId: string, label: Resource, symbol: Resource) {
    this.keyId = keyId;
    this.label = label;
    this.symbol = symbol;
  }
}

// ===== 搜索页：模式 chips（0 全文 / 1 标签 / 2 属性） =====
class DesignModeChip {
  keyId: string;
  label: Resource;
  mode: number;

  constructor(keyId: string, label: Resource, mode: number) {
    this.keyId = keyId;
    this.label = label;
    this.mode = mode;
  }
}

// ===== 搜索页：命中结果（头/命中/尾 三段高亮拼接） =====
class DesignSearchRow {
  keyId: string;
  path: string;
  titleHead: string;
  titleHit: string;
  titleTail: string;
  bodyHead: string;
  bodyHit: string;
  bodyTail: string;

  constructor(keyId: string, path: string, titleHead: string, titleHit: string, titleTail: string,
    bodyHead: string, bodyHit: string, bodyTail: string) {
    this.keyId = keyId;
    this.path = path;
    this.titleHead = titleHead;
    this.titleHit = titleHit;
    this.titleTail = titleTail;
    this.bodyHead = bodyHead;
    this.bodyHit = bodyHit;
    this.bodyTail = bodyTail;
  }
}

// ===== 图谱页：换算为 vp 后的节点（命中测试/画布绘制用） =====
class DesignGraphNodeVp {
  keyId: string;
  x: number;
  y: number;
  radiusVp: number;
  label: string;
  isRoot: boolean;
  /** 连线度数（标签按度数分级披露，只标注枢纽节点）。 */
  degree: number;
  /** 截断后的短标签（首帧 measureText 计算后缓存，避免逐帧测量）。 */
  shortLabel: string = '';

  constructor(keyId: string, x: number, y: number, radiusVp: number, label: string,
    isRoot: boolean, degree: number) {
    this.keyId = keyId;
    this.x = x;
    this.y = y;
    this.radiusVp = radiusVp;
    this.label = label;
    this.isRoot = isRoot;
    this.degree = degree;
  }
}

/** 图谱边（端点直接持有节点引用，绘制免查表）。 */
class DesignGraphEdgeVp {
  fromNode: DesignGraphNodeVp;
  toNode: DesignGraphNodeVp;

  constructor(fromNode: DesignGraphNodeVp, toNode: DesignGraphNodeVp) {
    this.fromNode = fromNode;
    this.toNode = toNode;
  }
}

// ===== 更多页：入口（宫格 + 列表通用） =====
class DesignMoreEntry {
  keyId: string;
  title: Resource;
  sub: ResourceStr;
  symbol: Resource;

  constructor(keyId: string, title: Resource, sub: ResourceStr, symbol: Resource) {
    this.keyId = keyId;
    this.title = title;
    this.sub = sub;
    this.symbol = symbol;
  }
}

// ===== FAB 长按气泡菜单动作 =====
class DesignBubbleAction {
  keyId: string;
  label: Resource;
  symbol: Resource;

  constructor(keyId: string, label: Resource, symbol: Resource) {
    this.keyId = keyId;
    this.label = label;
    this.symbol = symbol;
  }
}

// ===== 快速笔记编辑器：语法插入 chips =====
class DesignInsertChip {
  keyId: string;
  label: Resource;
  symbol: Resource;
  insertText: string;

  constructor(keyId: string, label: Resource, symbol: Resource, insertText: string) {
    this.keyId = keyId;
    this.label = label;
    this.symbol = symbol;
    this.insertText = insertText;
  }
}

/** 按关键词把文本拆为「头/命中/尾」三段（未命中时命中段为空串）。 */
function splitHighlight(source: string, keyword: string): string[] {
  const parts: string[] = [source, '', ''];
  const kw: string = keyword.trim();
  if (kw.length === 0 || source.length === 0) {
    return parts;
  }
  const index: number = source.toLowerCase().indexOf(kw.toLowerCase());
  if (index < 0) {
    return parts;
  }
  parts[0] = source.substring(0, index);
  parts[1] = source.substring(index, index + kw.length);
  parts[2] = source.substring(index + kw.length);
  return parts;
}

/** 最近访问的相对时间文案。 */
function formatRelativeTime(openedAt: number): ResourceStr {
  if (openedAt <= 0) {
    return '';
  }
  const diffMs: number = Date.now() - openedAt;
  const minuteMs: number = 60 * 1000;
  const hourMs: number = 60 * minuteMs;
  const dayMs: number = 24 * hourMs;
  if (diffMs < minuteMs) {
    return $r('app.string.design_time_now');
  }
  if (diffMs < hourMs) {
    return $r('app.string.design_time_min', Math.floor(diffMs / minuteMs));
  }
  if (diffMs < dayMs) {
    return $r('app.string.design_time_hour', Math.floor(diffMs / hourMs));
  }
  if (diffMs < 2 * dayMs) {
    return $r('app.string.design_time_yesterday');
  }
  const date: Date = new Date(openedAt);
  const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
  return `${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/**
 * Material 3 设计首页：Espresso 深色主题、悬浮分离式胶囊底部栏。
 *
 * 单页架构：本页为唯一 @Entry，四页签首页（文件/搜索/图谱/更多）与
 * 工作台（WorkspaceView）通过 viewMode 状态机在页内切换，无 router 跳转。
 * 键盘避让、窗口订阅与自动同步定时器等 @Entry 级生命周期统一归本页管理。
 */
@Entry
@ComponentV2
struct DesignIndex {
  // ===== 视图模型 =====
  @Local vm: VaultViewModel = new VaultViewModel();
  @Local searchVm: SearchViewModel = new SearchViewModel();
  @Local syncVm: SyncViewModel = new SyncViewModel();

  // ===== 交互状态 =====
  @Local currentTabIndex: number = 0;      // 当前页签
  @Local swipeOffsetVp: number = 0;        // 手势滑动跟手偏移（vp，滑向下一页为负）
  @Local indicatorScale: number = 1;       // 滑块指示器缩放（跟手时轻微收缩）
  @Local capsuleWidthVp: number = 0;       // 胶囊实际宽度（滑块定位基准）
  @Local swiperWidthVp: number = 0;        // Swiper 实际宽度（偏移换算基准）
  @Local topInset: number = 0;             // 状态栏避让高度（vp）
  @Local bottomInset: number = 0;          // 导航条避让高度（vp）
  @Local filesCollapsed: boolean = false;  // 文件页：目录区收起
  @Local filesSegment: number = 0;         // 文件页分段：0 书架 / 1 书签 / 2 时间轴 / 3 目录
  @Local currentFolderPath: string = '';   // 文件页：当前目录穿透浏览路径（'' 为根目录）
  @Local filesGridMode: boolean = false;   // 文件页视图模式：false 素雅列表视图 / true 书架封面宫格
  @Local searchKeyword: string = '';       // 搜索页：关键词
  @Local searchRows: DesignSearchRow[] = [];// 搜索页：命中结果（含高亮分段）
  @Local selectedGraphPath: string = '';   // 图谱页：选中节点路径（默认当前笔记）
  @Local graphCanvasWidthVp: number = 0;   // 图谱画布实际宽度
  @Local graphCanvasHeightVp: number = GRAPH_CANVAS_HEIGHT_VP; // 图谱画布高度（随节点数自适应）
  @Local graphClusterCount: number = 0;    // 图谱页：链接群簇数（洞见行）
  @Local graphOrphanCount: number = 0;     // 图谱页：未链接笔记数（洞见行）
  private graphNodeVpList: DesignGraphNodeVp[] = []; // 图谱节点 vp 坐标（命中测试/绘制用）
  private graphEdgeVpList: DesignGraphEdgeVp[] = []; // 图谱边端点引用（绘制用，避免逐帧 Map 查找）
  private graphNeighbors: Map<string, Set<string>> = new Map<string, Set<string>>(); // 邻接表（聚焦暗化）
  private graphScale: number = 1;             // 图谱缩放倍数（双指捏合 / 按钮）
  private graphOffsetXVp: number = 0;         // 图谱平移偏移 x（vp）
  private graphOffsetYVp: number = 0;         // 图谱平移偏移 y（vp）
  @Local showFabMenu: boolean = false;     // FAB 长按气泡菜单
  @Local showQuickEditor: boolean = false; // 快速笔记半模态
  @Local fabLongPressConsumed: boolean = false; // 长按已消费标志（防误触发 click）
  @Local draftTitle: string = '';          // 快速笔记草稿标题
  @Local draftBody: string = '';           // 快速笔记草稿正文
  @Local showSyncPanel: boolean = false;   // 同步设置浮层（全局，首页/工作台共用）
  @Local settingsSheetMode: number = SettingsSheetMode.NONE; // 外观与维护浮层模式（-1 关闭 / 0 外观与阅读 / 1 备份与维护）
  @Local showVaultManager: boolean = false; // 仓库管理浮层（全局，首页/工作台共用）
  @Local homeMenuPath: string = '';        // 首页长按/更多操作菜单目标路径
  @Local homeMenuIsDir: boolean = false;   // 首页操作菜单目标是否目录
  @Local homeDialogKind: string = DesignDialogKind.NONE; // 首页重命名/新建子目录/移动对话框
  @Local homeDialogTargetPath: string = ''; // 首页对话框目标笔记路径
  @Local viewMode: number = DesignViewMode.HOME; // 页面状态机：0 首页 / 1 工作台
  @Local showCreateVaultDialog: boolean = false; // 新建仓库对话框
  private pendingExternalImport: boolean = false; // 建库完成后自动导入外部预览文件
  private pendingExternalEditAfter: boolean = false; // 导入后是否立即进入编辑态
  @Local keyboardHeight: number = 0;       // 键盘高度（vp，NONE 避让下让位）
  @Local editorKeyboardMode: boolean = false; // 编辑区键盘交互态（切换 NONE 避让）
  @Local isWide: boolean = false;          // 宽屏形态（键盘避让策略依据）

  // ===== 控制器与画布上下文 =====
  private swiperController: SwiperController = new SwiperController();
  // 工作台返回首页重建 Swiper 时的初始页签（避免每次滑动联动重置动画）
  private homeInitialTabIndex: number = 0;
  private filesScroller: Scroller = new Scroller();
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private graphNodeMap: Map<string, DesignGraphNodeVp> = new Map<string, DesignGraphNodeVp>();
  private graphPrevPinchDist: number = 0;    // 捏合基线：双指间距（vp）
  private graphPrevMidXVp: number = 0;       // 捏合基线：双指中点 x（vp）
  private graphPrevMidYVp: number = 0;       // 捏合基线：双指中点 y（vp）
  private graphPinchEndTime: number = 0;     // 最近一次捏合结束时刻（抑制误触点击）
  private graphPageScroller: Scroller = new Scroller(); // 图谱页滚动控制器（单指拖动回落为页面滚动）
  private graphInteracting: boolean = false; // 交互进行中（捏合/单指平移）：快速重绘省略标签
  private graphLastDrawMs: number = 0;       // 最近一次绘制时间戳（节流：一帧最多画一次）
  private graphPanBaseXVp: number = 0;       // 单指平移手势起点：图谱偏移 x
  private graphPanBaseYVp: number = 0;       // 单指平移手势起点：图谱偏移 y
  private graphPanLastYVp: number = 0;       // 未缩放回落页面滚动：上次累计 y
  private searchDebounceId: number = -1;
  private itemLongPressConsumed: boolean = false; // 列表/卡片长按释放防误触打开
  private itemLongPressTimer: number = -1;
  private initReady: boolean = false;            // 视图模型初始化完成
  private syncReady: boolean = false;            // 同步配置初始化完成
  private darkModeListener: mediaquery.MediaQueryListener | null = null; // 深浅色切换监听（Canvas 重绘）
  /** 主窗口：用于订阅键盘高度变化。 */
  private mainWindow: window.Window | undefined = undefined;
  /** 键盘高度变化回调（单位 px）。 */
  private keyboardCallback: (height: number) => void = (height: number): void => {
    this.keyboardHeight = this.getUIContext().px2vp(height);
    // 键盘高度变化后重新评估避让策略（含收起时恢复 RESIZE）。
    this.applyKeyboardAvoidMode();
  };
  /** 自动同步周期定时器句柄。 */
  private autoSyncTimer: number = -1;
  /** 工作台返回键信号（onBackPress → WorkspaceView 返回链）。 */
  private workspaceBackSignal: WorkspaceBackSignal = new WorkspaceBackSignal();
  /** 本次进入工作台携带的启动动作（如 templates，退出时复位）。 */
  private workspaceLaunchAction: string = '';
  /** 自动同步后台巡检周期（10 分钟）。 */
  private static readonly AUTO_SYNC_INTERVAL_MS: number = 10 * 60 * 1000;

  // ===== 静态定义（图谱页签当前隐藏，代码完整保留供后续按需开启） =====
  readonly tabDefs: DesignTabDef[] = [
    new DesignTabDef('t_files', $r('app.string.design_tab_files'), $r('sys.symbol.doc_plaintext')),
    new DesignTabDef('t_search', $r('app.string.design_tab_search'), $r('sys.symbol.magnifyingglass')),
    new DesignTabDef('t_more', $r('app.string.design_tab_more'), $r('sys.symbol.more'))
  ];

  readonly modeChips: DesignModeChip[] = [
    new DesignModeChip('m_full', $r('app.string.design_search_mode_full'), 0),
    new DesignModeChip('m_tag', $r('app.string.design_search_mode_tag'), 1),
    new DesignModeChip('m_prop', $r('app.string.design_search_mode_prop'), 2)
  ];


  readonly bubbleActions: DesignBubbleAction[] = [
    new DesignBubbleAction('bubble_daily', $r('app.string.design_fab_daily'), $r('sys.symbol.calendar')),
    new DesignBubbleAction('bubble_note', $r('app.string.design_fab_new_note'), $r('sys.symbol.square_and_pencil')),
    new DesignBubbleAction('bubble_template', $r('app.string.design_fab_template'), $r('sys.symbol.doc_text_on_doc_text'))
  ];

  readonly insertChips: DesignInsertChip[] = [
    new DesignInsertChip('i_title', $r('app.string.design_editor_insert_title'), $r('sys.symbol.hash'), '\n## '),
    new DesignInsertChip('i_wikilink', $r('app.string.design_editor_insert_wikilink'), $r('sys.symbol.square_and_pencil'), '[[]]'),
    new DesignInsertChip('i_todo', $r('app.string.design_editor_insert_todo'), $r('sys.symbol.checkmark_circle'), '- [ ] ')
  ];

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      LOG.error('host context is unavailable');
      return;
    }
    this.loadWindowInsets();
    this.searchVm.setContext(context);
    this.vm.attachUi(this.getUIContext());
    this.syncVm.init(context).then((): void => {
      this.syncReady = true;
      this.restartAutoSyncTimer();
      this.maybeTriggerLaunchSync();
    });
    // 同步拉取了新文件后重建索引并刷新文件树，使新笔记可见。
    this.syncVm.onSyncComplete = (): void => {
      this.vm.rescanVault().catch((error: BusinessError): void => {
        LOG.error(`rescan vault after sync failed: ${error.message}`);
      });
    };
    this.syncVm.onNeedsConfirm = (): void => {
      this.showSyncSafetyConfirmDialog();
    };
    this.vm.init(context).then((): void => {
      this.initReady = true;
      this.handleLaunchParams();
      this.consumeShortcutAction();
      this.consumePendingOpenUri();
      this.maybeTriggerLaunchSync();
      this.vm.loadVaultGraph().then((): void => {
        this.rebuildGraphLayout();
      });
    });
    AbilityContextHolder.onShortcutAction = (): void => {
      if (this.initReady) {
        this.consumeShortcutAction();
      }
    };
    AbilityContextHolder.onOpenUri = (): void => {
      if (this.initReady) {
        this.consumePendingOpenUri();
      }
    };
    AbilityContextHolder.onForeground = (): void => {
      if (this.initReady && this.syncReady) {
        this.syncVm.requestPassiveSync(this.vm.currentVault);
      }
    };
    // 深浅色切换：Canvas 色值需按新模式重绘
    this.darkModeListener = this.getUIContext().getMediaQuery().matchMediaSync('(dark-mode: true)');
    this.darkModeListener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.rebuildGraphLayout();
    });
  }

  onPageShow(): void {
    if (this.initReady) {
      this.consumeShortcutAction();
      this.consumePendingOpenUri();
    }
  }

  aboutToDisappear(): void {
    AbilityContextHolder.onShortcutAction = null;
    AbilityContextHolder.onOpenUri = null;
    AbilityContextHolder.onForeground = null;
    this.stopAutoSyncTimer();
    this.syncVm.disposeTimers();
    if (this.itemLongPressTimer >= 0) {
      clearTimeout(this.itemLongPressTimer);
      this.itemLongPressTimer = -1;
    }
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('keyboardHeightChange', this.keyboardCallback);
      this.mainWindow = undefined;
    }
    if (this.darkModeListener !== null) {
      this.darkModeListener.off('change');
      this.darkModeListener = null;
    }
  }

  /** 记录上一次观测的仓库 ID（区分真实切换仓库与同仓库重扫）。 */
  private lastObservedVaultId: number = -1;

  /** 切换仓库后清空首页目录穿透路径，同仓库刷新则保留当前浏览位置。 */
  @Monitor('vm.currentVault')
  onCurrentVaultChanged(): void {
    const nextId: number = this.vm.currentVault.id;
    if (this.lastObservedVaultId >= 0 && nextId !== this.lastObservedVaultId) {
      this.currentFolderPath = '';
      this.homeMenuPath = '';
      this.homeDialogKind = DesignDialogKind.NONE;
      this.homeDialogTargetPath = '';
      this.itemLongPressConsumed = false;
    }
    this.lastObservedVaultId = nextId;
  }

  /** 系统返回键：工作台 → 信号下发工作台返回链；首页 → 依次关闭浮层 → 退出子目录 → 默认退出。 */
  onBackPress(): boolean {
    if (this.homeDialogKind !== DesignDialogKind.NONE) {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
        this.homeDialogKind = DesignDialogKind.NONE;
        this.homeDialogTargetPath = '';
      });
      return true;
    }
    if (this.homeMenuPath.length > 0) {
      this.itemLongPressConsumed = false;
      this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
        this.homeMenuPath = '';
      });
      return true;
    }
    // 全局浮层优先（首页 / 工作台两模式均可出现）。
    if (this.showCreateVaultDialog) {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.showCreateVaultDialog = false;
      });
      return true;
    }
    if (this.showVaultManager) {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.showVaultManager = false;
      });
      return true;
    }
    if (this.showSyncPanel) {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.showSyncPanel = false;
      });
      return true;
    }
    if (this.settingsSheetMode !== SettingsSheetMode.NONE) {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.settingsSheetMode = SettingsSheetMode.NONE;
      });
      return true;
    }
    if (this.viewMode === DesignViewMode.WORKSPACE) {
      this.workspaceBackSignal.request();
      return true;
    }
    if (this.showFabMenu) {
      this.toggleFabMenu();
      return true;
    }
    if (this.showQuickEditor) {
      this.closeQuickEditor();
      return true;
    }
    if (this.currentTabIndex === 0 && this.currentFolderPath.length > 0 &&
      (this.filesSegment === 0 || this.filesSegment === 3)) {
      this.navigateFolderUp();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.viewMode === DesignViewMode.HOME) {
        this.homeContent()
      } else {
        WorkspaceView({
          vm: this.vm,
          searchVm: this.searchVm,
          keyboardHeight: this.keyboardHeight,
          isWide: this.isWide,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          backSignal: this.workspaceBackSignal,
          launchAction: this.workspaceLaunchAction,
          syncConfigured: this.syncVm.configured,
          onRequestExit: (): void => {
            this.exitWorkspace();
          },
          onEditorKeyboardMode: (active: boolean): void => {
            this.setEditorKeyboardMode(active);
          },
          onOpenTag: (tag: string): void => {
            this.exitWorkspace();
            this.openWorkspaceTagSearch(tag);
          },
          onNoteMutated: (): void => {
            this.syncNowIfAuto();
          },
          onRequestCreateVault: (request: CreateVaultRequest): void => {
            this.createVaultFromDialog(request);
          },
          onRequestSync: (): void => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
              this.showSyncPanel = true;
            });
          },
          onRequestImportExternal: (editAfter: boolean): void => {
            this.handleImportExternalRequest(editAfter);
          },
          onRequestCloseExternal: (): void => {
            this.closeExternalPreview();
          }
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.Friction }))
      }

      // ===== 全局浮层（首页 / 工作台两模式共用）=====

      // 新建仓库对话框（含 WebDAV 同步配置）
      if (this.showCreateVaultDialog) {
        DialogHost({
          kind: DesignDialogKind.CREATE_VAULT,
          vm: this.vm,
          onClose: (): void => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
              this.showCreateVaultDialog = false;
            });
          },
          onCreateVault: (request: CreateVaultRequest): void => {
            this.createVaultFromDialog(request);
          }
        })
      }

      // 同步设置浮层
      if (this.showSyncPanel) {
        SyncSettingsSheet({
          syncVm: this.syncVm,
          vault: this.vm.currentVault,
          onImportCert: (): void => {
            this.pickCertFile();
          },
          onAutoSyncChange: (value: boolean): void => {
            this.syncVm.autoSync = value;
            this.restartAutoSyncTimer();
          },
          onSyncNow: (): void => {
            this.syncVm.runSync(this.vm.currentVault, false, true);
          },
          onClose: (): void => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
              this.showSyncPanel = false;
            });
          }
        })
      }

      // 外观与维护浮层（外观与阅读 / 备份与维护）
      if (this.settingsSheetMode !== SettingsSheetMode.NONE) {
        SettingsSheet({
          vm: this.vm,
          mode: this.settingsSheetMode,
          onClose: (): void => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
              this.settingsSheetMode = SettingsSheetMode.NONE;
            });
          }
        })
      }

      // 仓库管理浮层
      if (this.showVaultManager) {
        VaultManagerSheet({
          vm: this.vm,
          onCreateVault: (): void => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
              this.showVaultManager = false;
              this.showCreateVaultDialog = true;
            });
          },
          onClose: (): void => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
              this.showVaultManager = false;
            });
          }
        })
      }

      // 首页条目操作菜单（长按卡片 / 点按右侧更多入口）
      if (this.homeMenuPath.length > 0) {
        TreeItemMenuSheet({
          targetPath: this.homeMenuPath,
          isDir: this.homeMenuIsDir,
          bookmarked: this.vm.isBookmarked(this.homeMenuPath),
          showSplit: this.isWide && this.vm.selectedPath.length > 0 && this.vm.selectedPath !== this.homeMenuPath,
          showOpenFolder: true,
          onClose: (): void => {
            this.itemLongPressConsumed = false;
            this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
              this.homeMenuPath = '';
            });
          },
          onOpenFolder: (folder: string): void => {
            this.enterFolder(folder);
          },
          onNewNoteInFolder: (folder: string): void => {
            this.vm.createNote(folder).then((): void => {
              this.onHomeNoteMutated();
              this.openWorkspace({});
            });
          },
          onNewSubfolder: (folder: string): void => {
            this.vm.pendingFolderPrefix = `${folder}/`;
            this.openHomeDialog(DesignDialogKind.NEW_FOLDER, '');
          },
          onTrashFolder: (folder: string): void => {
            this.confirmTrashHomeFolder(folder);
          },
          onOpenNote: (path: string): void => {
            this.openWorkspace({ 'openPath': path });
          },
          onSplitOpen: (path: string): void => {
            this.vm.openSecondary(path).then((): void => {
              this.openWorkspace({});
            });
          },
          onToggleBookmark: (path: string): void => {
            this.vm.toggleBookmark(path).then((added: boolean): void => {
              this.toast(added ? $r('app.string.msg_bookmark_added') : $r('app.string.msg_bookmark_removed'));
            });
          },
          onRenameNote: (path: string): void => {
            this.openHomeDialog(DesignDialogKind.RENAME, path);
          },
          onMoveNote: (path: string): void => {
            this.openHomeDialog(DesignDialogKind.MOVE, path);
          },
          onTrashNote: (path: string): void => {
            this.confirmTrashHomeNote(path);
          }
        })
      }

      // 首页重命名 / 新建子文件夹 / 移动对话框
      if (this.homeDialogKind !== DesignDialogKind.NONE) {
        DialogHost({
          kind: this.homeDialogKind,
          targetPath: this.homeDialogTargetPath,
          vm: this.vm,
          onClose: (): void => {
            this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
              this.homeDialogKind = DesignDialogKind.NONE;
              this.homeDialogTargetPath = '';
            });
          },
          onNoteMutated: (): void => {
            this.onHomeNoteMutated();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.design_bg'))
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // 布局形态变化后重新评估键盘避让策略（宽屏无底部悬浮导航栏）。
      const wide: boolean = Number(newArea.width) >= 600;
      if (wide !== this.isWide) {
        this.isWide = wide;
        this.applyKeyboardAvoidMode();
      }
    })
  }

  /** 首页内容：三页签横滑（图谱页已隐藏但保留实现） + 悬浮毛玻璃底栏 + 各浮层。 */
  @Builder
  homeContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 内容区：笔记 / 搜索 / 更多 三个页面横滑
      Swiper(this.swiperController) {
        this.filesPage()
        this.searchPage()
        this.morePage()
      }
      .index(this.homeInitialTabIndex)
      .width('100%')
      .height('100%')
      .indicator(false)
      .loop(false)
      .onGestureSwipe((_index: number, extraInfo: SwiperAnimationEvent) => {
        // 手势滑动：滑块实时跟手并轻微收缩
        this.swipeOffsetVp = extraInfo.currentOffset;
        this.indicatorScale = 0.92;
      })
      .onAnimationStart((_index: number, targetIndex: number, _extraInfo: SwiperAnimationEvent) => {
        // 松手/点击页签：滑块弹性归位
        this.springIndicatorTo(targetIndex);
      })
      .onChange((index: number) => {
        if (index !== this.currentTabIndex) {
          this.springIndicatorTo(index);
        }
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.swiperWidthVp = Number(newArea.width);
      })

      // 底部悬浮分离式毛玻璃胶囊 + 毛玻璃 FAB
      this.bottomBar()

      // FAB 长按气泡菜单（含遮罩）
      if (this.showFabMenu) {
        this.overlayScrim(() => {
          this.toggleFabMenu();
        })
        this.fabMenuOverlay()
      }

      // 快速笔记半模态（含遮罩）
      if (this.showQuickEditor) {
        this.overlayScrim(() => {
          this.closeQuickEditor();
        })
        this.editorSheet()
      }
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.Friction }))
  }

  // ==================== 底部悬浮毛玻璃栏 ====================

  @Builder
  bottomBar() {
    Row({ space: BAR_GAP_VP }) {
      // 左：胶囊导航（透明毛玻璃模糊 + 半透明玻璃滑块指示器）
      Stack() {
        // 滑块指示器：跟随手势偏移，松手弹性归位
        Stack() {
        }
        .width(SLIDER_WIDTH_VP)
        .height(SLIDER_HEIGHT_VP)
        .borderRadius(SLIDER_RADIUS_VP)
        .backgroundColor($r('app.color.design_glass_pill'))
        .border({ width: 1, color: $r('app.color.design_glass_stroke') })
        .position({ x: this.sliderXVp, y: (CAPSULE_HEIGHT_VP - SLIDER_HEIGHT_VP) / 2 })
        .scale({ x: this.indicatorScale, y: this.indicatorScale })

        // 页签单元
        Row() {
          ForEach(this.tabDefs, (tab: DesignTabDef, index: number) => {
            Column({ space: 2 }) {
              SymbolGlyph(tab.symbol)
                .fontSize(22)
                .fontColor([index === this.currentTabIndex ?
                  $r('app.color.design_text_primary') : $r('app.color.design_text_secondary')])
              Text(tab.label)
                .fontSize(10)
                .fontWeight(index === this.currentTabIndex ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(index === this.currentTabIndex ?
                  $r('app.color.design_text_primary') : $r('app.color.design_text_secondary'))
            }
            .justifyContent(FlexAlign.Center)
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.changeTab(index);
            })
          }, (tab: DesignTabDef) => tab.keyId)
        }
        .width('100%')
        .height('100%')
      }
      .layoutWeight(1)
      .height(CAPSULE_HEIGHT_VP)
      .backgroundColor($r('app.color.design_glass_bg'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .borderRadius(CAPSULE_HEIGHT_VP / 2)
      .border({ width: 1, color: $r('app.color.design_glass_stroke') })
      .shadow({ radius: 28, color: $r('app.color.design_shadow'), offsetY: 10 })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.capsuleWidthVp = Number(newArea.width);
      })

      // 右：毛玻璃悬浮 FAB（短按快速闪念笔记 / 长按气泡菜单）
      Stack() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(26)
          .fontColor([$r('app.color.design_text_primary')])
      }
      .width(FAB_SIZE_VP)
      .height(FAB_SIZE_VP)
      .borderRadius(FAB_SIZE_VP / 2)
      .backgroundColor($r('app.color.design_glass_bg'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: $r('app.color.design_glass_stroke') })
      .shadow({ radius: 28, color: $r('app.color.design_shadow'), offsetY: 10 })
      .onClick(() => {
        // 长按释放后的 click 由消费标志吞掉
        if (this.fabLongPressConsumed) {
          this.fabLongPressConsumed = false;
          return;
        }
        if (this.showFabMenu) {
          this.toggleFabMenu();
          return;
        }
        if (this.vm.vaults.length === 0) {
          this.openWorkspace({});
          return;
        }
        this.openQuickEditor('');
      })
      .gesture(
        LongPressGesture({ repeat: false, duration: 320 })
          .onAction((_event: GestureEvent) => {
            if (this.showFabMenu) {
              this.toggleFabMenu();
            } else {
              this.fabLongPressConsumed = true;
              this.toggleFabMenu();
            }
          })
      )
    }
    .width('100%')
    .padding({ left: BAR_SIDE_VP, right: BAR_SIDE_VP })
    .margin({ bottom: BAR_BOTTOM_VP + this.bottomInset })
  }

  // ==================== 笔记页 ====================

  @Builder
  filesPage() {
    Stack({ alignContent: Alignment.Top }) {
      // 底层滚动内容区：向上滚动时直接穿过顶栏毛玻璃控件下方，实现实时动态色彩透射模糊
      Scroll(this.filesScroller) {
        Column({ space: 12 }) {
          if (this.vm.vaults.length === 0) {
            this.onboardCard()
          } else if (this.filesSegment === 0) {
            this.shelfSegmentContent()
          } else if (this.filesSegment === 1) {
            this.bookmarkSegmentContent()
          } else if (this.filesSegment === 2) {
            this.timelineSegmentContent()
          } else {
            this.folderSegmentContent()
          }
        }
        .width('100%')
        .padding({
          left: BAR_SIDE_VP,
          right: BAR_SIDE_VP,
          top: this.topInset + (this.vm.vaults.length > 0 ? 108 : 62),
          bottom: CAPSULE_HEIGHT_VP + BAR_BOTTOM_VP + this.bottomInset + 24
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 悬浮顶栏与毛玻璃分段胶囊
      Column({ space: 10 }) {
        // 顶栏：有仓库时显示切换器 + 日记/视图按钮；0 仓库时只显示应用标题，避免孤立下拉箭头与无用按钮
        Row({ space: 8 }) {
          if (this.vm.vaults.length > 0) {
            Row({ space: 6 }) {
              Text(this.vm.currentVault.name)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.design_text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 200 })
              Stack() {
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(13)
                  .fontColor([$r('app.color.design_text_secondary')])
              }
              .width(24)
              .height(24)
              .borderRadius(12)
              .backgroundColor($r('app.color.design_glass_bg'))
              .backgroundBlurStyle(BlurStyle.Thin)
              .border({ width: 1, color: $r('app.color.design_glass_stroke') })
            }
            .alignItems(VerticalAlign.Center)
            .layoutWeight(1)
            .onClick(() => {
              this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
                this.showVaultManager = true;
              });
            })

            this.headerIconCircle($r('sys.symbol.calendar'), $r('app.string.design_more_daily'), (): void => {
              this.openDailyAndJump();
            })

            this.headerIconCircle(
              this.filesGridMode ? $r('sys.symbol.list_bullet') : $r('sys.symbol.square_grid_2x2'),
              $r('app.string.files_view_grid'),
              (): void => {
                this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
                  this.filesGridMode = !this.filesGridMode;
                });
              }
            )
          } else {
            Text($r('app.string.app_title'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.design_text_primary'))
              .layoutWeight(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: BAR_SIDE_VP, right: BAR_SIDE_VP })

        // 分段胶囊切换栏（笔记 N | 收藏 N | 时间线 | 文件夹）
        if (this.vm.vaults.length > 0) {
          this.filesSegmentBar()
        }
      }
      .width('100%')
      .padding({ top: this.topInset + 8, bottom: 10 })
      .backgroundColor($r('app.color.design_glass_bg'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
  }

  /** 顶栏右侧 38vp 透明毛玻璃圆形图标按钮（随底层滚动内容实时变色模糊）。 */
  @Builder
  headerIconCircle(icon: Resource, a11y: Resource, action: () => void) {
    Stack() {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([$r('app.color.design_text_primary')])
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .backgroundColor($r('app.color.design_glass_bg'))
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: $r('app.color.design_glass_stroke') })
    .shadow({ radius: 10, color: $r('app.color.design_shadow'), offsetY: 3 })
    .accessibilityText(a11y)
    .onClick(() => {
      action();
    })
  }

  /** 笔记页分段胶囊切换栏（未选中项采用透明毛玻璃模糊，随背景动态变化）。 */
  @Builder
  filesSegmentBar() {
    Row() {
      Stack() {
        Text($r('app.string.files_seg_shelf', this.vm.vaultFiles.length))
          .fontSize(13)
          .fontWeight(this.filesSegment === 0 ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.filesSegment === 0 ?
            $r('app.color.design_surface_solid') : $r('app.color.design_text_primary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.filesSegment === 0 ?
        $r('app.color.design_text_primary') : $r('app.color.design_glass_bg'))
      .backgroundBlurStyle(this.filesSegment === 0 ? BlurStyle.NONE : BlurStyle.Thin)
      .border({
        width: 1,
        color: this.filesSegment === 0 ? $r('app.color.design_stroke') : $r('app.color.design_glass_stroke')
      })
      .onClick(() => {
        this.selectFilesSegment(0);
      })

      Stack() {
        Text($r('app.string.files_seg_bookmarks', this.vm.bookmarks.length))
          .fontSize(13)
          .fontWeight(this.filesSegment === 1 ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.filesSegment === 1 ?
            $r('app.color.design_surface_solid') : $r('app.color.design_text_primary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.filesSegment === 1 ?
        $r('app.color.design_text_primary') : $r('app.color.design_glass_bg'))
      .backgroundBlurStyle(this.filesSegment === 1 ? BlurStyle.NONE : BlurStyle.Thin)
      .border({
        width: 1,
        color: this.filesSegment === 1 ? $r('app.color.design_stroke') : $r('app.color.design_glass_stroke')
      })
      .margin({ left: 6 })
      .onClick(() => {
        this.selectFilesSegment(1);
      })

      Stack() {
        Text($r('app.string.files_seg_timeline'))
          .fontSize(13)
          .fontWeight(this.filesSegment === 2 ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.filesSegment === 2 ?
            $r('app.color.design_surface_solid') : $r('app.color.design_text_primary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.filesSegment === 2 ?
        $r('app.color.design_text_primary') : $r('app.color.design_glass_bg'))
      .backgroundBlurStyle(this.filesSegment === 2 ? BlurStyle.NONE : BlurStyle.Thin)
      .border({
        width: 1,
        color: this.filesSegment === 2 ? $r('app.color.design_stroke') : $r('app.color.design_glass_stroke')
      })
      .margin({ left: 6 })
      .onClick(() => {
        this.selectFilesSegment(2);
      })

      Stack() {
        Text($r('app.string.files_seg_folders'))
          .fontSize(13)
          .fontWeight(this.filesSegment === 3 ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.filesSegment === 3 ?
            $r('app.color.design_surface_solid') : $r('app.color.design_text_primary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.filesSegment === 3 ?
        $r('app.color.design_text_primary') : $r('app.color.design_glass_bg'))
      .backgroundBlurStyle(this.filesSegment === 3 ? BlurStyle.NONE : BlurStyle.Thin)
      .border({
        width: 1,
        color: this.filesSegment === 3 ? $r('app.color.design_stroke') : $r('app.color.design_glass_stroke')
      })
      .margin({ left: 6 })
      .onClick(() => {
        this.selectFilesSegment(3);
      })
    }
    .width('100%')
    .padding({ left: BAR_SIDE_VP, right: BAR_SIDE_VP })
  }

  private selectFilesSegment(seg: number): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
      this.filesSegment = seg;
      this.currentFolderPath = '';
    });
    this.filesScroller.scrollEdge(Edge.Top);
  }

  /** 分段 0：全部笔记视图（支持便签卡片宫格 / 经典列表双模式，目录点击原地穿透浏览）。 */
  @Builder
  shelfSegmentContent() {
    Column({ space: 12 }) {
      if (this.currentFolderPath.length > 0) {
        this.folderBrowserContent()
      } else if (this.filesGridMode) {
        this.bookshelfGridView(true, false)
      } else if (this.vm.rootFolders.length === 0 && this.vm.bookmarks.length === 0 && this.shelfNotes.length === 0) {
        Text($r('app.string.design_files_empty'))
          .fontSize(13)
          .fontColor($r('app.color.design_text_secondary'))
          .width('100%')
          .padding({ top: 32, bottom: 32, left: 20, right: 20 })
          .textAlign(TextAlign.Center)
      } else {
        if (this.vm.rootFolders.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.vm.rootFolders, (folder: RootFolderSummary) => {
              this.folderRow(folder)
            }, (folder: RootFolderSummary) => folder.path)
          }
          .width('100%')
        }
        if (this.vm.bookmarks.length > 0) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(13)
              .fontColor([$r('app.color.design_accent')])
            Text($r('app.string.bookmark_section'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_text_secondary'))
          }
          .width('100%')
          .margin({ top: 4 })

          ForEach(this.vm.bookmarks, (path: string) => {
            this.bookmarkNoteCard(path)
          }, (path: string) => path)
        }
        if (this.shelfNotes.length > 0) {
          Text($r('app.string.design_files_recent'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_secondary'))
            .width('100%')
            .margin({ top: 4 })

          ForEach(this.shelfNotes, (item: RecentNoteItem) => {
            this.recentNoteCard(item)
          }, (item: RecentNoteItem) => item.path)
        }
      }
    }
    .width('100%')
  }

  /** 分段 1：星标收藏笔记视图。 */
  @Builder
  bookmarkSegmentContent() {
    Column({ space: 10 }) {
      if (this.vm.bookmarks.length === 0) {
        Text($r('app.string.files_bookmarks_empty'))
          .fontSize(13)
          .fontColor($r('app.color.design_text_secondary'))
          .width('100%')
          .padding({ top: 32, bottom: 32, left: 20, right: 20 })
          .textAlign(TextAlign.Center)
      } else if (this.filesGridMode) {
        this.bookshelfGridView(false, true)
      } else {
        ForEach(this.vm.bookmarks, (path: string) => {
          this.bookmarkNoteCard(path)
        }, (path: string) => path)
      }
    }
    .width('100%')
  }

  /** 分段 2：时间线笔记流（左真实日期/编号字牌 + 右素雅柔彩笔记卡）。 */
  @Builder
  timelineSegmentContent() {
    Column({ space: 12 }) {
      if (this.shelfNotes.length === 0) {
        Text($r('app.string.design_files_empty'))
          .fontSize(13)
          .fontColor($r('app.color.design_text_secondary'))
          .width('100%')
          .padding({ top: 24, bottom: 24 })
          .textAlign(TextAlign.Center)
      } else {
        ForEach(this.shelfNotes, (item: RecentNoteItem, index: number) => {
          this.timelineNoteRow(item, index)
        }, (item: RecentNoteItem) => item.path)
      }
    }
    .width('100%')
  }

  /** 分段 3：文件夹与根目录笔记列表（支持原地逐级展开子目录与直属笔记，不跳转工作台）。 */
  @Builder
  folderSegmentContent() {
    Column({ space: 10 }) {
      if (this.currentFolderPath.length > 0) {
        this.folderBrowserContent()
      } else if (this.vm.rootFolders.length === 0 && this.rootNotes.length === 0) {
        Text($r('app.string.files_folder_empty'))
          .fontSize(13)
          .fontColor($r('app.color.design_text_secondary'))
          .width('100%')
          .padding({ top: 32, bottom: 32, left: 20, right: 20 })
          .textAlign(TextAlign.Center)
      } else {
        if (this.vm.rootFolders.length > 0) {
          ForEach(this.vm.rootFolders, (folder: RootFolderSummary) => {
            this.folderRow(folder)
          }, (folder: RootFolderSummary) => folder.path)
        }

        if (this.rootNotes.length > 0) {
          Text($r('app.string.files_root_notes_header', this.rootNotes.length))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_secondary'))
            .width('100%')
            .margin({ top: 4 })

          if (this.filesGridMode) {
            this.noteGridThreeCol(3, 0)
          } else {
            ForEach(this.rootNotes, (item: RecentNoteItem) => {
              this.recentNoteCard(item)
            }, (item: RecentNoteItem) => `root_${item.path}`)
          }
        }
      }
    }
    .width('100%')
  }

  /** 原地目录浏览器：统一莫兰迪柔彩列表/宫格风格，支持多级子目录逐层进入与面包屑返回。 */
  @Builder
  folderBrowserContent() {
    Column({ space: 10 }) {
      this.folderBreadcrumbCard()

      if (this.activeSubFolders.length === 0 && this.activeFolderNotes.length === 0) {
        Text($r('app.string.files_folder_empty'))
          .fontSize(13)
          .fontColor($r('app.color.design_text_secondary'))
          .width('100%')
          .padding({ top: 32, bottom: 32, left: 20, right: 20 })
          .textAlign(TextAlign.Center)
      } else {
        if (this.activeSubFolders.length > 0) {
          ForEach(this.activeSubFolders, (folder: RootFolderSummary) => {
            this.folderRow(folder)
          }, (folder: RootFolderSummary) => folder.path)
        }

        if (this.activeFolderNotes.length > 0) {
          if (this.activeSubFolders.length > 0) {
            Text($r('app.string.files_folder_section_notes', this.activeFolderNotes.length))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_text_secondary'))
              .width('100%')
              .margin({ top: 4 })
          }

          if (this.filesGridMode) {
            this.noteGridThreeCol(2, 0)
          } else {
            ForEach(this.activeFolderNotes, (item: RecentNoteItem) => {
              this.recentNoteCard(item)
            }, (item: RecentNoteItem) => `${this.currentFolderPath}_${item.path}`)
          }
        }
      }
    }
    .width('100%')
  }

  /** 目录导航面包屑卡：继承当前文件夹低饱和纸色，提供返回上级与可点击祖先路径。 */
  @Builder
  folderBreadcrumbCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(16)
            .fontColor([this.tintFgOf(this.currentFolderPath)])
        }
        .width(34)
        .height(34)
        .borderRadius(11)
        .backgroundColor(this.tintPillOf(this.currentFolderPath))
        .accessibilityText($r('app.string.files_folder_up'))
        .onClick(() => {
          this.navigateFolderUp();
        })

        Column({ space: 2 }) {
          Text(this.folderLeafName(this.currentFolderPath))
            .fontSize(16.5)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.activeSubFolders.length > 0 && this.activeFolderNotes.length > 0) {
            Text($r('app.string.files_folder_summary', this.activeSubFolders.length, this.activeFolderNotes.length))
              .fontSize(12)
              .fontColor(this.tintFgOf(this.currentFolderPath))
          } else if (this.activeSubFolders.length > 0) {
            Text($r('app.string.files_folder_sub_count', this.activeSubFolders.length))
              .fontSize(12)
              .fontColor(this.tintFgOf(this.currentFolderPath))
          } else {
            Text($r('app.string.design_files_folder_count', this.activeFolderNotes.length))
              .fontSize(12)
              .fontColor(this.tintFgOf(this.currentFolderPath))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Stack() {
          ThreeDotsIcon(3.2, 2.8, this.tintFgOf(this.currentFolderPath), 0.9)
        }
        .width(34)
        .height(34)
        .borderRadius(11)
        .backgroundColor(this.tintPillOf(this.currentFolderPath))
        .accessibilityText($r('app.string.files_folder_actions'))
        .onClick(() => {
          this.handleCardTap(() => {
            this.openItemMenu(this.currentFolderPath, true);
          });
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Row({ space: 4 }) {
          Text($r('app.string.files_folder_root'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_secondary'))
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(9)
            .backgroundColor($r('app.color.design_glass_bg'))
            .border({ width: 0.8, color: $r('app.color.design_glass_stroke') })
            .onClick(() => {
              this.enterFolder('');
            })

          ForEach(this.folderBreadcrumbSegments(), (segPath: string) => {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(11)
                .fontColor([$r('app.color.design_text_secondary')])
                .opacity(0.6)
              Text(this.folderLeafName(segPath))
                .fontSize(12)
                .fontWeight(segPath === this.currentFolderPath ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(segPath === this.currentFolderPath ?
                  this.tintFgOf(this.currentFolderPath) : $r('app.color.design_text_secondary'))
                .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                .borderRadius(9)
                .backgroundColor(segPath === this.currentFolderPath ?
                  this.tintPillOf(this.currentFolderPath) : $r('app.color.design_glass_bg'))
                .border({
                  width: 0.8,
                  color: segPath === this.currentFolderPath ?
                    this.tintPillOf(this.currentFolderPath) : $r('app.color.design_glass_stroke')
                })
                .maxLines(1)
                .onClick(() => {
                  this.enterFolder(segPath);
                })
            }
            .alignItems(VerticalAlign.Center)
          }, (segPath: string) => `${segPath}_${segPath === this.currentFolderPath}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(18)
    .backgroundColor(this.tintBgOf(this.currentFolderPath))
    .border({ width: 0.8, color: this.tintPillOf(this.currentFolderPath) })
  }

  /**
   * 笔记卡片宫格视图：
   * - showFeatured=true 时，首行渲染「2:1 精选最近编辑区」（左侧深墨黑最近笔记大卡 + 右侧莫兰迪便签卡）；
   * - 其余笔记以三列莫兰迪便签卡片宫格呈现（右上角均可直接点按星标收藏/取消收藏）。
   */
  @Builder
  bookshelfGridView(showFeatured: boolean, onlyBookmarks: boolean) {
    Column({ space: 16 }) {
      if (this.gridNotesForSource(onlyBookmarks ? 1 : 0).length === 0) {
        Text($r('app.string.design_files_empty'))
          .fontSize(13)
          .fontColor($r('app.color.design_text_secondary'))
          .width('100%')
          .padding({ top: 24, bottom: 24 })
          .textAlign(TextAlign.Center)
      } else {
        if (showFeatured && this.gridNotesForSource(onlyBookmarks ? 1 : 0).length >= 1) {
          Row({ space: 12 }) {
            Column() {
              this.featuredSpreadCard(this.gridNotesForSource(onlyBookmarks ? 1 : 0)[0])
            }
            .layoutWeight(2)

            if (this.gridNotesForSource(onlyBookmarks ? 1 : 0).length >= 2) {
              Column() {
                this.bookCoverCard(this.gridNotesForSource(onlyBookmarks ? 1 : 0)[1], 124)
              }
              .layoutWeight(1)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }

        this.noteGridThreeCol(onlyBookmarks ? 1 : 0,
          showFeatured ? Math.min(2, this.gridNotesForSource(onlyBookmarks ? 1 : 0).length) : 0)
      }
    }
    .width('100%')
  }

  /** 共用三列莫兰迪便签卡片宫格（source: 0 全部 / 1 收藏 / 2 当前目录 / 3 根目录）。 */
  @Builder
  noteGridThreeCol(source: number, startFrom: number) {
    Column({ space: 16 }) {
      ForEach(this.gridRowIndices(this.gridNotesForSource(source).length, startFrom),
        (startIdx: number) => {
          Row({ space: 12 }) {
            ForEach([0, 1, 2], (colOffset: number) => {
              if (startIdx + colOffset < this.gridNotesForSource(source).length) {
                Column() {
                  this.bookCoverCard(this.gridNotesForSource(source)[startIdx + colOffset], 130)
                }
                .layoutWeight(1)
              } else {
                Blank()
                  .layoutWeight(1)
              }
            }, (colOffset: number) => `col_${source}_${startIdx}_${colOffset}`)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (startIdx: number) => `row_${source}_${this.currentFolderPath}_${startIdx}`)
    }
    .width('100%')
  }

  /** 首行左侧：最近编辑笔记精选大卡（支持一键星标收藏与直接点按续写）。 */
  @Builder
  featuredSpreadCard(item: RecentNoteItem) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text($r('app.string.files_featured_badge'))
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.design_accent'))
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor($r('app.color.design_accent_weak'))
            Text(this.folderBadgeOf(item.path))
              .fontSize(10)
              .fontColor($r('app.color.design_cover_text'))
              .opacity(0.65)
              .maxLines(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(item.title)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_cover_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(20)
            .width('100%')

          Blank()

          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(11)
              .fontColor([$r('app.color.design_cover_text')])
              .opacity(0.7)
            Text(item.path)
              .fontSize(10)
              .fontColor($r('app.color.design_cover_text'))
              .opacity(0.7)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 10 })
        .alignItems(HorizontalAlign.Start)

        // 右上角可交互星标按钮（点按直接收藏/取消收藏该笔记）
        Stack() {
          SymbolGlyph(this.vm.isBookmarked(item.path) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
            .fontSize(14)
            .fontColor([this.vm.isBookmarked(item.path) ?
              $r('app.color.design_accent') : $r('app.color.design_cover_text')])
        }
        .width(28)
        .height(28)
        .margin({ top: 4, right: 4 })
        .onClick(() => {
          this.handleCardTap(() => {
            this.vm.toggleBookmark(item.path);
          });
        })
      }
      .width('100%')
      .height(124)
      .borderRadius(12)
      .backgroundColor($r('app.color.design_cover_ink'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 12, color: $r('app.color.design_shadow'), offsetY: 4 })

      Text(item.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 4 }) {
        Text(item.openedAt > 0 ? formatRelativeTime(item.openedAt) : this.folderBadgeOf(item.path))
          .fontSize(11)
          .fontColor($r('app.color.design_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.itemMoreButton(item.path, false, $r('app.color.design_text_secondary'), true)
      }
      .width('100%')
      .height(24)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .gestureModifier(this.longPressFor(item.path, false))
    .onClick(() => {
      this.handleCardTap(() => {
        this.openWorkspace({ 'openPath': item.path });
      });
    })
  }

  /** 莫兰迪便签笔记宫格卡（内框标题 + 底部所属文件夹 + 右上角可点击星标按钮）。 */
  @Builder
  bookCoverCard(item: RecentNoteItem, coverHeight: number) {
    Column({ space: 6 }) {
      Column() {
        Column() {
          Row() {
            Blank()
            Stack() {
              SymbolGlyph(this.vm.isBookmarked(item.path) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                .fontSize(12)
                .fontColor([$r('app.color.design_cover_text')])
                .opacity(this.vm.isBookmarked(item.path) ? 1.0 : 0.72)
            }
            .width(22)
            .height(22)
            .alignContent(Alignment.Center)
            .onClick(() => {
              this.handleCardTap(() => {
                this.vm.toggleBookmark(item.path);
              });
            })
          }
          .width('100%')

          Text(item.title)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_cover_text'))
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(16)
            .width('100%')
            .margin({ top: 4 })

          Row()
            .width(18)
            .height(1)
            .backgroundColor($r('app.color.design_cover_text'))
            .opacity(0.65)
            .margin({ top: 6 })

          Blank()

          Text(this.folderBadgeOf(item.path))
            .fontSize(9)
            .fontColor($r('app.color.design_cover_text'))
            .opacity(0.85)
            .maxLines(1)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 7, right: 7, top: 5, bottom: 7 })
        .borderRadius(6)
        .border({ width: 1, color: $r('app.color.design_cover_text') })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height(coverHeight)
      .padding(6)
      .borderRadius(10)
      .backgroundColor(this.coverColorOf(item.path))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 10, color: $r('app.color.design_shadow'), offsetY: 3 })

      Text(item.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 4 }) {
        Text(item.openedAt > 0 ? formatRelativeTime(item.openedAt) : item.path)
          .fontSize(11)
          .fontColor($r('app.color.design_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.itemMoreButton(item.path, false, $r('app.color.design_text_secondary'), true)
      }
      .width('100%')
      .height(24)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .gestureModifier(this.longPressFor(item.path, false))
    .onClick(() => {
      this.handleCardTap(() => {
        this.openWorkspace({ 'openPath': item.path });
      });
    })
  }

  /** 时间线笔记行（左大字真实日期/序号字牌 + 右白底笔记卡片，支持一键收藏）。 */
  @Builder
  timelineNoteRow(item: RecentNoteItem, index: number) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.timelinePrimaryBadge(item, index))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.design_text_primary'))
        Text(this.timelineSecondaryBadge(item))
          .fontSize(11)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .width(44)
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 4 })

      Column({ space: 10 }) {
        Row({ space: 10 }) {
          this.miniBookCover(item.path, item.title)

          Column({ space: 4 }) {
            Text(item.title)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.design_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.folderBadgeOf(item.path))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tintFgOf(item.path))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(this.tintPillOf(item.path))
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: 2 }) {
            Stack() {
              SymbolGlyph(this.vm.isBookmarked(item.path) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                .fontSize(16)
                .fontColor([this.vm.isBookmarked(item.path) ?
                  $r('app.color.design_accent') : this.tintFgOf(item.path)])
            }
            .width(32)
            .height(32)
            .onClick(() => {
              this.handleCardTap(() => {
                this.vm.toggleBookmark(item.path);
              });
            })

            this.itemMoreButton(item.path, false, this.tintFgOf(item.path), false)
          }
        }
        .width('100%')

        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(13)
            .fontColor([this.tintFgOf(item.path)])
          Text(item.path)
            .fontSize(12)
            .fontColor($r('app.color.design_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.openedAt > 0) {
            Text(formatRelativeTime(item.openedAt))
              .fontSize(11)
              .fontColor(this.tintFgOf(item.path))
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .padding(14)
      .borderRadius(18)
      .backgroundColor(this.tintBgOf(item.path))
      .border({ width: 0.8, color: this.tintPillOf(item.path) })
      .gestureModifier(this.longPressFor(item.path, false))
      .onClick(() => {
        this.handleCardTap(() => {
          this.openWorkspace({ 'openPath': item.path });
        });
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 微缩便签图标（用于时间线卡片与「更多-最近笔记」卡片）。 */
  @Builder
  miniBookCover(path: string, title: string) {
    Column() {
      Text(title.length > 0 ? title.substring(0, Math.min(2, title.length)) : 'MD')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.design_cover_text'))
        .maxLines(1)
    }
    .width(36)
    .height(42)
    .borderRadius(8)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.coverColorOf(path))
    .border({ width: 1, color: $r('app.color.design_stroke') })
  }

  /** 汇总展示笔记列表（优先最近访问，不足时以仓库内笔记补足至最多 18 篇）。 */
  @Computed
  get shelfNotes(): RecentNoteItem[] {
    const result: RecentNoteItem[] = [];
    const seen: Set<string> = new Set<string>();
    for (const item of this.vm.recentNotes) {
      if (!this.vm.vaultFiles.includes(item.path)) {
        continue;
      }
      result.push(item);
      seen.add(item.path);
    }
    for (const path of this.vm.vaultFiles) {
      if (result.length >= 18) {
        break;
      }
      if (path.endsWith('.md') && !seen.has(path)) {
        seen.add(path);
        result.push({
          path: path,
          title: this.noteTitleFromPath(path),
          openedAt: 0
        });
      }
    }
    return result;
  }

  /** 根目录直属笔记列表（用于「文件夹」页签展示）。 */
  @Computed
  get rootNotes(): RecentNoteItem[] {
    const result: RecentNoteItem[] = [];
    for (const path of this.vm.vaultFiles) {
      if (path.endsWith('.md') && path.indexOf('/') < 0) {
        result.push({
          path: path,
          title: this.noteTitleFromPath(path),
          openedAt: 0
        });
      }
    }
    return result;
  }

  /** 收藏笔记转为 RecentNoteItem 列表。 */
  @Computed
  get bookmarkNotes(): RecentNoteItem[] {
    const result: RecentNoteItem[] = [];
    for (const path of this.vm.bookmarks) {
      result.push({
        path: path,
        title: this.noteTitleFromPath(path),
        openedAt: 0
      });
    }
    return result;
  }

  /** 当前浏览目录的直接子目录摘要（按当前仓库目录树计算）。 */
  @Computed
  get activeSubFolders(): RootFolderSummary[] {
    if (this.vm.vaultFiles.length === 0 && this.vm.rootFolders.length === 0) {
      return [];
    }
    return this.vm.listSubFolders(this.currentFolderPath);
  }

  /** 当前浏览目录的直属 Markdown 笔记列表（保留最近访问时间戳）。 */
  @Computed
  get activeFolderNotes(): RecentNoteItem[] {
    const recentTimeByPath: Map<string, number> = new Map<string, number>();
    for (const recent of this.vm.recentNotes) {
      recentTimeByPath.set(recent.path, recent.openedAt);
    }
    const prefix: string = this.currentFolderPath.length > 0 ? `${this.currentFolderPath}/` : '';
    const result: RecentNoteItem[] = [];
    for (const path of this.vm.vaultFiles) {
      if (!path.toLowerCase().endsWith('.md')) {
        continue;
      }
      if (prefix.length === 0) {
        if (path.indexOf('/') >= 0) {
          continue;
        }
      } else {
        if (!path.startsWith(prefix)) {
          continue;
        }
        if (path.substring(prefix.length).indexOf('/') >= 0) {
          continue;
        }
      }
      const openedAt: number | undefined = recentTimeByPath.get(path);
      result.push({
        path: path,
        title: this.noteTitleFromPath(path),
        openedAt: openedAt !== undefined ? openedAt : 0
      });
    }
    return result;
  }

  private gridNotesForSource(source: number): RecentNoteItem[] {
    if (source === 1) {
      return this.bookmarkNotes;
    }
    if (source === 2) {
      return this.activeFolderNotes;
    }
    if (source === 3) {
      return this.rootNotes;
    }
    return this.shelfNotes;
  }

  /** 在首页目录树内原地进入子目录（不跳转工作台、不自动打开文件）。 */
  private enterFolder(folderPath: string): void {
    if (folderPath === this.currentFolderPath) {
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
      this.currentFolderPath = folderPath;
    });
    this.filesScroller.scrollEdge(Edge.Top);
  }

  /** 目录浏览器返回上一级（已在根目录时不变）。 */
  private navigateFolderUp(): void {
    if (this.currentFolderPath.length === 0) {
      return;
    }
    const lastSlash: number = this.currentFolderPath.lastIndexOf('/');
    const parentPath: string = lastSlash > 0 ? this.currentFolderPath.substring(0, lastSlash) : '';
    this.enterFolder(parentPath);
  }

  /** 将当前浏览路径拆分为逐级可点击的累积路径列表。 */
  private folderBreadcrumbSegments(): string[] {
    if (this.currentFolderPath.length === 0) {
      return [];
    }
    const parts: string[] = this.currentFolderPath.split('/');
    const paths: string[] = [];
    let acc: string = '';
    for (const part of parts) {
      if (part.length === 0) {
        continue;
      }
      acc = acc.length === 0 ? part : `${acc}/${part}`;
      paths.push(acc);
    }
    return paths;
  }

  private folderLeafName(folderPath: string): string {
    const slash: number = folderPath.lastIndexOf('/');
    return slash >= 0 ? folderPath.substring(slash + 1) : folderPath;
  }

  /** 三列宫格每行起始下标。 */
  private gridRowIndices(total: number, startFrom: number): number[] {
    const indices: number[] = [];
    for (let i: number = startFrom; i < total; i += 3) {
      indices.push(i);
    }
    return indices;
  }

  /** 按路径哈希稳定选取 5 款素雅低饱和纸色索引。 */
  private tintIndexOf(path: string): number {
    let hash: number = 0;
    for (let i: number = 0; i < path.length; i++) {
      hash = (hash * 31 + path.charCodeAt(i)) & 0x7fffffff;
    }
    return hash % TINT_BG_PALETTE.length;
  }

  private tintBgOf(path: string): Resource {
    return TINT_BG_PALETTE[this.tintIndexOf(path)];
  }

  private tintPillOf(path: string): Resource {
    return TINT_PILL_PALETTE[this.tintIndexOf(path)];
  }

  private tintFgOf(path: string): Resource {
    return TINT_FG_PALETTE[this.tintIndexOf(path)];
  }

  private isDailyNotePath(path: string): boolean {
    const title: string = this.noteTitleFromPath(path);
    return path.startsWith('日记/') ||
      (title.length >= 10 && title.charAt(4) === '-' && title.charAt(7) === '-');
  }

  /** 按路径哈希稳定选取 4 款莫兰迪便签色。 */
  private coverColorOf(path: string): Resource {
    let hash: number = 0;
    for (let i: number = 0; i < path.length; i++) {
      hash = (hash * 31 + path.charCodeAt(i)) & 0x7fffffff;
    }
    const idx: number = hash % 4;
    if (idx === 0) {
      return $r('app.color.design_cover_rose');
    }
    if (idx === 1) {
      return $r('app.color.design_cover_sage');
    }
    if (idx === 2) {
      return $r('app.color.design_cover_ochre');
    }
    return $r('app.color.design_cover_violet');
  }

  /** 提取笔记所属目录名称（保留嵌套日记如 `日记 · 2026-11`）。 */
  private folderBadgeOf(path: string): string {
    const lastSlash: number = path.lastIndexOf('/');
    return lastSlash > 0 ? path.substring(0, lastSlash).replace(/\//g, ' · ') : '根目录';
  }

  /** 时间线左侧主数字（优先解析 YYYY-MM-DD 日期，其次 openedAt，再回退笔记序号）。 */
  private timelinePrimaryBadge(item: RecentNoteItem, fallbackIdx: number): string {
    if (item.title.length >= 10 && item.title.charAt(4) === '-' && item.title.charAt(7) === '-') {
      return item.title.substring(8, 10);
    }
    if (item.openedAt > 0) {
      const d: Date = new Date(item.openedAt);
      const day: number = d.getDate();
      return day < 10 ? `0${day}` : `${day}`;
    }
    if (item.title.length >= 2 && item.title.charAt(0) >= '0' && item.title.charAt(0) <= '9' &&
      item.title.charAt(1) >= '0' && item.title.charAt(1) <= '9') {
      return item.title.substring(0, 2);
    }
    const seq: number = fallbackIdx + 1;
    return seq < 10 ? `0${seq}` : `${seq}`;
  }

  /** 时间线左侧副标签（月份或 #序号）。 */
  private timelineSecondaryBadge(item: RecentNoteItem): ResourceStr {
    if (item.title.length >= 10 && item.title.charAt(4) === '-' && item.title.charAt(7) === '-') {
      const monthNum: number = Number.parseInt(item.title.substring(5, 7));
      if (!Number.isNaN(monthNum) && monthNum >= 1 && monthNum <= 12) {
        return $r('app.string.timeline_month_fmt', monthNum);
      }
    }
    if (item.openedAt > 0) {
      const d: Date = new Date(item.openedAt);
      return $r('app.string.timeline_month_fmt', d.getMonth() + 1);
    }
    return $r('app.string.more_stat_notes');
  }

  @Builder
  onboardCard() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(30)
        .fontColor([$r('app.color.design_accent')])
      Text($r('app.string.design_onboard_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.design_text_primary'))
      Text($r('app.string.design_onboard_sub'))
        .fontSize(13)
        .fontColor($r('app.color.design_text_secondary'))
        .textAlign(TextAlign.Center)
      Text($r('app.string.design_onboard_create'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_accent'))
        .padding({ left: 22, right: 22, top: 10, bottom: 10 })
        .borderRadius(22)
        .backgroundColor($r('app.color.design_accent_weak'))
        .margin({ top: 6 })
        .onClick(() => {
          this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
            this.showCreateVaultDialog = true;
          });
        })
    }
    .width('100%')
    .padding({ top: 28, bottom: 26, left: 20, right: 20 })
    .borderRadius(20)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 24 })
  }

  @Builder
  folderRow(folder: RootFolderSummary) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(17)
          .fontColor([this.tintFgOf(folder.path)])
      }
      .width(34)
      .height(34)
      .borderRadius(10)
      .backgroundColor(this.tintPillOf(folder.path))

      Text(folder.name)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text($r('app.string.design_files_folder_count', folder.noteCount))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tintFgOf(folder.path))
        .padding({ left: 9, right: 9, top: 3, bottom: 3 })
        .borderRadius(10)
        .backgroundColor(this.tintPillOf(folder.path))
      this.itemMoreButton(folder.path, true, this.tintFgOf(folder.path), false)
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 10 })
    .borderRadius(16)
    .backgroundColor(this.tintBgOf(folder.path))
    .border({ width: 0.8, color: this.tintPillOf(folder.path) })
    .gestureModifier(this.longPressFor(folder.path, true))
    .onClick(() => {
      this.handleCardTap(() => {
        this.enterFolder(folder.path);
      });
    })
  }

  @Builder
  recentNoteCard(item: RecentNoteItem) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph(this.isDailyNotePath(item.path) ? $r('sys.symbol.calendar') : $r('sys.symbol.doc_plaintext'))
          .fontSize(18)
          .fontColor([this.tintFgOf(item.path)])
      }
      .width(38)
      .height(42)
      .borderRadius(11)
      .backgroundColor(this.tintPillOf(item.path))

      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(item.title)
            .fontSize(15.5)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.vm.isBookmarked(item.path)) {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(12)
              .fontColor([$r('app.color.design_accent')])
          }
          if (item.openedAt > 0) {
            Text(formatRelativeTime(item.openedAt))
              .fontSize(11.5)
              .fontColor(this.tintFgOf(item.path))
          }
        }
        .width('100%')

        Row({ space: 6 }) {
          Text(this.folderBadgeOf(item.path))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tintFgOf(item.path))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(7)
            .backgroundColor(this.tintPillOf(item.path))
            .maxLines(1)
          Text(item.path)
            .fontSize(11.5)
            .fontColor($r('app.color.design_text_secondary'))
            .opacity(0.85)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.itemMoreButton(item.path, false, this.tintFgOf(item.path), false)
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(16)
    .backgroundColor(this.tintBgOf(item.path))
    .border({ width: 0.8, color: this.tintPillOf(item.path) })
    .gestureModifier(this.longPressFor(item.path, false))
    .onClick(() => {
      this.handleCardTap(() => {
        this.openWorkspace({ 'openPath': item.path });
      });
    })
  }

  @Builder
  bookmarkNoteCard(path: string) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(16)
          .fontColor([$r('app.color.design_accent')])
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor(this.tintPillOf(path))
      .onClick(() => {
        this.handleCardTap(() => {
          this.vm.toggleBookmark(path);
        });
      })
      Column({ space: 4 }) {
        Text(this.noteTitleFromPath(path))
          .fontSize(15.5)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text(this.folderBadgeOf(path))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tintFgOf(path))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(7)
            .backgroundColor(this.tintPillOf(path))
            .maxLines(1)
          Text(path)
            .fontSize(11.5)
            .fontColor($r('app.color.design_text_secondary'))
            .opacity(0.85)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      this.itemMoreButton(path, false, this.tintFgOf(path), false)
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(16)
    .backgroundColor(this.tintBgOf(path))
    .border({ width: 0.8, color: this.tintPillOf(path) })
    .gestureModifier(this.longPressFor(path, false))
    .onClick(() => {
      this.handleCardTap(() => {
        this.openWorkspace({ 'openPath': path });
      });
    })
  }

  /** 条目卡片最右侧「更多操作」入口（点击即弹出与长按一致的操作面板）。 */
  @Builder
  itemMoreButton(path: string, isDir: boolean, tintColor: Resource, compact: boolean) {
    Stack() {
      ThreeDotsIcon(compact ? 2.6 : 3.2, compact ? 2.2 : 2.8, tintColor, 0.78)
    }
    .width(compact ? 26 : 34)
    .height(compact ? 24 : 34)
    .borderRadius(compact ? 8 : 10)
    .accessibilityText(isDir ? $r('app.string.files_folder_actions') : $r('app.string.note_more_actions'))
    .onClick(() => {
      this.handleCardTap(() => {
        this.openItemMenu(path, isDir);
      });
    })
  }

  private noteTitleFromPath(path: string): string {
    return resolveNoteTitle(path);
  }

  // ==================== 搜索页 ====================

  @Builder
  searchPage() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 12 }) {
          if (this.vm.vaults.length === 0) {
            this.needVaultCard()
          } else {
            // 全文模式：检索前引导提示卡
            if (this.searchVm.searchMode === 0 && !this.hasSearched) {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(16)
                  .fontColor([$r('app.color.design_accent')])
                Text($r('app.string.design_search_full_hint'))
                  .fontSize(13)
                  .fontColor($r('app.color.design_text_secondary'))
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 16, bottom: 16, left: 16, right: 16 })
              .borderRadius(20)
              .backgroundColor($r('app.color.design_surface_solid'))
              .border({ width: 1, color: $r('app.color.design_stroke') })
            }

            // 标签模式：多行自动换行平铺标签面板（随页面上下滑动）
            if (this.searchVm.searchMode === 1) {
              if (this.searchVm.tagChips.length === 0) {
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.hash'))
                    .fontSize(16)
                    .fontColor([$r('app.color.design_accent')])
                  Text($r('app.string.design_search_tag_hint'))
                    .fontSize(13)
                    .fontColor($r('app.color.design_text_secondary'))
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ top: 16, bottom: 16, left: 16, right: 16 })
                .borderRadius(20)
                .backgroundColor($r('app.color.design_surface_solid'))
                .border({ width: 1, color: $r('app.color.design_stroke') })
              } else {
                Column({ space: 12 }) {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.hash'))
                      .fontSize(15)
                      .fontColor([$r('app.color.design_accent')])
                    Text($r('app.string.search_tags_all_header', this.searchVm.tagChips.length))
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.design_text_primary'))
                      .layoutWeight(1)
                    if (this.searchVm.activeTag.length > 0) {
                      Row({ space: 4 }) {
                        Text($r('app.string.search_tags_clear_filter', this.searchVm.activeTag))
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.design_accent'))
                        SymbolGlyph($r('sys.symbol.xmark'))
                          .fontSize(11)
                          .fontColor([$r('app.color.design_accent')])
                      }
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .borderRadius(12)
                      .backgroundColor($r('app.color.design_accent_weak'))
                      .onClick(() => {
                        this.selectTagChip(this.searchVm.activeTag);
                      })
                    } else {
                      Text($r('app.string.search_tags_tap_hint'))
                        .fontSize(12)
                        .fontColor($r('app.color.design_text_secondary'))
                    }
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)

                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(this.searchVm.tagChips, (chip: TagRef) => {
                      Row({ space: 6 }) {
                        Text(`#${chip.tag}`)
                          .fontSize(13)
                          .fontWeight(chip.tag === this.searchVm.activeTag ? FontWeight.Bold : FontWeight.Medium)
                          .fontColor(chip.tag === this.searchVm.activeTag ?
                            $r('app.color.design_on_accent') : $r('app.color.design_text_primary'))
                        Text(`${chip.count}`)
                          .fontSize(11)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(chip.tag === this.searchVm.activeTag ?
                            $r('app.color.design_on_accent') : $r('app.color.design_accent'))
                          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                          .borderRadius(8)
                          .backgroundColor(chip.tag === this.searchVm.activeTag ?
                            $r('app.color.design_glass_pill') : $r('app.color.design_accent_weak'))
                      }
                      .padding({ left: 12, right: 10, top: 7, bottom: 7 })
                      .borderRadius(16)
                      .backgroundColor(chip.tag === this.searchVm.activeTag ?
                        $r('app.color.design_accent') : $r('app.color.design_elevated'))
                      .border({
                        width: 1,
                        color: chip.tag === this.searchVm.activeTag ?
                          $r('app.color.design_accent') : $r('app.color.design_stroke')
                      })
                      .margin({ right: 8, bottom: 8 })
                      .onClick(() => {
                        this.selectTagChip(chip.tag);
                      })
                    }, (chip: TagRef) => `${chip.tag}_${chip.count}_${chip.tag === this.searchVm.activeTag}`)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 8 })
                .borderRadius(20)
                .backgroundColor($r('app.color.design_surface_solid'))
                .border({ width: 1, color: $r('app.color.design_stroke') })
              }
            }

            // 属性模式：格式提示卡片
            if (this.searchVm.searchMode === 2 && !this.hasSearched) {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.list_bullet'))
                  .fontSize(16)
                  .fontColor([$r('app.color.design_accent')])
                Text($r('app.string.design_search_prop_hint'))
                  .fontSize(13)
                  .fontColor($r('app.color.design_text_secondary'))
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 16, bottom: 16, left: 16, right: 16 })
              .borderRadius(20)
              .backgroundColor($r('app.color.design_surface_solid'))
              .border({ width: 1, color: $r('app.color.design_stroke') })
            }

            // 结果计数
            if (this.hasSearched) {
              Text(this.searchCountLabel)
                .fontSize(12)
                .fontColor($r('app.color.design_text_secondary'))
                .width('100%')
            }

            // 命中列表（关键词高亮）
            ForEach(this.searchRows, (row: DesignSearchRow) => {
              this.searchHitCell(row)
            }, (row: DesignSearchRow) => row.keyId)
          }
        }
        .width('100%')
        .padding({
          left: BAR_SIDE_VP,
          right: BAR_SIDE_VP,
          top: this.topInset + (this.vm.vaults.length > 0 ? 112 : 24),
          bottom: CAPSULE_HEIGHT_VP + BAR_BOTTOM_VP + this.bottomInset + 24
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 悬浮毛玻璃搜索栏 + 模式胶囊
      if (this.vm.vaults.length > 0) {
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([$r('app.color.design_text_secondary')])
            TextInput({ text: this.searchKeyword, placeholder: $r('app.string.design_search_hint') })
              .layoutWeight(1)
              .height(40)
              .padding({ left: 0, right: 0 })
              .backgroundColor(Color.Transparent)
              .placeholderColor($r('app.color.design_text_secondary'))
              .placeholderFont({ size: 14 })
              .fontSize(14)
              .fontColor($r('app.color.design_text_primary'))
              .caretColor($r('app.color.design_accent'))
              .onChange((value: string) => {
                this.onSearchKeywordChange(value);
              })
            if (this.searchKeyword.length > 0) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(14)
                .fontColor([$r('app.color.design_text_secondary')])
                .onClick(() => {
                  this.clearSearch();
                })
            }
          }
          .width('100%')
          .height(48)
          .padding({ left: 14, right: 14 })
          .borderRadius(24)
          .backgroundColor($r('app.color.design_glass_bg'))
          .backgroundBlurStyle(BlurStyle.Thin)
          .border({ width: 1, color: $r('app.color.design_glass_stroke') })
          .shadow({ radius: 12, color: $r('app.color.design_shadow'), offsetY: 4 })

          // 模式 chips（全文 / 标签 / 属性）
          Row({ space: 8 }) {
            ForEach(this.modeChips, (chip: DesignModeChip) => {
              Text(chip.label)
                .fontSize(13)
                .fontWeight(chip.mode === this.searchVm.searchMode ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(chip.mode === this.searchVm.searchMode ?
                  $r('app.color.design_surface_solid') : $r('app.color.design_text_primary'))
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .borderRadius(16)
                .backgroundColor(chip.mode === this.searchVm.searchMode ?
                  $r('app.color.design_text_primary') : $r('app.color.design_glass_bg'))
                .backgroundBlurStyle(chip.mode === this.searchVm.searchMode ? BlurStyle.NONE : BlurStyle.Thin)
                .border({
                  width: 1,
                  color: chip.mode === this.searchVm.searchMode ?
                    $r('app.color.design_stroke') : $r('app.color.design_glass_stroke')
                })
                .onClick(() => {
                  this.switchSearchMode(chip.mode);
                })
            }, (chip: DesignModeChip) => `${chip.keyId}_${chip.mode === this.searchVm.searchMode}`)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: BAR_SIDE_VP, right: BAR_SIDE_VP, top: this.topInset + 10, bottom: 10 })
        .backgroundColor($r('app.color.design_glass_bg'))
        .backgroundBlurStyle(BlurStyle.Thin)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  needVaultCard() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(28)
        .fontColor([$r('app.color.design_accent')])
      Text($r('app.string.design_need_vault'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_text_primary'))
      Text($r('app.string.design_onboard_create'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_accent'))
        .padding({ left: 22, right: 22, top: 10, bottom: 10 })
        .borderRadius(22)
        .backgroundColor($r('app.color.design_accent_weak'))
        .margin({ top: 6 })
        .onClick(() => {
          this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
            this.showCreateVaultDialog = true;
          });
        })
    }
    .width('100%')
    .padding({ top: 28, bottom: 26, left: 20, right: 20 })
    .borderRadius(20)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 24 })
  }

  @Builder
  searchHitCell(row: DesignSearchRow) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text() {
          Span(row.titleHead)
            .fontColor($r('app.color.design_text_primary'))
          Span(row.titleHit)
            .fontColor($r('app.color.design_accent'))
            .fontWeight(FontWeight.Bold)
          Span(row.titleTail)
            .fontColor($r('app.color.design_text_primary'))
        }
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

        this.itemMoreButton(row.path, false, $r('app.color.design_text_secondary'), true)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text() {
        Span(row.bodyHead)
        Span(row.bodyHit)
          .fontColor($r('app.color.design_text_primary'))
          .fontWeight(FontWeight.Medium)
        Span(row.bodyTail)
      }
      .fontSize(13)
      .fontColor($r('app.color.design_text_secondary'))
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(18)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .gestureModifier(this.longPressFor(row.path, false))
    .onClick(() => {
      this.handleCardTap(() => {
        this.openWorkspace({ 'openPath': row.path });
      });
    })
  }

  // ==================== 图谱页 ====================

  @Builder
  graphPage() {
    Column() {
      Scroll(this.graphPageScroller) {
        Column({ space: 10 }) {
          Row() {
            Text($r('app.string.design_graph_source'))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.design_text_primary'))
              .layoutWeight(1)
          }
          .width('100%')

          if (this.vm.currentVault.name.length > 0) {
            Text($r('app.string.design_graph_scope', this.vm.currentVault.name,
              this.vm.vaultGraph.nodes.length))
              .fontSize(12)
              .fontColor($r('app.color.design_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.graphClusterCount > 0 || this.graphOrphanCount > 0) {
            Text($r('app.string.design_graph_stats', this.graphClusterCount, this.graphOrphanCount))
              .fontSize(12)
              .fontColor($r('app.color.design_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.vm.vaults.length === 0) {
            this.needVaultCard()
          } else {
            if (this.vm.vaultGraph.nodes.length === 0) {
              Column() {
                Text($r('app.string.design_graph_empty'))
                  .fontSize(13)
                  .fontColor($r('app.color.design_text_secondary'))
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .padding({ top: 40, bottom: 40, left: 24, right: 24 })
              .borderRadius(20)
              .backgroundColor($r('app.color.design_surface_solid'))
              .border({ width: 1, color: $r('app.color.design_stroke') })
            } else {
              // 画布一体绘制：连线、节点、标签均走 Canvas（无组件层标签，
              // 捏合缩放只触发重绘，不触发任何 ArkUI 组件重排）
              Stack({ alignContent: Alignment.TopEnd }) {
                Canvas(this.canvasContext)
                  .width('100%')
                  .height(this.graphCanvasHeightVp)
                  .onReady(() => {
                    this.drawGraph();
                  })
                  .onTouch((event: TouchEvent) => {
                    this.handleGraphTouch(event);
                  })
                  // 互斥手势组：单指平移（放大后拖图 / 未放大滚页面）与双指捏合
                  .gesture(GestureGroup(GestureMode.Exclusive,
                    PanGesture({ fingers: 1 })
                      .onActionStart((event: GestureEvent) => {
                        this.graphPanBaseXVp = this.graphOffsetXVp;
                        this.graphPanBaseYVp = this.graphOffsetYVp;
                        this.graphPanLastYVp = 0;
                        if (this.graphScale > 1) {
                          this.graphInteracting = true;
                        }
                      })
                      .onActionUpdate((event: GestureEvent) => {
                        if (this.graphScale > 1) {
                          // 已放大：单指直接平移图谱
                          this.graphOffsetXVp = this.clampGraphOffset(
                            this.graphPanBaseXVp + event.offsetX,
                            this.graphCanvasWidthVp, this.graphScale);
                          this.graphOffsetYVp = this.clampGraphOffset(
                            this.graphPanBaseYVp + event.offsetY,
                            this.graphCanvasHeightVp, this.graphScale);
                          this.requestGraphDraw();
                        } else {
                          // 未放大：单指拖动回落为页面滚动
                          const deltaYVp: number = event.offsetY - this.graphPanLastYVp;
                          this.graphPanLastYVp = event.offsetY;
                          if (Math.abs(deltaYVp) > 0.01) {
                            this.graphPageScroller.scrollBy(0, -deltaYVp);
                          }
                        }
                      })
                      .onActionEnd(() => {
                        if (this.graphInteracting) {
                          this.graphInteracting = false;
                          this.drawGraph();
                        }
                      }),
                    PinchGesture({ fingers: 2 })
                  ))
                  .onClick((event: ClickEvent) => {
                    this.handleGraphClick(event);
                  })
                this.graphZoomControls()
              }
              .width('100%')
              .height(this.graphCanvasHeightVp)
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                const widthVp: number = Number(newArea.width);
                if (Math.abs(widthVp - this.graphCanvasWidthVp) > 0.5) {
                  this.graphCanvasWidthVp = widthVp;
                  this.rebuildGraphLayout();
                }
              })
            }
          }

          Text($r('app.string.design_graph_hint'))
            .fontSize(12)
            .fontColor($r('app.color.design_text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({
          left: BAR_SIDE_VP,
          right: BAR_SIDE_VP,
          top: 4,
          bottom: CAPSULE_HEIGHT_VP + BAR_BOTTOM_VP + this.bottomInset + 24
        })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset + 16 })
  }

  /** 图谱缩放控件组（画布右上角悬浮）：放大 / 缩小 / 复位。 */
  @Builder
  graphZoomControls() {
    Column({ space: 8 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(15)
          .fontColor([$r('app.color.design_text_primary')])
      }
      .width(34)
      .height(34)
      .borderRadius(17)
      .backgroundColor($r('app.color.design_elevated'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 12, color: $r('app.color.design_shadow'), offsetY: 4 })
      .onClick(() => {
        this.zoomGraphBy(GRAPH_ZOOM_STEP);
      })

      Stack() {
        SymbolGlyph($r('sys.symbol.minus'))
          .fontSize(15)
          .fontColor([$r('app.color.design_text_primary')])
      }
      .width(34)
      .height(34)
      .borderRadius(17)
      .backgroundColor($r('app.color.design_elevated'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 12, color: $r('app.color.design_shadow'), offsetY: 4 })
      .onClick(() => {
        this.zoomGraphBy(1 / GRAPH_ZOOM_STEP);
      })

      Stack() {
        SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
          .fontSize(15)
          .fontColor([$r('app.color.design_text_primary')])
      }
      .width(34)
      .height(34)
      .borderRadius(17)
      .backgroundColor($r('app.color.design_elevated'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 12, color: $r('app.color.design_shadow'), offsetY: 4 })
      .onClick(() => {
        this.resetGraphZoom();
      })
    }
    .margin({ top: 10, right: 10 })
  }

  // ==================== 更多页 ====================

  @Builder
  morePage() {
    Stack({ alignContent: Alignment.Top }) {
      // 底层滚动内容区：向上滚动时穿过顶栏毛玻璃按钮下方
      Scroll() {
        Column({ space: 14 }) {
          // 1. 知识库数据概览四联卡（笔记 / 收藏 / 标签 / 快照）
          this.moreStatsCard()

          // 2. 最近笔记足迹大卡
          if (this.shelfNotes.length > 0) {
            this.moreHistoryCard()
          }

          // 3. 笔记快捷工具分组白卡（今日日记 / 模板库 / 标签管理）
          this.moreToolsGroupCard()

          // 4. 设置与数据管理分组白卡（仓库管理 / WebDAV 同步 / 外观与阅读 / 备份与维护）
          this.moreSettingsGroupCard()
        }
        .width('100%')
        .padding({
          left: BAR_SIDE_VP,
          right: BAR_SIDE_VP,
          top: this.topInset + 64,
          bottom: CAPSULE_HEIGHT_VP + BAR_BOTTOM_VP + this.bottomInset + 24
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 悬浮毛玻璃顶栏：保持简洁标题，不与下方设置卡片重复放置同步 / 设置按钮
      Row() {
        Text($r('app.string.design_tab_more'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.design_text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: BAR_SIDE_VP, right: BAR_SIDE_VP, top: this.topInset + 10, bottom: 12 })
      .backgroundColor($r('app.color.design_glass_bg'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
  }

  /** 更多页卡片 1：知识库四联统计概览（笔记 / 收藏 / 标签 / 快照）。 */
  @Builder
  moreStatsCard() {
    Row() {
      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.doc_plaintext'))
          .fontSize(20)
          .fontColor([$r('app.color.design_accent')])
        Text($r('app.string.more_stat_notes'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .margin({ top: 2 })
        Text(`${this.vm.vaultFiles.length}`)
          .fontSize(12)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.filesSegment = 0;
        this.changeTab(0);
      })

      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(20)
          .fontColor([$r('app.color.design_accent')])
        Text($r('app.string.more_stat_bookmarks'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .margin({ top: 2 })
        Text(`${this.vm.bookmarks.length}`)
          .fontSize(12)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.filesSegment = 1;
        this.changeTab(0);
      })

      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.hash'))
          .fontSize(20)
          .fontColor([$r('app.color.design_accent')])
        Text($r('app.string.more_stat_tags'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .margin({ top: 2 })
        Text(`${this.vm.allTagNames.length}`)
          .fontSize(12)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.openTagSearch();
      })

      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.doc_zipper'))
          .fontSize(20)
          .fontColor([$r('app.color.design_accent')])
        Text($r('app.string.more_stat_backups'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .margin({ top: 2 })
        Text(`${this.vm.backups.length}`)
          .fontSize(12)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.openSettingsSheet(SettingsSheetMode.MAINTENANCE);
      })
    }
    .width('100%')
    .padding({ top: 16, bottom: 16, left: 8, right: 8 })
    .borderRadius(20)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
  }

  /** 更多页卡片 2：最近笔记足迹卡。 */
  @Builder
  moreHistoryCard() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.more_section_history'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.design_text_primary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.design_text_secondary')])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.filesSegment = 2;
        this.changeTab(0);
      })

      ForEach(this.shelfNotes.slice(0, 3), (item: RecentNoteItem) => {
        Row({ space: 12 }) {
          this.miniBookCover(item.path, item.title)

          Column({ space: 4 }) {
            Text(item.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row({ space: 6 }) {
              Text(this.folderBadgeOf(item.path))
                .fontSize(10)
                .fontColor($r('app.color.design_accent'))
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(6)
                .backgroundColor($r('app.color.design_accent_weak'))
              Text(item.path)
                .fontSize(12)
                .fontColor($r('app.color.design_text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          this.itemMoreButton(item.path, false, $r('app.color.design_text_secondary'), false)
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
        .gestureModifier(this.longPressFor(item.path, false))
        .onClick(() => {
          this.handleCardTap(() => {
            this.openWorkspace({ 'openPath': item.path });
          });
        })
      }, (item: RecentNoteItem) => `hist_${item.path}`)
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
  }

  /** 更多页卡片 3：笔记工具分组白卡（今日日记 / 模板库 / 标签管理）。 */
  @Builder
  moreToolsGroupCard() {
    Column() {
      ForEach(this.moreTools, (entry: DesignMoreEntry, index: number) => {
        Column() {
          if (index > 0) {
            Divider()
              .color($r('app.color.design_divider'))
              .margin({ left: 64, right: 16 })
          }
          this.moreListRow(entry)
        }
        .width('100%')
      }, (entry: DesignMoreEntry) => `${entry.keyId}_${this.vm.allTagNames.length}`)
    }
    .width('100%')
    .borderRadius(20)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .clip(true)
  }

  /** 笔记快捷工具入口（仅含笔记创作与标签组织工具）。 */
  @Computed
  get moreTools(): DesignMoreEntry[] {
    return [
      new DesignMoreEntry('m_daily', $r('app.string.design_more_daily'),
        $r('app.string.design_more_daily_sub'), $r('sys.symbol.calendar')),
      new DesignMoreEntry('m_templates', $r('app.string.design_more_templates'),
        $r('app.string.design_more_templates_sub'), $r('sys.symbol.doc_text_on_doc_text')),
      new DesignMoreEntry('m_tags', $r('app.string.design_more_tags'),
        $r('app.string.design_more_tags_sub', this.vm.allTagNames.length), $r('sys.symbol.hash'))
    ];
  }

  /** 更多页卡片 4：设置与数据管理分组白卡（仓库 / 同步 / 外观 / 备份，单一入口互不重复）。 */
  @Builder
  moreSettingsGroupCard() {
    Column() {
      ForEach(this.moreSettings, (entry: DesignMoreEntry, index: number) => {
        Column() {
          if (index > 0) {
            Divider()
              .color($r('app.color.design_divider'))
              .margin({ left: 64, right: 16 })
          }
          this.moreListRow(entry)
        }
        .width('100%')
      }, (entry: DesignMoreEntry) =>
        `${entry.keyId}_${this.vm.currentVault.name}_${this.syncVm.configured}_${this.syncVm.syncing}_${this.syncVm.awaitingConfirmation}_${this.syncVm.status.state}_${this.syncVm.conflicts.length}_${this.syncVm.autoSync}_${this.vm.fontSize}_${this.vm.themeMode}_${this.vm.backups.length}`)
    }
    .width('100%')
    .borderRadius(20)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .clip(true)
  }

  /** 设置与数据管理入口：仓库、WebDAV 同步、外观与阅读、备份与维护。 */
  @Computed
  get moreSettings(): DesignMoreEntry[] {
    return [
      new DesignMoreEntry('m_vaults', $r('app.string.more_service_vaults'),
        $r('app.string.more_vault_current', this.vm.currentVault.name), $r('sys.symbol.folder')),
      new DesignMoreEntry('m_sync', $r('app.string.design_more_sync'),
        this.syncSummaryResource(), $r('sys.symbol.arrow_clockwise')),
      new DesignMoreEntry('m_appearance', $r('app.string.design_more_appearance'),
        this.appearanceSummaryLabel(), $r('sys.symbol.paintpalette')),
      new DesignMoreEntry('m_backup', $r('app.string.design_more_backup'),
        $r('app.string.design_more_backup_sub', this.vm.backups.length), $r('sys.symbol.doc_zipper'))
    ];
  }

  /** 生成「更多 -> WebDAV 同步」卡片的实时状态副标题。 */
  private syncSummaryResource(): Resource {
    if (!this.syncVm.configured) {
      return $r('app.string.design_more_sync_not_configured');
    }
    if (this.syncVm.syncing) {
      return $r('app.string.design_more_sync_syncing');
    }
    if (this.syncVm.awaitingConfirmation) {
      return $r('app.string.design_more_sync_paused');
    }
    if (this.syncVm.conflicts.length > 0 || this.syncVm.status.state === SyncState.CONFLICT) {
      return $r('app.string.design_more_sync_conflict', this.syncVm.conflicts.length);
    }
    if (this.syncVm.status.state === SyncState.FAILED) {
      return $r('app.string.design_more_sync_failed');
    }
    if (this.syncVm.autoSync) {
      return $r('app.string.design_more_sync_auto_on');
    }
    return $r('app.string.design_more_sync_configured');
  }

  /** 生成外观与阅读列表项的当前配置摘要。 */
  private appearanceSummaryLabel(): Resource {
    if (this.vm.themeMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      return $r('app.string.design_more_appearance_value_light', this.vm.fontSize);
    }
    if (this.vm.themeMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      return $r('app.string.design_more_appearance_value_dark', this.vm.fontSize);
    }
    return $r('app.string.design_more_appearance_value_system', this.vm.fontSize);
  }

  @Builder
  moreListRow(entry: DesignMoreEntry) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph(entry.symbol)
          .fontSize(20)
          .fontColor([$r('app.color.design_accent')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.design_elevated'))

      Column({ space: 2 }) {
        Text(entry.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
        Text(entry.sub)
          .fontSize(12)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.design_text_secondary')])
        .opacity(0.6)
    }
    .width('100%')
    .padding(14)
    .onClick(() => {
      this.onMoreEntry(entry.keyId);
    })
  }

  // ==================== FAB 气泡菜单 ====================

  @Builder
  fabMenuOverlay() {
    // 全屏透明容器：空白区点击穿透到遮罩，菜单靠 padding 定位在 FAB 上方
    Column() {
      Column({ space: 8 }) {
        ForEach(this.bubbleActions, (action: DesignBubbleAction, index: number) => {
          Row({ space: 10 }) {
            SymbolGlyph(action.symbol)
              .fontSize(18)
              .fontColor([$r('app.color.design_accent')])
            Text(action.label)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_text_primary'))
          }
          .padding({ left: 16, right: 18, top: 10, bottom: 10 })
          .borderRadius(22)
          .backgroundColor($r('app.color.design_glass_bg'))
          .backgroundBlurStyle(BlurStyle.Regular)
          .border({ width: 1, color: $r('app.color.design_glass_stroke') })
          .shadow({ radius: 16, color: $r('app.color.design_shadow'), offsetY: 6 })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
            .animation({ delay: index * 40, curve: curves.springMotion(0.4, 0.8) }))
          .onClick(() => {
            this.onBubbleAction(action.keyId);
          })
        }, (action: DesignBubbleAction) => action.keyId)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.End)
    .padding({
      right: BAR_SIDE_VP,
      bottom: BAR_BOTTOM_VP + this.bottomInset + FAB_SIZE_VP + BAR_GAP_VP + 8
    })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // ==================== 快速笔记半模态 ====================

  @Builder
  editorSheet() {
    Column() {
      // 顶部抓手
      Column() {
      }
      .width(36)
      .height(4)
      .borderRadius(2)
      .backgroundColor($r('app.color.design_divider'))
      .margin({ top: 10, bottom: 14 })

      // 标题行：取消 / 标题 / 保存
      Row() {
        Text($r('app.string.design_editor_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.design_text_primary'))
          .layoutWeight(1)
        Text($r('app.string.design_editor_cancel'))
          .fontSize(14)
          .fontColor($r('app.color.design_text_secondary'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.closeQuickEditor();
          })
        Text($r('app.string.design_editor_save'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_accent'))
          .padding({ left: 16, right: 16, top: 7, bottom: 7 })
          .borderRadius(18)
          .backgroundColor($r('app.color.design_accent_weak'))
          .onClick(() => {
            this.saveQuickEditor();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 2, right: 0 })

      // 标题输入
      TextInput({ text: this.draftTitle, placeholder: $r('app.string.design_editor_title_hint') })
        .width('100%')
        .height(48)
        .margin({ top: 10 })
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .backgroundColor($r('app.color.design_elevated'))
        .placeholderColor($r('app.color.design_text_secondary'))
        .placeholderFont({ size: 15 })
        .fontSize(15)
        .fontColor($r('app.color.design_text_primary'))
        .caretColor($r('app.color.design_accent'))
        .onChange((value: string) => {
          this.draftTitle = value;
        })

      // 正文输入
      TextArea({ text: this.draftBody, placeholder: $r('app.string.design_editor_body_hint') })
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 10 })
        .padding(14)
        .borderRadius(14)
        .backgroundColor($r('app.color.design_elevated'))
        .placeholderColor($r('app.color.design_text_secondary'))
        .placeholderFont({ size: 14 })
        .fontSize(14)
        .fontColor($r('app.color.design_text_primary'))
        .caretColor($r('app.color.design_accent'))
        .constraintSize({ minHeight: 120 })
        .onChange((value: string) => {
          this.draftBody = value;
        })

      // Markdown 语法插入条（自动换行平铺，避免窄屏或大字号下横向溢出）
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.insertChips, (chip: DesignInsertChip) => {
          Row({ space: 6 }) {
            SymbolGlyph(chip.symbol)
              .fontSize(15)
              .fontColor([$r('app.color.design_accent')])
            Text(chip.label)
              .fontSize(13)
              .fontColor($r('app.color.design_text_secondary'))
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor($r('app.color.design_elevated'))
          .border({ width: 1, color: $r('app.color.design_stroke') })
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.draftBody = this.draftBody + chip.insertText;
          })
        }, (chip: DesignInsertChip) => chip.keyId)
      }
      .width('100%')
      .margin({ top: 12, bottom: 4 })
    }
    .width('100%')
    .height('76%')
    .padding({ left: BAR_SIDE_VP, right: BAR_SIDE_VP, bottom: Math.max(this.bottomInset, 14) })
    .backgroundColor($r('app.color.design_surface_solid'))
    .borderRadius({ topLeft: 28, topRight: 28 })
    .transition(TransitionEffect.translate({ y: '100%' })
      .animation({ duration: 360, curve: curves.springMotion(0.42, 0.86) }))
  }

  // ==================== 遮罩 ====================

  @Builder
  overlayScrim(onTap: () => void) {
    Column() {
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.design_dim'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Friction }))
    .onClick(() => {
      onTap();
    })
  }

  // ==================== 私有逻辑 ====================

  /** 滑块指示器 x 坐标（vp）：页签槽位 + 手势偏移换算，带边界收敛。 */
  @Computed
  get sliderXVp(): number {
    const slotVp: number = this.capsuleWidthVp / this.tabDefs.length;
    if (slotVp <= 0 || this.swiperWidthVp <= 0) {
      return 0;
    }
    let xVp: number = slotVp * this.currentTabIndex + (slotVp - SLIDER_WIDTH_VP) / 2
      - (this.swipeOffsetVp / this.swiperWidthVp) * slotVp;
    const maxXVp: number = this.capsuleWidthVp - SLIDER_WIDTH_VP;
    if (xVp < 0) {
      xVp = 0;
    }
    if (xVp > maxXVp) {
      xVp = maxXVp;
    }
    return xVp;
  }

  /** 是否已有搜索条件（关键词或选中标签）。 */
  @Computed
  get hasSearched(): boolean {
    return this.searchKeyword.trim().length > 0 || this.searchVm.activeTag.length > 0;
  }

  /** 搜索结果计数文案。 */
  @Computed
  get searchCountLabel(): ResourceStr {
    if (this.searchRows.length > 0) {
      return $r('app.string.design_search_result_count', this.searchRows.length);
    }
    return $r('app.string.design_search_no_result');
  }

  /** 读取系统避让区：状态栏与底部导航条高度（窗口为全屏布局，需手动避让）。 */
  private loadWindowInsets(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    window.getLastWindow(context).then((win: window.Window) => {
      const system = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = this.getUIContext().px2vp(system.topRect.height);
      this.bottomInset = this.getUIContext().px2vp(nav.bottomRect.height);
      // 订阅键盘高度变化：键盘弹出时按高度抬升编辑区，使编辑工具栏紧贴键盘上沿。
      this.mainWindow = win;
      win.on('keyboardHeightChange', this.keyboardCallback);
    }).catch((error: BusinessError) => {
      LOG.error(`load window insets failed, code=${error.code}, message=${error.message}`);
    });
  }

  /** 切换页签：驱动 Swiper 并让滑块弹性滑向目标。 */
  private changeTab(index: number): void {
    if (index === this.currentTabIndex) {
      return;
    }
    this.swiperController.changeIndex(index, true);
    this.springIndicatorTo(index);
  }

  /** 滑块弹性归位：springMotion 物理弹簧曲线。 */
  private springIndicatorTo(targetIndex: number): void {
    const clamped: number = Math.max(0, Math.min(this.tabDefs.length - 1, targetIndex));
    this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 0.85) }, () => {
      this.currentTabIndex = clamped;
      this.swipeOffsetVp = 0;
      this.indicatorScale = 1;
    });
  }

  /** 打开页内工作台子视图：处理携带参数后切换 viewMode（无 router 跳转）。 */
  private openWorkspace(params: Record<string, Object>): void {
    const openPathRaw: Object | undefined = params['openPath'];
    const openPath: string = typeof openPathRaw === 'string' ? openPathRaw : '';
    if (openPath.length > 0) {
      this.vm.openNote(openPath);
    }
    // 启动动作（templates 等）经 launchAction 传入工作台，由其在挂载时消费。
    const actionRaw: Object | undefined = params['action'];
    this.workspaceLaunchAction = typeof actionRaw === 'string' ? actionRaw : '';
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => {
      this.viewMode = DesignViewMode.WORKSPACE;
    });
  }

  /** 退出工作台返回首页：复位键盘态与启动动作并恢复会话（仓库/笔记/图谱/搜索）。 */
  private exitWorkspace(): void {
    this.setEditorKeyboardMode(false);
    this.workspaceLaunchAction = '';
    this.homeInitialTabIndex = this.currentTabIndex;
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => {
      this.viewMode = DesignViewMode.HOME;
    });
    this.refreshAfterReturn();
  }

  /**
   * 应用键盘避让策略。
   * 窄屏（底部悬浮导航栏形态）下，编辑区进入键盘交互态时改用 NONE 避让：
   * 页面不被压缩，仅编辑工具栏贴在键盘上沿；其余场景保持 RESIZE
   * （弹窗与浮层不会被键盘遮挡）。
   */
  private applyKeyboardAvoidMode(): void {
    const useNone: boolean = this.noneAvoidActive();
    const mode: KeyboardAvoidMode = useNone ? KeyboardAvoidMode.NONE : KeyboardAvoidMode.RESIZE;
    this.getUIContext().setKeyboardAvoidMode(mode);
  }

  /** NONE 避让是否生效（页面不被压缩，需手动让出键盘高度）。 */
  private noneAvoidActive(): boolean {
    return this.editorKeyboardMode && this.viewMode === DesignViewMode.WORKSPACE && !this.isWide;
  }

  /** 首页路由参数是否已处理（防重入）。 */
  private launchHandled: boolean = false;

  /**
   * 处理外部启动路由参数：
   * openPath 打开笔记（进工作台）、expandPath 在首页目录原地定位、
   * action 打开指定面板（templates / vaults / settings）。
   */
  private handleLaunchParams(): void {
    if (this.launchHandled) {
      return;
    }
    const params: Record<string, Object> | undefined =
      router.getParams() as Record<string, Object> | undefined;
    if (params === undefined) {
      return;
    }
    this.launchHandled = true;
    const openPathRaw: Object | undefined = params['openPath'];
    const openPath: string = typeof openPathRaw === 'string' ? openPathRaw : '';
    if (openPath.length > 0) {
      this.openWorkspace({ 'openPath': openPath });
      return;
    }
    const expandPathRaw: Object | undefined = params['expandPath'];
    const expandPath: string = typeof expandPathRaw === 'string' ? expandPathRaw : '';
    if (expandPath.length > 0) {
      this.filesSegment = 3;
      this.currentFolderPath = expandPath;
      return;
    }
    const actionRaw: Object | undefined = params['action'];
    const action: string = typeof actionRaw === 'string' ? actionRaw : '';
    if (action === 'templates') {
      this.openWorkspace({ 'action': 'templates' });
      return;
    }
    if (action === 'vaults') {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.showVaultManager = true;
      });
      return;
    }
    if (action === 'settings') {
      this.openSettingsSheet(SettingsSheetMode.APPEARANCE);
    }
  }

  /** 消费桌面长按快捷方式注入的动作（quick_note / daily_note / search）。 */
  private consumeShortcutAction(): void {
    const action: string = AbilityContextHolder.pendingShortcutAction;
    if (action.length === 0) {
      return;
    }
    AbilityContextHolder.pendingShortcutAction = '';
    if (action === 'quick_note') {
      if (this.viewMode === DesignViewMode.WORKSPACE) {
        this.exitWorkspace();
      }
      this.openQuickEditor('');
      return;
    }
    if (action === 'daily_note') {
      this.openDailyAndJump();
      return;
    }
    if (action === 'search') {
      if (this.viewMode === DesignViewMode.WORKSPACE) {
        this.exitWorkspace();
      }
      this.changeTab(1);
    }
  }

  /** 消费文件管理器或其他应用传入的待打开外部 Markdown URI（冷/热启动共用）。 */
  private consumePendingOpenUri(): void {
    const uri: string = AbilityContextHolder.pendingOpenUri;
    if (uri.length === 0) {
      return;
    }
    AbilityContextHolder.pendingOpenUri = '';
    this.pendingExternalImport = false;
    this.pendingExternalEditAfter = false;
    const openExternal = (): void => {
      this.dismissAllModalsForExternal();
      const ok: boolean = this.vm.openExternalUri(uri);
      if (!ok) {
        this.toast($r('app.string.msg_external_read_failed'));
        return;
      }
      if (this.viewMode !== DesignViewMode.WORKSPACE) {
        this.openWorkspace({});
      }
    };
    if (this.vm.editMode && this.vm.draftBuffer !== this.vm.noteContent &&
      this.vm.selectedPath.length > 0) {
      this.setEditorKeyboardMode(false);
      this.vm.saveDraft().then((): void => {
        this.syncNowIfAuto();
        openExternal();
      });
      return;
    }
    this.setEditorKeyboardMode(false);
    openExternal();
  }

  /** 打开外部文件前先收起可能遮挡正文的首页弹层/弹窗。 */
  private dismissAllModalsForExternal(): void {
    this.showFabMenu = false;
    this.showQuickEditor = false;
    this.showSyncPanel = false;
    this.showVaultManager = false;
    this.settingsSheetMode = SettingsSheetMode.NONE;
    this.showCreateVaultDialog = false;
    this.homeMenuPath = '';
    this.homeDialogKind = DesignDialogKind.NONE;
  }

  /** 处理外部只读预览导入仓库请求；若尚无仓库则先弹出建库对话框。 */
  private handleImportExternalRequest(editAfter: boolean): void {
    if (!this.vm.isExternalMode) {
      return;
    }
    if (this.vm.vaults.length === 0) {
      this.pendingExternalImport = true;
      this.pendingExternalEditAfter = editAfter;
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.showCreateVaultDialog = true;
      });
      return;
    }
    this.finishImportExternal(editAfter);
  }

  /** 执行外部预览文件落盘导入，并按需进入编辑态。 */
  private async finishImportExternal(editAfter: boolean): Promise<void> {
    const importedPath: string = await this.vm.importExternalToVault();
    if (importedPath.length === 0) {
      this.toast($r('app.string.msg_create_failed'));
      return;
    }
    this.toast($r('app.string.msg_external_imported', importedPath));
    this.syncNowIfAuto();
    if (editAfter) {
      this.vm.startEdit();
    }
  }

  /** 关闭外部 Markdown 只读预览，回到首页或恢复既有会话。 */
  private closeExternalPreview(): void {
    this.pendingExternalImport = false;
    this.pendingExternalEditAfter = false;
    this.vm.closeNote();
    this.exitWorkspace();
  }

  /** 进入 / 退出编辑区键盘交互态。 */
  private setEditorKeyboardMode(active: boolean): void {
    if (this.editorKeyboardMode === active) {
      return;
    }
    this.editorKeyboardMode = active;
    this.applyKeyboardAvoidMode();
  }

  /** 启动后首次同时就绪时触发一次轻量无感同步。 */
  private maybeTriggerLaunchSync(): void {
    if (!this.initReady || !this.syncReady) {
      return;
    }
    this.syncVm.requestPassiveSync(this.vm.currentVault);
  }

  /** 自动同步开启时防抖合并触发同步（保存 / 新建 / 删除后调用，不丢连续编辑）。 */
  private syncNowIfAuto(): void {
    if (!this.syncVm.autoSync || this.syncVm.serverUrl.length === 0) {
      return;
    }
    this.syncVm.scheduleAutoSync(this.vm.currentVault);
  }

  /** 依据自动同步开关重建周期同步定时器。 */
  private restartAutoSyncTimer(): void {
    this.stopAutoSyncTimer();
    if (!this.syncVm.autoSync || this.syncVm.serverUrl.length === 0) {
      return;
    }
    this.autoSyncTimer = setInterval((): void => {
      this.syncNowIfAuto();
    }, DesignIndex.AUTO_SYNC_INTERVAL_MS);
  }

  private stopAutoSyncTimer(): void {
    if (this.autoSyncTimer >= 0) {
      clearInterval(this.autoSyncTimer);
      this.autoSyncTimer = -1;
    }
  }

  /** FAB 气泡菜单开关。 */
  private toggleFabMenu(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
      this.showFabMenu = !this.showFabMenu;
    });
  }

  /** 打开快速笔记半模态（可预填标题）。 */
  private openQuickEditor(prefillTitle: string): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => {
      this.draftTitle = prefillTitle;
      this.draftBody = '';
      this.showFabMenu = false;
      this.showQuickEditor = true;
    });
  }

  /** 关闭快速笔记半模态。 */
  private closeQuickEditor(): void {
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => {
      this.showQuickEditor = false;
    });
  }

  /** 保存快速笔记：新建笔记并跳转工作台。 */
  private saveQuickEditor(): void {
    const title: string = this.draftTitle;
    const body: string = this.draftBody;
    this.closeQuickEditor();
    if (title.trim().length === 0 && body.trim().length === 0) {
      return;
    }
    this.vm.createQuickNote(title, body).then((path: string): void => {
      if (path.length === 0) {
        promptAction.showToast({ message: $r('app.string.msg_create_failed') });
        return;
      }
      promptAction.showToast({ message: $r('app.string.design_editor_saved') });
      this.openWorkspace({ 'openPath': path });
    });
  }

  /** 气泡菜单动作分发。 */
  private onBubbleAction(keyId: string): void {
    this.toggleFabMenu();
    if (this.vm.vaults.length === 0) {
      this.openWorkspace({});
      return;
    }
    if (keyId === 'bubble_daily') {
      this.openDailyAndJump();
      return;
    }
    if (keyId === 'bubble_note') {
      this.createNoteAndJump();
      return;
    }
    if (keyId === 'bubble_template') {
      this.openWorkspace({ 'action': 'templates' });
      return;
    }
  }

  /** 打开今天的日记并跳转工作台。 */
  private openDailyAndJump(): void {
    if (this.vm.vaults.length === 0) {
      this.openWorkspace({});
      return;
    }
    this.vm.openDailyNote().then((ok: boolean): void => {
      if (ok) {
        this.openWorkspace({ 'openPath': this.vm.selectedPath });
      }
    });
  }

  /** 新建空白笔记并跳转工作台。 */
  private createNoteAndJump(): void {
    if (this.vm.vaults.length === 0) {
      this.openWorkspace({});
      return;
    }
    this.vm.createNote().then((): void => {
      this.openWorkspace({ 'openPath': this.vm.selectedPath });
    });
  }

  /** 带摩擦力曲线动效打开外观 / 维护设置弹窗。 */
  private openSettingsSheet(mode: number): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
      this.settingsSheetMode = mode;
    });
  }

  /** 更多页工具与设置行入口分发。 */
  private onMoreEntry(keyId: string): void {
    if (keyId === 'm_daily') {
      this.openDailyAndJump();
      return;
    }
    if (keyId === 'm_templates') {
      this.openWorkspace({ 'action': 'templates' });
      return;
    }
    if (keyId === 'm_tags') {
      this.openTagSearch();
      return;
    }
    if (keyId === 'm_vaults') {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.showVaultManager = true;
      });
      return;
    }
    if (keyId === 'm_sync') {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.showSyncPanel = true;
      });
      return;
    }
    if (keyId === 'm_appearance') {
      this.openSettingsSheet(SettingsSheetMode.APPEARANCE);
      return;
    }
    if (keyId === 'm_backup') {
      this.openSettingsSheet(SettingsSheetMode.MAINTENANCE);
      return;
    }
  }

  /** 切到搜索页并以标签模式展示（标签管理入口）。 */
  private openTagSearch(): void {
    this.changeTab(1);
    if (this.vm.currentVault.id > 0) {
      this.searchVm.setMode(this.vm.currentVault.id, 1).then((): void => {
        this.searchKeyword = this.searchVm.keyword;
        this.rebuildSearchRows();
      });
    }
  }

  /** 工作台上报的标签点击：回首页搜索页并定位该标签下的笔记。 */
  private openWorkspaceTagSearch(tag: string): void {
    this.changeTab(1);
    if (this.vm.currentVault.id > 0) {
      this.searchVm.setMode(this.vm.currentVault.id, 1).then((): void => {
        this.searchVm.selectTag(this.vm.currentVault.id, tag).then((): void => {
          this.searchKeyword = this.searchVm.keyword;
          this.rebuildSearchRows();
        });
      });
    }
  }

  /** 搜索输入防抖。 */
  private onSearchKeywordChange(value: string): void {
    this.searchKeyword = value;
    if (this.searchDebounceId >= 0) {
      clearTimeout(this.searchDebounceId);
    }
    this.searchDebounceId = setTimeout((): void => {
      this.runSearch();
    }, SEARCH_DEBOUNCE_MS);
  }

  /** 清空搜索并复位结果。 */
  private clearSearch(): void {
    if (this.searchDebounceId >= 0) {
      clearTimeout(this.searchDebounceId);
      this.searchDebounceId = -1;
    }
    this.searchKeyword = '';
    this.runSearch();
  }

  /** 执行搜索并重建高亮行。 */
  private runSearch(): void {
    if (this.vm.currentVault.id <= 0) {
      return;
    }
    this.searchVm.search(this.vm.currentVault.id, this.searchKeyword).then((): void => {
      this.rebuildSearchRows();
    });
  }

  /** 切换搜索模式（0 全文 / 1 标签 / 2 属性）。 */
  private switchSearchMode(mode: number): void {
    if (this.vm.currentVault.id <= 0) {
      return;
    }
    if (this.searchDebounceId >= 0) {
      clearTimeout(this.searchDebounceId);
      this.searchDebounceId = -1;
    }
    this.searchVm.setMode(this.vm.currentVault.id, mode).then((): void => {
      this.searchKeyword = this.searchVm.keyword;
      this.rebuildSearchRows();
    });
  }

  /** 选中一个标签，展示该标签下的笔记。 */
  private selectTagChip(tag: string): void {
    if (this.vm.currentVault.id <= 0) {
      return;
    }
    this.searchVm.selectTag(this.vm.currentVault.id, tag).then((): void => {
      this.rebuildSearchRows();
    });
  }

  /** 把命中结果按关键词拆分为头/命中/尾三段高亮行。 */
  private rebuildSearchRows(): void {
    const rows: DesignSearchRow[] = [];
    const keyword: string = this.searchVm.keyword.trim();
    for (const hit of this.searchVm.hits) {
      const titleParts: string[] = splitHighlight(hit.title, keyword);
      const rawBody: string = hit.snippet.trim().length > 0 ? hit.snippet : hit.path;
      const snippet: string = rawBody.replace(/\n/g, ' ');
      const bodyParts: string[] = splitHighlight(snippet, keyword);
      rows.push(new DesignSearchRow(`${hit.noteId}-${rows.length}`, hit.path,
        titleParts[0], titleParts[1], titleParts[2],
        bodyParts[0], bodyParts[1], bodyParts[2]));
    }
    this.searchRows = rows;
  }

  /** 从工作台返回：恢复最近会话（仓库/笔记/图谱/搜索）。 */
  private refreshAfterReturn(): void {
    this.vm.restoreSession().then((): void => {
      this.refreshDerivedViews();
    });
  }

  /** 重新构建图谱布局并在需要时刷新搜索结果。 */
  private refreshDerivedViews(): void {
    this.vm.loadVaultGraph().then((): void => {
      this.selectedGraphPath = '';
      this.rebuildGraphLayout();
    });
    if (this.searchVm.searchMode === 1 ||
      this.searchKeyword.trim().length > 0 ||
      this.searchVm.activeTag.length > 0) {
      this.runSearch();
    }
  }

  /** 为首页笔记或目录条目构造统一长按手势修饰器。 */
  private longPressFor(path: string, isDir: boolean): ItemLongPressModifier {
    return new ItemLongPressModifier(
      path,
      isDir,
      (targetPath: string, targetIsDir: boolean): void => {
        if (this.itemLongPressTimer >= 0) {
          clearTimeout(this.itemLongPressTimer);
          this.itemLongPressTimer = -1;
        }
        this.itemLongPressConsumed = true;
        this.openItemMenu(targetPath, targetIsDir);
      },
      (): void => {
        this.scheduleClearLongPressConsumed();
      },
      (): void => {
        this.scheduleClearLongPressConsumed();
      }
    );
  }

  /** 长按抬手后延时清除防误触标志，吞掉长按末尾附带的 click。 */
  private scheduleClearLongPressConsumed(): void {
    if (this.itemLongPressTimer >= 0) {
      clearTimeout(this.itemLongPressTimer);
    }
    this.itemLongPressTimer = setTimeout((): void => {
      this.itemLongPressConsumed = false;
      this.itemLongPressTimer = -1;
    }, 180);
  }

  /** 统一点击守护：刚结束长按时吞掉抬手点击，其余情况正常执行。 */
  private handleCardTap(action: () => void): void {
    if (this.itemLongPressConsumed) {
      this.itemLongPressConsumed = false;
      return;
    }
    action();
  }

  /** 打开首页条目操作面板（供长按与最右侧「更多」按钮共用）。 */
  private openItemMenu(path: string, isDir: boolean): void {
    if (path.length === 0) {
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
      this.homeMenuIsDir = isDir;
      this.homeMenuPath = path;
    });
  }

  /** 打开首页重命名 / 新建子目录 / 移动笔记对话框（不强行进入工作台）。 */
  private openHomeDialog(kind: string, targetPath: string): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
      this.homeDialogTargetPath = targetPath;
      this.homeDialogKind = kind;
    });
  }

  /** 首页确认将笔记移入回收站。 */
  private confirmTrashHomeNote(path: string): void {
    confirmTrashNoteAction(this.vm, path, (): void => {
      this.toast($r('app.string.msg_trash_done'));
      this.onHomeNoteMutated();
    }, (msg: ResourceStr): void => {
      this.toast(msg);
    });
  }

  /** 首页确认将目录及其笔记移入回收站并删除空目录。 */
  private confirmTrashHomeFolder(dirPath: string): void {
    confirmTrashFolderAction(this.vm, dirPath, (): void => {
      if (this.currentFolderPath === dirPath || this.currentFolderPath.startsWith(`${dirPath}/`)) {
        const lastSlash: number = dirPath.lastIndexOf('/');
        this.currentFolderPath = lastSlash > 0 ? dirPath.substring(0, lastSlash) : '';
      }
      this.toast($r('app.string.msg_trash_folder_done'));
      this.onHomeNoteMutated();
    }, (msg: ResourceStr): void => {
      this.toast(msg);
    });
  }

  /** 首页完成增删改移后刷新衍生视图并在开启自动同步时触发同步。 */
  private onHomeNoteMutated(): void {
    this.refreshDerivedViews();
    this.syncNowIfAuto();
  }

  /** 标签分级披露：缩放越小只标枢纽，放大后逐步显示全部（像地图一样渐进披露细节）。 */
  private labelMinDegree(scale: number): number {
    if (scale >= 2.6) {
      return 0;
    }
    if (scale >= 1.6) {
      return 1;
    }
    return this.graphNodeVpList.length > 150 ? 3 : 1;
  }

  /** 按画布实际宽度重算图谱布局（分簇力导向）并重绘。 */
  private rebuildGraphLayout(): void {
    const widthVp: number = this.graphCanvasWidthVp;
    const graph = this.vm.vaultGraph;
    if (widthVp <= 0 || graph.nodes.length === 0) {
      this.graphNodeVpList = [];
      this.graphNodeMap = new Map<string, DesignGraphNodeVp>();
      this.graphEdgeVpList = [];
      this.graphNeighbors = new Map<string, Set<string>>();
      this.graphClusterCount = 0;
      this.graphOrphanCount = 0;
      return;
    }
    // 画布高度随节点数自适应：节点越多画布越高（页面本身可滚动）。
    this.graphCanvasHeightVp = Math.max(GRAPH_CANVAS_HEIGHT_VP,
      Math.min(900, 260 + graph.nodes.length * 1.0));
    const stats: GraphLayoutStats = GraphLayout.compute(graph, widthVp, this.graphCanvasHeightVp);
    this.graphClusterCount = stats.clusters;
    this.graphOrphanCount = stats.orphans;
    if (this.selectedGraphPath.length === 0) {
      for (const node of graph.nodes) {
        if (node.root) {
          this.selectedGraphPath = node.path;
          break;
        }
      }
    }
    // 度数统计 + 邻接表（标签分级 / 聚焦暗化依据）
    const degrees: Map<string, number> = new Map<string, number>();
    const neighbors: Map<string, Set<string>> = new Map<string, Set<string>>();
    for (const edge of graph.edges) {
      degrees.set(edge.from, (degrees.get(edge.from) ?? 0) + 1);
      degrees.set(edge.to, (degrees.get(edge.to) ?? 0) + 1);
      const fromSet: Set<string> | undefined = neighbors.get(edge.from);
      if (fromSet === undefined) {
        neighbors.set(edge.from, new Set<string>([edge.to]));
      } else {
        fromSet.add(edge.to);
      }
      const toSet: Set<string> | undefined = neighbors.get(edge.to);
      if (toSet === undefined) {
        neighbors.set(edge.to, new Set<string>([edge.from]));
      } else {
        toSet.add(edge.from);
      }
    }
    this.graphNeighbors = neighbors;
    const list: DesignGraphNodeVp[] = [];
    const map: Map<string, DesignGraphNodeVp> = new Map<string, DesignGraphNodeVp>();
    for (const node of graph.nodes) {
      const vpNode: DesignGraphNodeVp = new DesignGraphNodeVp(node.path, node.x, node.y,
        node.radius, node.title, node.root, degrees.get(node.path) ?? 0);
      list.push(vpNode);
      map.set(node.path, vpNode);
    }
    this.graphNodeVpList = list;
    this.graphNodeMap = map;
    // 边端点引用列表（绘制免逐帧查 Map）
    const edgeList: DesignGraphEdgeVp[] = [];
    for (const edge of graph.edges) {
      const fromNode: DesignGraphNodeVp | undefined = map.get(edge.from);
      const toNode: DesignGraphNodeVp | undefined = map.get(edge.to);
      if (fromNode === undefined || toNode === undefined) {
        continue;
      }
      edgeList.push(new DesignGraphEdgeVp(fromNode, toNode));
    }
    this.graphEdgeVpList = edgeList;
    // 布局重算后坐标系已变化：复位缩放/平移，避免旧偏移指向错误区域
    this.graphScale = 1;
    this.graphOffsetXVp = 0;
    this.graphOffsetYVp = 0;
    this.graphPrevPinchDist = 0;
    this.drawGraph();
  }

  /** 经 resourceManager 解析 design_* 色板（跟随系统深浅色），供 Canvas 使用。 */
  private paletteColor(name: string): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return DesignPalette.FALLBACK;
    }
    return DesignPalette.color(context.resourceManager, name);
  }

  /**
   * 绘制图谱（画布一体绘制，捏合缩放零组件重排）：
   * - 连线按「活跃 / 普通 / 暗化」三类各自合并成单次描边（数千条边也只有 3 次绘制调用）
   * - 节点圆点按「选中 / 邻居 / 无关」分批填充
   * - 选中即聚焦：无关连线与节点淡出，突出当前笔记的知识邻域（Obsidian 式聚焦）
   * - 标签画布内绘制（描边勾底保证可读），随缩放分级披露 + 视口裁剪
   */
  private drawGraph(): void {
    const ctx: CanvasRenderingContext2D = this.canvasContext;
    const widthVp: number = this.graphCanvasWidthVp;
    if (widthVp <= 0) {
      return;
    }
    this.graphLastDrawMs = Date.now();
    ctx.clearRect(0, 0, widthVp, this.graphCanvasHeightVp);
    if (this.graphNodeVpList.length === 0) {
      return;
    }
    // 色板按当前深浅模式解析
    const accent: string = this.paletteColor('design_accent');
    const elevated: string = this.paletteColor('design_elevated');
    const textSecondary: string = this.paletteColor('design_text_secondary');
    const background: string = this.paletteColor('design_bg');
    const selected: string = this.selectedGraphPath;
    const focusMode: boolean = selected.length > 0;
    const neighborSet: Set<string> | undefined = focusMode ? this.graphNeighbors.get(selected) : undefined;
    // 整体变换：清屏在恒等变换下完成，内容按缩放/平移绘制
    ctx.save();
    ctx.translate(this.graphOffsetXVp, this.graphOffsetYVp);
    ctx.scale(this.graphScale, this.graphScale);
    // 线宽随缩放反向补偿：屏幕厚度恒定，放大后线条不会变粗
    const invScale: number = 1 / this.graphScale;
    // ===== 连线（三类合并描边） =====
    if (focusMode) {
      // 无关连线暗化
      ctx.strokeStyle = DesignPalette.rgba(textSecondary, 0.06);
      ctx.lineWidth = invScale;
      ctx.beginPath();
      for (const edge of this.graphEdgeVpList) {
        if (edge.fromNode.keyId !== selected && edge.toNode.keyId !== selected) {
          ctx.moveTo(edge.fromNode.x, edge.fromNode.y);
          ctx.lineTo(edge.toNode.x, edge.toNode.y);
        }
      }
      ctx.stroke();
      // 选中连线高亮
      ctx.strokeStyle = DesignPalette.rgba(accent, 0.75);
      ctx.lineWidth = 1.6 * invScale;
      ctx.beginPath();
      for (const edge of this.graphEdgeVpList) {
        if (edge.fromNode.keyId === selected || edge.toNode.keyId === selected) {
          ctx.moveTo(edge.fromNode.x, edge.fromNode.y);
          ctx.lineTo(edge.toNode.x, edge.toNode.y);
        }
      }
      ctx.stroke();
    } else {
      ctx.strokeStyle = DesignPalette.rgba(textSecondary, 0.22);
      ctx.lineWidth = 1.1 * invScale;
      ctx.beginPath();
      for (const edge of this.graphEdgeVpList) {
        ctx.moveTo(edge.fromNode.x, edge.fromNode.y);
        ctx.lineTo(edge.toNode.x, edge.toNode.y);
      }
      ctx.stroke();
    }
    // ===== 节点（分批填充） =====
    if (focusMode) {
      // 无关节点淡出
      ctx.fillStyle = DesignPalette.rgba(elevated, 0.35);
      ctx.beginPath();
      for (const node of this.graphNodeVpList) {
        if (node.keyId === selected || (neighborSet !== undefined && neighborSet.has(node.keyId))) {
          continue;
        }
        ctx.moveTo(node.x + node.radiusVp, node.y);
        ctx.arc(node.x, node.y, node.radiusVp, 0, DOUBLE_PI);
      }
      ctx.fill();
      // 邻居节点正常显示
      if (neighborSet !== undefined) {
        ctx.fillStyle = elevated;
        ctx.beginPath();
        for (const node of this.graphNodeVpList) {
          if (node.keyId === selected || !neighborSet.has(node.keyId)) {
            continue;
          }
          ctx.moveTo(node.x + node.radiusVp, node.y);
          ctx.arc(node.x, node.y, node.radiusVp, 0, DOUBLE_PI);
        }
        ctx.fill();
      }
    } else {
      ctx.fillStyle = elevated;
      ctx.beginPath();
      for (const node of this.graphNodeVpList) {
        ctx.moveTo(node.x + node.radiusVp, node.y);
        ctx.arc(node.x, node.y, node.radiusVp, 0, DOUBLE_PI);
      }
      ctx.fill();
    }
    // 选中节点：光晕 + 强调色
    const selectedNode: DesignGraphNodeVp | undefined = this.graphNodeMap.get(selected);
    if (selectedNode !== undefined) {
      ctx.beginPath();
      ctx.fillStyle = DesignPalette.rgba(accent, 0.16);
      ctx.arc(selectedNode.x, selectedNode.y, selectedNode.radiusVp * 1.7, 0, DOUBLE_PI);
      ctx.fill();
      ctx.beginPath();
      ctx.fillStyle = accent;
      ctx.moveTo(selectedNode.x + selectedNode.radiusVp, selectedNode.y);
      ctx.arc(selectedNode.x, selectedNode.y, selectedNode.radiusVp * 1.15, 0, DOUBLE_PI);
      ctx.fill();
    }
    ctx.restore();
    // ===== 标签（屏幕空间绘制：字号恒定不随缩放膨胀，截断缓存跨缩放有效） =====
    // 交互进行中（捏合/平移）省略标签：strokeText 成本高，留到手势结束再补画
    if (!this.graphInteracting) {
      const scale: number = this.graphScale;
      const minDegree: number = this.labelMinDegree(scale);
      const canvasH: number = this.graphCanvasHeightVp;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.lineJoin = 'round';
      let labelCount: number = 0;
      for (const node of this.graphNodeVpList) {
        if (labelCount >= 90) {
          break;
        }
        const isSelected: boolean = node.keyId === selected;
        if (!isSelected && node.degree < minDegree) {
          continue;
        }
        const screenX: number = node.x * scale + this.graphOffsetXVp;
        const screenY: number = (node.y + node.radiusVp) * scale + this.graphOffsetYVp + 6;
        if (screenX < -60 || screenX > widthVp + 60 ||
          screenY < -16 || screenY > canvasH + 16) {
          continue;
        }
        // 短标签截断（首帧计算后缓存）
        if (node.shortLabel.length === 0) {
          ctx.font = '400 11px sans-serif';
          node.shortLabel = GraphLayoutStats.clipLabel(ctx, node.label, 84);
        }
        ctx.font = isSelected ? '600 12px sans-serif' : '400 11px sans-serif';
        ctx.lineWidth = 3;
        ctx.strokeStyle = DesignPalette.rgba(background, 0.85);
        ctx.strokeText(node.shortLabel, screenX, screenY);
        ctx.fillStyle = isSelected ? accent : textSecondary;
        ctx.fillText(node.shortLabel, screenX, screenY);
        labelCount += 1;
      }
    }
  }

  /** 交互期节流重绘：触摸事件频率高于刷新率，一帧内只画一次。 */
  private requestGraphDraw(): void {
    const now: number = Date.now();
    if (now - this.graphLastDrawMs < 16) {
      return;
    }
    this.drawGraph();
  }

  /** 点击画布：命中未选中节点则高亮；命中已选中节点则在工作台打开。 */
  private handleGraphClick(event: ClickEvent): void {
    // 捏合刚结束的短时间内抑制误触点击
    if (Date.now() - this.graphPinchEndTime < GRAPH_PINCH_COOLDOWN_MS) {
      return;
    }
    // 逆变换：屏幕坐标 → 图谱世界坐标
    const xVp: number = (event.x - this.graphOffsetXVp) / this.graphScale;
    const yVp: number = (event.y - this.graphOffsetYVp) / this.graphScale;
    let hitPath: string = '';
    let bestDistance: number = 1e9;
    for (const node of this.graphNodeVpList) {
      const dxVp: number = node.x - xVp;
      const dyVp: number = node.y - yVp;
      const distance: number = dxVp * dxVp + dyVp * dyVp;
      // 命中垫量随缩放反向补偿，保证指尖命中区域视觉恒定
      const hitRadiusVp: number = node.radiusVp + 12 / this.graphScale;
      if (distance <= hitRadiusVp * hitRadiusVp && distance < bestDistance) {
        bestDistance = distance;
        hitPath = node.keyId;
      }
    }
    if (hitPath.length === 0) {
      return;
    }
    if (hitPath === this.selectedGraphPath) {
      this.openWorkspace({ 'openPath': hitPath });
      return;
    }
    this.selectedGraphPath = hitPath;
    this.drawGraph();
  }

  /**
   * 画布原始触摸：双指捏合缩放 + 双指拖动平移（锚点数学保证指下内容跟手）。
   * 单指拖动由 PanGesture 处理（放大后平移图谱 / 未放大滚动页面）。
   */
  private handleGraphTouch(event: TouchEvent): void {
    const touches: TouchObject[] = event.touches;
    if (touches.length < 2) {
      // 有捏合在进行时抬指/取消：记录结束时刻用于抑制误触点击，并补画标签
      if (this.graphPrevPinchDist > 0 &&
        (event.type === TouchType.Up || event.type === TouchType.Cancel)) {
        this.graphPinchEndTime = Date.now();
        this.graphInteracting = false;
        this.drawGraph();
      }
      this.graphPrevPinchDist = 0;
      return;
    }
    const first: TouchObject = touches[0];
    const second: TouchObject = touches[1];
    const dxVp: number = second.x - first.x;
    const dyVp: number = second.y - first.y;
    const distVp: number = Math.sqrt(dxVp * dxVp + dyVp * dyVp);
    const midXVp: number = (first.x + second.x) / 2;
    const midYVp: number = (first.y + second.y) / 2;
    // 基线缺失（双指刚按下 / 抬指后首帧）：只重建基线，不产生跳变
    if (event.type !== TouchType.Move || this.graphPrevPinchDist <= 0 || distVp <= 0) {
      this.graphPrevPinchDist = distVp;
      this.graphPrevMidXVp = midXVp;
      this.graphPrevMidYVp = midYVp;
      return;
    }
    const oldScale: number = this.graphScale;
    let newScale: number = oldScale * (distVp / this.graphPrevPinchDist);
    if (newScale > GRAPH_MAX_SCALE) {
      newScale = GRAPH_MAX_SCALE;
    }
    if (newScale < 1) {
      newScale = 1;
    }
    // 锚点：保持指下内容不动（同时覆盖缩放与平移）
    const worldX: number = (this.graphPrevMidXVp - this.graphOffsetXVp) / oldScale;
    const worldY: number = (this.graphPrevMidYVp - this.graphOffsetYVp) / oldScale;
    this.graphScale = newScale;
    this.graphOffsetXVp = this.clampGraphOffset(midXVp - worldX * newScale,
      this.graphCanvasWidthVp, newScale);
    this.graphOffsetYVp = this.clampGraphOffset(midYVp - worldY * newScale,
      this.graphCanvasHeightVp, newScale);
    this.graphPrevPinchDist = distVp;
    this.graphPrevMidXVp = midXVp;
    this.graphPrevMidYVp = midYVp;
    // 捏合进行中：节流重绘（省略标签），手势结束再补画
    this.graphInteracting = true;
    this.requestGraphDraw();
  }

  /** 缩放按钮：围绕画布中心缩放一步。 */
  private zoomGraphBy(factor: number): void {
    const oldScale: number = this.graphScale;
    let newScale: number = oldScale * factor;
    if (newScale > GRAPH_MAX_SCALE) {
      newScale = GRAPH_MAX_SCALE;
    }
    if (newScale < 1) {
      newScale = 1;
    }
    if (newScale === oldScale) {
      return;
    }
    const centerXVp: number = this.graphCanvasWidthVp / 2;
    const centerYVp: number = this.graphCanvasHeightVp / 2;
    const worldX: number = (centerXVp - this.graphOffsetXVp) / oldScale;
    const worldY: number = (centerYVp - this.graphOffsetYVp) / oldScale;
    this.graphScale = newScale;
    this.graphOffsetXVp = this.clampGraphOffset(centerXVp - worldX * newScale,
      this.graphCanvasWidthVp, newScale);
    this.graphOffsetYVp = this.clampGraphOffset(centerYVp - worldY * newScale,
      this.graphCanvasHeightVp, newScale);
    this.drawGraph();
  }

  /** 复位缩放与平移。 */
  private resetGraphZoom(): void {
    if (this.graphScale === 1 && this.graphOffsetXVp === 0 && this.graphOffsetYVp === 0) {
      return;
    }
    this.graphScale = 1;
    this.graphOffsetXVp = 0;
    this.graphOffsetYVp = 0;
    this.graphPrevPinchDist = 0;
    this.drawGraph();
  }

  /** 平移偏移钳制：缩放后的内容不脱离画布视口。 */
  private clampGraphOffset(value: number, extentVp: number, scale: number): number {
    const minVp: number = extentVp * (1 - scale);
    if (value > 0) {
      return 0;
    }
    if (value < minVp) {
      return minVp;
    }
    return value;
  }

  /** 从文件选择器导入 PEM 证书。 */
  private async pickCertFile(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.pem', '.crt', '.cer'];
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      const ok: boolean = await this.syncVm.importCert(uris[0]);
      if (!ok) {
        promptAction.showToast({ message: $r('app.string.msg_cert_import_failed') });
      }
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`pick cert failed, code=${err.code}, message=${err.message}`);
    }
  }

  /** 新建仓库对话框确认：若同时启用 WebDAV 则跳过示例笔记直接从远端拉取，防止示例笔记污染已有库。 */
  private async createVaultFromDialog(request: CreateVaultRequest): Promise<void> {
    const shouldImportExternal: boolean = this.pendingExternalImport;
    const editAfterImport: boolean = this.pendingExternalEditAfter;
    this.pendingExternalImport = false;
    this.pendingExternalEditAfter = false;
    try {
      const hasSync: boolean = request.withSync && request.serverUrl.trim().length > 0;
      await this.vm.createVault(request.name, !hasSync && !shouldImportExternal);
      await this.applyCreateSyncConfig(request);
      if (shouldImportExternal && this.vm.isExternalMode) {
        await this.finishImportExternal(editAfterImport);
      }
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`create vault failed, code=${err.code}, message=${err.message}`);
      this.toast($r('app.string.msg_create_failed'));
    }
  }

  /** 新建仓库时同时保存 WebDAV 配置，启用自动同步并触发首次同步。 */
  private async applyCreateSyncConfig(request: CreateVaultRequest): Promise<void> {
    const url: string = request.serverUrl.trim();
    if (!request.withSync || url.length === 0) {
      return;
    }
    this.syncVm.serverUrl = url;
    this.syncVm.username = request.username.trim();
    this.syncVm.password = request.password;
    const root: string = request.remoteRoot.trim();
    this.syncVm.remoteRoot = root.length > 0 ? root : 'mysidian';
    this.syncVm.skipCertVerify = request.skipCertVerify;
    this.syncVm.autoSync = true;
    await this.syncVm.save();
    this.restartAutoSyncTimer();
    this.toast($r('app.string.msg_sync_config_saved'));
    await this.syncVm.runSync(this.vm.currentVault, false, true);
  }

  /** 安全闸门触发后弹出摘要确认框（切换远端目标 / 首次非空合并 / 批量移入回收站）。 */
  private showSyncSafetyConfirmDialog(): void {
    AlertDialog.show({
      title: $r('app.string.sync_confirm_title'),
      message: this.syncVm.safetyAlertMessage(),
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        action: (): void => {
          this.syncVm.cancelPendingSync();
        }
      },
      secondaryButton: {
        value: $r('app.string.sync_confirm_proceed'),
        fontColor: $r('app.color.design_accent'),
        action: (): void => {
          this.syncVm.confirmPendingSync(this.vm.currentVault);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
