import { curves, KeyboardAvoidMode, mediaquery, promptAction, window } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { TagRef } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { SyncSettings } from '../view/SyncSettings';
import { SettingsOverlay } from '../view/SettingsOverlay';
import { WorkspaceView, DesignViewMode } from '../view/design/WorkspaceView';
import { GraphLayout } from '../viewmodel/GraphLayout';
import { DesignPalette } from '../viewmodel/DesignPalette';
import { SearchViewModel } from '../viewmodel/SearchViewModel';
import { SyncViewModel } from '../viewmodel/SyncViewModel';
import { RecentNoteItem, RootFolderSummary, VaultViewModel } from '../viewmodel/VaultViewModel';

const LOG: Logger = new Logger('DesignIndex');

// ===== Material 3 悬浮分离式胶囊底栏尺寸常量（vp） =====
const BAR_SIDE_VP: number = 16;               // 底栏左右外边距
const BAR_BOTTOM_VP: number = 16;             // 底栏距屏幕底部
const CAPSULE_HEIGHT_VP: number = 64;         // 左侧胶囊高度
const FAB_SIZE_VP: number = 64;               // 右侧 FAB 边长
const BAR_GAP_VP: number = 12;                // 胶囊与 FAB 间距
const SLIDER_WIDTH_VP: number = 60;           // 滑块指示器宽度
const SLIDER_HEIGHT_VP: number = 54;          // 滑块指示器高度
const SLIDER_RADIUS_VP: number = 27;          // 滑块指示器圆角
const GRAPH_CANVAS_HEIGHT_VP: number = 340;   // 图谱画布高度
const DOUBLE_PI: number = Math.PI * 2;
const SEARCH_DEBOUNCE_MS: number = 250;       // 搜索防抖时长

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

// ===== 图谱页：换算为 vp 后的节点（标签叠加定位用） =====
class DesignGraphNodeVp {
  keyId: string;
  x: number;
  y: number;
  radiusVp: number;
  label: string;
  isRoot: boolean;

  constructor(keyId: string, x: number, y: number, radiusVp: number, label: string, isRoot: boolean) {
    this.keyId = keyId;
    this.x = x;
    this.y = y;
    this.radiusVp = radiusVp;
    this.label = label;
    this.isRoot = isRoot;
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
  @Local searchKeyword: string = '';       // 搜索页：关键词
  @Local searchRows: DesignSearchRow[] = [];// 搜索页：命中结果（含高亮分段）
  @Local selectedGraphPath: string = '';   // 图谱页：选中节点路径（默认当前笔记）
  @Local graphCanvasWidthVp: number = 0;   // 图谱画布实际宽度
  @Local graphNodeVpList: DesignGraphNodeVp[] = []; // 图谱节点 vp 坐标（标签叠加用）
  @Local showFabMenu: boolean = false;     // FAB 长按气泡菜单
  @Local showQuickEditor: boolean = false; // 快速笔记半模态
  @Local fabLongPressConsumed: boolean = false; // 长按已消费标志（防误触发 click）
  @Local draftTitle: string = '';          // 快速笔记草稿标题
  @Local draftBody: string = '';           // 快速笔记草稿正文
  @Local showSyncPanel: boolean = false;   // 同步设置浮层
  @Local showSettingsPanel: boolean = false; // 外观与设置浮层
  @Local viewMode: number = DesignViewMode.HOME; // 页面状态机：0 首页 / 1 工作台
  @Local keyboardHeight: number = 0;       // 键盘高度（vp，NONE 避让下让位）
  @Local editorKeyboardMode: boolean = false; // 编辑区键盘交互态（切换 NONE 避让）
  @Local isWide: boolean = false;          // 宽屏形态（键盘避让策略依据）

  // ===== 控制器与画布上下文 =====
  private swiperController: SwiperController = new SwiperController();
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private graphNodeMap: Map<string, DesignGraphNodeVp> = new Map<string, DesignGraphNodeVp>();
  private searchDebounceId: number = -1;
  private initReady: boolean = false;            // 视图模型初始化完成
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
  /** 自动同步周期。 */
  private static readonly AUTO_SYNC_INTERVAL_MS: number = 30 * 60 * 1000;

  // ===== 静态定义 =====
  readonly tabDefs: DesignTabDef[] = [
    new DesignTabDef('t_files', $r('app.string.design_tab_files'), $r('sys.symbol.folder')),
    new DesignTabDef('t_search', $r('app.string.design_tab_search'), $r('sys.symbol.magnifyingglass')),
    new DesignTabDef('t_graph', $r('app.string.design_tab_graph'), $r('sys.symbol.circle_grid_2x2')),
    new DesignTabDef('t_more', $r('app.string.design_tab_more'), $r('sys.symbol.more'))
  ];

  readonly modeChips: DesignModeChip[] = [
    new DesignModeChip('m_full', $r('app.string.design_search_mode_full'), 0),
    new DesignModeChip('m_tag', $r('app.string.design_search_mode_tag'), 1),
    new DesignModeChip('m_prop', $r('app.string.design_search_mode_prop'), 2)
  ];

  /** 插件宫格（标签计数取真实数据）。 */
  @Computed
  get morePlugins(): DesignMoreEntry[] {
    return [
      new DesignMoreEntry('m_daily', $r('app.string.design_more_daily'), $r('app.string.design_more_daily_sub'),
        $r('sys.symbol.calendar')),
      new DesignMoreEntry('m_templates', $r('app.string.design_more_templates'), $r('app.string.design_more_templates_sub'),
        $r('sys.symbol.doc_text_on_doc_text')),
      new DesignMoreEntry('m_tags', $r('app.string.design_more_tags'),
        $r('app.string.design_more_tags_sub', this.vm.allTagNames.length), $r('sys.symbol.hash'))
    ];
  }

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
      this.restartAutoSyncTimer();
    });
    // 同步拉取了新文件后重建索引并刷新文件树，使新笔记可见。
    this.syncVm.onSyncComplete = (): void => {
      this.vm.rescanVault();
    };
    this.vm.init(context).then((): void => {
      this.initReady = true;
      this.vm.loadGraph().then((): void => {
        this.rebuildGraphLayout();
      });
    });
    // 深浅色切换：Canvas 色值需按新模式重绘
    this.darkModeListener = this.getUIContext().getMediaQuery().matchMediaSync('(dark-mode: true)');
    this.darkModeListener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.rebuildGraphLayout();
    });
  }

  aboutToDisappear(): void {
    this.stopAutoSyncTimer();
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('keyboardHeightChange', this.keyboardCallback);
      this.mainWindow = undefined;
    }
    if (this.darkModeListener !== null) {
      this.darkModeListener.off('change');
      this.darkModeListener = null;
    }
  }

  /** 系统返回键：工作台 → 返回首页；首页 → 依次关闭浮层 → 默认退出。 */
  onBackPress(): boolean {
    if (this.viewMode === DesignViewMode.WORKSPACE) {
      this.exitWorkspace();
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
    if (this.showSyncPanel) {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.showSyncPanel = false;
      });
      return true;
    }
    if (this.showSettingsPanel) {
      this.showSettingsPanel = false;
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
          keyboardHeight: this.keyboardHeight,
          isWide: this.isWide,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          onRequestExit: (): void => {
            this.exitWorkspace();
          },
          onEditorKeyboardMode: (active: boolean): void => {
            this.setEditorKeyboardMode(active);
          }
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.Friction }))
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

  /** 首页内容：四页签横滑 + 悬浮底栏 + 各浮层。 */
  @Builder
  homeContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 内容区：四个页面横滑
      Swiper(this.swiperController) {
        this.filesPage()
        this.searchPage()
        this.graphPage()
        this.morePage()
      }
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

      // 底部悬浮分离式胶囊 + FAB
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

      // 同步设置浮层（自含遮罩）
      if (this.showSyncPanel) {
        SyncSettings({
          serverUrl: this.syncVm.serverUrl,
          username: this.syncVm.username,
          password: this.syncVm.password,
          remoteRoot: this.syncVm.remoteRoot,
          caCertPath: this.syncVm.caCertPath,
          skipCertVerify: this.syncVm.skipCertVerify,
          autoSync: this.syncVm.autoSync,
          statusText: this.syncVm.statusText(),
          conflicts: this.syncVm.conflicts,
          onServerUrlChange: (value: string): void => {
            this.syncVm.serverUrl = value;
          },
          onUsernameChange: (value: string): void => {
            this.syncVm.username = value;
          },
          onPasswordChange: (value: string): void => {
            this.syncVm.password = value;
          },
          onRemoteRootChange: (value: string): void => {
            this.syncVm.remoteRoot = value;
          },
          onImportCert: (): void => {
            this.pickCertFile();
          },
          onClearCert: (): void => {
            this.syncVm.clearCert();
          },
          onSkipCertChange: (value: boolean): void => {
            this.syncVm.skipCertVerify = value;
          },
          onAutoSyncChange: (value: boolean): void => {
            this.syncVm.autoSync = value;
            this.restartAutoSyncTimer();
          },
          onSyncNow: (): void => {
            this.syncVm.runSync(this.vm.currentVault);
          },
          onClose: (): void => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
              this.showSyncPanel = false;
            });
          }
        })
      }

      // 外观与设置浮层（自含遮罩）
      if (this.showSettingsPanel) {
        SettingsOverlay({
          fontSize: this.vm.fontSize,
          onFontSizeChange: (size: number): void => {
            this.vm.setFontSize(size);
          },
          onReindex: (): void => {
            this.vm.rescanVault();
          },
          onExport: (): void => {
            this.exportVault();
          },
          onClose: (): void => {
            this.showSettingsPanel = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.Friction }))
  }

  // ==================== 底部悬浮栏 ====================

  @Builder
  bottomBar() {
    Row({ space: BAR_GAP_VP }) {
      // 左：胶囊导航（毛玻璃 + 滑块指示器）
      Stack() {
        // 滑块指示器：跟随手势偏移，松手弹性归位
        Stack() {
        }
        .width(SLIDER_WIDTH_VP)
        .height(SLIDER_HEIGHT_VP)
        .borderRadius(SLIDER_RADIUS_VP)
        .backgroundColor($r('app.color.design_elevated'))
        .position({ x: this.sliderXVp, y: (CAPSULE_HEIGHT_VP - SLIDER_HEIGHT_VP) / 2 })
        .scale({ x: this.indicatorScale, y: this.indicatorScale })

        // 四个页签单元
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
      .backgroundColor($r('app.color.design_surface'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .borderRadius(CAPSULE_HEIGHT_VP / 2)
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 28, color: $r('app.color.design_shadow'), offsetY: 10 })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.capsuleWidthVp = Number(newArea.width);
      })

      // 右：FAB（短按快速笔记 / 长按气泡菜单）
      Stack() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(26)
          .fontColor([$r('app.color.design_text_primary')])
      }
      .width(FAB_SIZE_VP)
      .height(FAB_SIZE_VP)
      .borderRadius(FAB_SIZE_VP / 2)
      .backgroundColor($r('app.color.design_elevated'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
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

  // ==================== 文件页 ====================

  @Builder
  filesPage() {
    Column() {
      // 顶栏：仓库名（点按进入工作台）+ 收起按钮
      Row() {
        Row({ space: 4 }) {
          Text(this.vm.currentVault.name)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 240 })
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.design_text_secondary')])
        }
        .alignItems(VerticalAlign.Center)
        .layoutWeight(1)
        .onClick(() => {
          this.openWorkspace({});
        })

        Stack() {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(18)
            .fontColor([$r('app.color.design_text_secondary')])
            .rotate({ angle: this.filesCollapsed ? -90 : 0 })
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.design_surface_solid'))
        .border({ width: 1, color: $r('app.color.design_stroke') })
        .onClick(() => {
          this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
            this.filesCollapsed = !this.filesCollapsed;
          });
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: BAR_SIDE_VP, right: BAR_SIDE_VP })

      Scroll() {
        Column({ space: 10 }) {
          if (this.vm.vaults.length === 0) {
            // 无仓库：引导创建
            this.onboardCard()
          } else {
            if (!this.filesCollapsed) {
              Column({ space: 8 }) {
                ForEach(this.vm.rootFolders, (folder: RootFolderSummary) => {
                  this.folderRow(folder)
                }, (folder: RootFolderSummary) => folder.path)
              }
              .width('100%')
            }

            Text($r('app.string.design_files_recent'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_text_secondary'))
              .width('100%')
              .margin({ top: 4 })

            if (this.vm.recentNotes.length === 0) {
              Text($r('app.string.design_files_empty'))
                .fontSize(13)
                .fontColor($r('app.color.design_text_secondary'))
                .width('100%')
                .padding({ top: 8, bottom: 8 })
            }

            ForEach(this.vm.recentNotes, (item: RecentNoteItem) => {
              this.recentNoteCard(item)
            }, (item: RecentNoteItem) => item.path)
          }
        }
        .width('100%')
        .padding({
          left: BAR_SIDE_VP,
          right: BAR_SIDE_VP,
          top: 12,
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
    .padding({ top: this.topInset + 8 })
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
          this.openWorkspace({});
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
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(20)
        .fontColor([$r('app.color.design_text_secondary')])
      Text(folder.name)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text($r('app.string.design_files_folder_count', folder.noteCount))
        .fontSize(13)
        .fontColor($r('app.color.design_text_secondary'))
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.design_text_secondary')])
        .opacity(0.6)
    }
    .width('100%')
    .height(52)
    .padding({ left: 14, right: 14 })
    .borderRadius(16)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .onClick(() => {
      this.openWorkspace({ 'expandPath': folder.path });
    })
  }

  @Builder
  recentNoteCard(item: RecentNoteItem) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_plaintext'))
          .fontSize(16)
          .fontColor([$r('app.color.design_text_secondary')])
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(formatRelativeTime(item.openedAt))
          .fontSize(12)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .width('100%')

      Text(item.path)
        .fontSize(12)
        .fontColor($r('app.color.design_text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(18)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .onClick(() => {
      this.openWorkspace({ 'openPath': item.path });
    })
  }

  // ==================== 搜索页 ====================

  @Builder
  searchPage() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          if (this.vm.vaults.length === 0) {
            this.needVaultCard()
          } else {
            // 圆角搜索框
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
            .backgroundColor($r('app.color.design_surface_solid'))
            .border({ width: 1, color: $r('app.color.design_stroke') })

            // 模式 chips（全文 / 标签 / 属性）
            Row({ space: 8 }) {
              ForEach(this.modeChips, (chip: DesignModeChip) => {
                Text(chip.label)
                  .fontSize(13)
                  .fontWeight(chip.mode === this.searchVm.searchMode ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(chip.mode === this.searchVm.searchMode ?
                    $r('app.color.design_text_primary') : $r('app.color.design_text_secondary'))
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .borderRadius(16)
                  .backgroundColor(chip.mode === this.searchVm.searchMode ?
                    $r('app.color.design_elevated') : $r('app.color.design_surface_solid'))
                  .border({ width: 1, color: $r('app.color.design_stroke') })
                  .onClick(() => {
                    this.switchSearchMode(chip.mode);
                  })
              }, (chip: DesignModeChip) => chip.keyId)
            }
            .width('100%')

            // 标签模式：标签候选
            if (this.searchVm.searchMode === 1) {
              if (this.searchVm.tagChips.length === 0) {
                Text($r('app.string.design_search_tag_hint'))
                  .fontSize(13)
                  .fontColor($r('app.color.design_text_secondary'))
                  .width('100%')
                  .padding({ top: 4, bottom: 4 })
              } else {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(this.searchVm.tagChips, (chip: TagRef) => {
                      Text(`#${chip.tag} · ${chip.count}`)
                        .fontSize(13)
                        .fontWeight(chip.tag === this.searchVm.activeTag ? FontWeight.Medium : FontWeight.Normal)
                        .fontColor(chip.tag === this.searchVm.activeTag ?
                          $r('app.color.design_accent') : $r('app.color.design_text_secondary'))
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .borderRadius(14)
                        .backgroundColor(chip.tag === this.searchVm.activeTag ?
                          $r('app.color.design_accent_weak') : $r('app.color.design_surface_solid'))
                        .border({ width: 1, color: $r('app.color.design_stroke') })
                        .onClick(() => {
                          this.selectTagChip(chip.tag);
                        })
                    }, (chip: TagRef) => chip.tag)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
              }
            }

            // 属性模式：格式提示
            if (this.searchVm.searchMode === 2 && !this.hasSearched) {
              Text($r('app.string.design_search_prop_hint'))
                .fontSize(13)
                .fontColor($r('app.color.design_text_secondary'))
                .width('100%')
                .padding({ top: 4, bottom: 4 })
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
          this.openWorkspace({});
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
      .width('100%')

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
    .onClick(() => {
      this.openWorkspace({ 'openPath': row.path });
    })
  }

  // ==================== 图谱页 ====================

  @Builder
  graphPage() {
    Column() {
      Scroll() {
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
            Text(this.vm.noteTitle)
              .fontSize(12)
              .fontColor($r('app.color.design_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.vm.vaults.length === 0) {
            this.needVaultCard()
          } else {
            if (this.vm.graph.nodes.length === 0) {
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
              // 画布绘制连线与节点圆点，节点标题用 Text 叠加保证字体清晰
              Stack() {
                Canvas(this.canvasContext)
                  .width('100%')
                  .height(GRAPH_CANVAS_HEIGHT_VP)
                  .onReady(() => {
                    this.drawGraph();
                  })
                  .onClick((event: ClickEvent) => {
                    this.handleGraphClick(event);
                  })
                ForEach(this.graphNodeVpList, (node: DesignGraphNodeVp) => {
                  Text(node.label)
                    .fontSize(node.isRoot ? 13 : 11)
                    .fontWeight(node.keyId === this.selectedGraphPath ? FontWeight.Bold : FontWeight.Medium)
                    .fontColor(node.keyId === this.selectedGraphPath ?
                      $r('app.color.design_accent') : $r('app.color.design_text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(76)
                    .textAlign(TextAlign.Center)
                    .position({ x: node.x, y: node.y + node.radiusVp + 12 })
                    .markAnchor({ x: '50%', y: '0%' })
                    .hitTestBehavior(HitTestMode.Transparent)
                }, (node: DesignGraphNodeVp) => node.keyId)
              }
              .width('100%')
              .height(GRAPH_CANVAS_HEIGHT_VP)
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

  // ==================== 更多页 ====================

  @Builder
  morePage() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Text($r('app.string.design_tab_more'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_text_primary'))
            .width('100%')

          Text($r('app.string.design_more_section_plugins'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_secondary'))
            .width('100%')
            .margin({ top: 4 })

          // 核心插件：三列宫格
          Row({ space: 10 }) {
            ForEach(this.morePlugins, (entry: DesignMoreEntry) => {
              Column({ space: 8 }) {
                Stack() {
                  SymbolGlyph(entry.symbol)
                    .fontSize(22)
                    .fontColor([$r('app.color.design_accent')])
                }
                .width(44)
                .height(44)
                .borderRadius(22)
                .backgroundColor($r('app.color.design_elevated'))
                Text(entry.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.design_text_primary'))
                  .maxLines(1)
                Text(entry.sub)
                  .fontSize(11)
                  .fontColor($r('app.color.design_text_secondary'))
                  .maxLines(2)
                  .textAlign(TextAlign.Center)
              }
              .layoutWeight(1)
              .padding({ top: 14, bottom: 12, left: 6, right: 6 })
              .borderRadius(20)
              .backgroundColor($r('app.color.design_surface_solid'))
              .border({ width: 1, color: $r('app.color.design_stroke') })
              .onClick(() => {
                this.onPluginEntry(entry.keyId);
              })
            }, (entry: DesignMoreEntry) => entry.keyId)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          Text($r('app.string.design_more_section_settings'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_secondary'))
            .width('100%')
            .margin({ top: 4 })

          // 设置：列表行
          ForEach(this.moreSettings, (entry: DesignMoreEntry) => {
            this.moreListRow(entry)
          }, (entry: DesignMoreEntry) => entry.keyId)
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

  /** 设置区入口（含同步配置状态）。 */
  @Computed
  get moreSettings(): DesignMoreEntry[] {
    return [
      new DesignMoreEntry('m_workspace', $r('app.string.design_more_workspace'),
        $r('app.string.design_more_workspace_sub'), $r('sys.symbol.square_grid_2x2')),
      new DesignMoreEntry('m_sync', $r('app.string.design_more_sync'),
        this.syncVm.configured ? $r('app.string.design_more_sync_configured') :
        $r('app.string.design_more_sync_not_configured'), $r('sys.symbol.arrow_clockwise')),
      new DesignMoreEntry('m_appearance', $r('app.string.design_more_appearance'),
        $r('app.string.design_more_appearance_sub'), $r('sys.symbol.paintpalette'))
    ];
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
    .borderRadius(18)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
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
          .backgroundColor($r('app.color.design_surface_solid'))
          .border({ width: 1, color: $r('app.color.design_stroke') })
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
      .padding({ left: 20, right: 12 })

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

      // Markdown 语法插入条
      Row({ space: 8 }) {
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
          .onClick(() => {
            this.draftBody = this.draftBody + chip.insertText;
          })
        }, (chip: DesignInsertChip) => chip.keyId)
      }
      .width('100%')
      .margin({ top: 12, bottom: 16 })
    }
    .width('100%')
    .height('76%')
    .padding({ left: BAR_SIDE_VP, right: BAR_SIDE_VP })
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
    } else {
      const expandPathRaw: Object | undefined = params['expandPath'];
      const expandPath: string = typeof expandPathRaw === 'string' ? expandPathRaw : '';
      if (expandPath.length > 0) {
        for (const item of this.vm.treeItems) {
          if (item.node.path === expandPath && item.node.isDir && !item.expanded) {
            this.vm.toggleDir(expandPath);
            break;
          }
        }
      }
    }
    // 'action' 类参数（templates 等）待工作台弹层接入后处理。
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => {
      this.viewMode = DesignViewMode.WORKSPACE;
    });
  }

  /** 退出工作台返回首页：复位键盘态并恢复会话（仓库/笔记/图谱/搜索）。 */
  private exitWorkspace(): void {
    this.setEditorKeyboardMode(false);
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

  /** 进入 / 退出编辑区键盘交互态。 */
  private setEditorKeyboardMode(active: boolean): void {
    if (this.editorKeyboardMode === active) {
      return;
    }
    this.editorKeyboardMode = active;
    this.applyKeyboardAvoidMode();
  }

  /** 自动同步开启时立即触发一次同步（保存 / 新建后调用）。 */
  private syncNowIfAuto(): void {
    if (!this.syncVm.autoSync || this.syncVm.serverUrl.length === 0) {
      return;
    }
    this.syncVm.runSync(this.vm.currentVault);
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

  /** 更多页插件宫格入口分发。 */
  private onPluginEntry(keyId: string): void {
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
  }

  /** 更多页设置行入口分发。 */
  private onMoreEntry(keyId: string): void {
    if (keyId === 'm_workspace') {
      this.openWorkspace({});
      return;
    }
    if (keyId === 'm_sync') {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, () => {
        this.showSyncPanel = true;
      });
      return;
    }
    if (keyId === 'm_appearance') {
      this.showSettingsPanel = true;
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
      const snippet: string = hit.snippet.replace(/\n/g, ' ');
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
      this.vm.loadGraph().then((): void => {
        this.selectedGraphPath = '';
        this.rebuildGraphLayout();
      });
      if (this.searchKeyword.trim().length > 0 || this.searchVm.activeTag.length > 0) {
        this.runSearch();
      }
    });
  }

  /** 按画布实际宽度重算图谱布局（力导向）并重绘。 */
  private rebuildGraphLayout(): void {
    const widthVp: number = this.graphCanvasWidthVp;
    const graph = this.vm.graph;
    if (widthVp <= 0 || graph.nodes.length === 0) {
      this.graphNodeVpList = [];
      this.graphNodeMap = new Map<string, DesignGraphNodeVp>();
      return;
    }
    GraphLayout.compute(graph, widthVp, GRAPH_CANVAS_HEIGHT_VP);
    if (this.selectedGraphPath.length === 0) {
      for (const node of graph.nodes) {
        if (node.root) {
          this.selectedGraphPath = node.path;
          break;
        }
      }
    }
    const list: DesignGraphNodeVp[] = [];
    const map: Map<string, DesignGraphNodeVp> = new Map<string, DesignGraphNodeVp>();
    for (const node of graph.nodes) {
      const vpNode: DesignGraphNodeVp = new DesignGraphNodeVp(node.path, node.x, node.y,
        node.radius, node.title, node.root);
      list.push(vpNode);
      map.set(node.path, vpNode);
    }
    this.graphNodeVpList = list;
    this.graphNodeMap = map;
    this.drawGraph();
  }

  /** 经 resourceManager 解析 design_* 色板（跟随系统深浅色），供 Canvas 使用。 */
  private paletteColor(name: string): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '#808080';
    }
    return DesignPalette.color(context.resourceManager, name);
  }

  /** 绘制图谱：连线（选中关联高亮）+ 节点圆点（选中放大加光晕）。 */
  private drawGraph(): void {
    const ctx: CanvasRenderingContext2D = this.canvasContext;
    const widthVp: number = this.graphCanvasWidthVp;
    if (widthVp <= 0) {
      return;
    }
    ctx.clearRect(0, 0, widthVp, GRAPH_CANVAS_HEIGHT_VP);
    if (this.graphNodeVpList.length === 0) {
      return;
    }
    // 色板按当前深浅模式解析
    const accent: string = this.paletteColor('design_accent');
    const elevated: string = this.paletteColor('design_elevated');
    const edgeActive: string = DesignPalette.rgba(accent, 0.8);
    const edgeIdle: string = DesignPalette.rgba(this.paletteColor('design_text_secondary'), 0.28);
    const haloColor: string = DesignPalette.rgba(accent, 0.16);
    const nodeStroke: string = DesignPalette.rgba(this.paletteColor('design_text_primary'), 0.14);
    // 连线
    for (const edge of this.vm.graph.edges) {
      const fromNode: DesignGraphNodeVp | undefined = this.graphNodeMap.get(edge.from);
      const toNode: DesignGraphNodeVp | undefined = this.graphNodeMap.get(edge.to);
      if (fromNode === undefined || toNode === undefined) {
        continue;
      }
      const active: boolean = edge.from === this.selectedGraphPath || edge.to === this.selectedGraphPath;
      ctx.strokeStyle = active ? edgeActive : edgeIdle;
      ctx.lineWidth = active ? 2 : 1.2;
      ctx.beginPath();
      ctx.moveTo(fromNode.x, fromNode.y);
      ctx.quadraticCurveTo((fromNode.x + toNode.x) / 2, (fromNode.y + toNode.y) / 2 - 16, toNode.x, toNode.y);
      ctx.stroke();
    }
    // 节点
    for (const node of this.graphNodeVpList) {
      const selected: boolean = node.keyId === this.selectedGraphPath;
      const radiusVp: number = selected ? node.radiusVp * 1.15 : node.radiusVp;
      if (selected) {
        ctx.beginPath();
        ctx.fillStyle = haloColor;
        ctx.arc(node.x, node.y, node.radiusVp * 1.7, 0, DOUBLE_PI);
        ctx.fill();
      }
      ctx.beginPath();
      ctx.fillStyle = selected ? accent : elevated;
      ctx.arc(node.x, node.y, radiusVp, 0, DOUBLE_PI);
      ctx.fill();
      ctx.beginPath();
      ctx.strokeStyle = nodeStroke;
      ctx.lineWidth = 1;
      ctx.arc(node.x, node.y, radiusVp, 0, DOUBLE_PI);
      ctx.stroke();
    }
  }

  /** 点击画布：命中未选中节点则高亮；命中已选中节点则在工作台打开。 */
  private handleGraphClick(event: ClickEvent): void {
    const xVp: number = event.x;
    const yVp: number = event.y;
    let hitPath: string = '';
    let bestDistance: number = 1e9;
    for (const node of this.graphNodeVpList) {
      const dxVp: number = node.x - xVp;
      const dyVp: number = node.y - yVp;
      const distance: number = dxVp * dxVp + dyVp * dyVp;
      const hitRadiusVp: number = node.radiusVp + 12;
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

  /** 导出当前仓库为 zip。 */
  private async exportVault(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`${this.vm.currentVault.name}.zip`];
      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return;
      }
      await this.vm.exportVault(this.vm.currentVault, uris[0]);
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`export vault failed, code=${err.code}, message=${err.message}`);
      promptAction.showToast({ message: $r('app.string.msg_export_failed') });
    }
  }
}
