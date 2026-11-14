import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/** 页面视图状态机：首页 / 工作台。 */
export class DesignViewMode {
  static readonly HOME: number = 0;
  static readonly WORKSPACE: number = 1;
}

/**
 * Material 3 工作台全屏子视图（骨架阶段）。
 *
 * 单页架构：不再 router 跳转，由 DesignIndex 的 viewMode 状态机控制挂载。
 * 本阶段仅含顶栏（返回 / 笔记标题）与正文占位，
 * 后续阶段依次接入文件树、编辑/预览主体与弹层。
 * 常驻全屏容器显式声明 hitTestBehavior，避免 v0.3.0 的透传吞触摸问题。
 */
@ComponentV2
export struct WorkspaceView {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Param keyboardHeight: number = 0;    // 键盘高度（vp，NONE 避让下让位）
  @Param isWide: boolean = false;       // 宽屏形态
  @Param topInset: number = 0;          // 状态栏避让高度（vp）
  @Param bottomInset: number = 0;       // 导航条避让高度（vp）
  @Event onRequestExit: () => void = (): void => {};
  @Event onEditorKeyboardMode: (active: boolean) => void = (_active: boolean): void => {};

  build() {
    Column() {
      // ===== 顶栏：返回 + 笔记标题 =====
      Row({ space: 12 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.design_text_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.design_surface_solid'))
        .border({ width: 1, color: $r('app.color.design_stroke') })
        .onClick(() => {
          this.onRequestExit();
        })

        Column({ space: 2 }) {
          Text(this.vm.noteTitle.length > 0 ? this.vm.noteTitle : this.vm.currentVault.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.vm.selectedPath.length > 0) {
            Text(this.vm.selectedPath)
              .fontSize(11)
              .fontColor($r('app.color.design_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16 })

      // ===== 主体：正文占位（阶段 3 替换为编辑/预览） =====
      Stack() {
        if (this.vm.selectedPath.length === 0) {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(40)
              .fontColor([$r('app.color.design_text_secondary')])
            Text($r('app.string.design_workspace_empty'))
              .fontSize(13)
              .fontColor($r('app.color.design_text_secondary'))
          }
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Text(this.vm.noteContent)
              .fontSize(14)
              .fontColor($r('app.color.design_text_primary'))
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .alignContent(Alignment.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.design_bg'))
    .padding({ top: this.topInset, bottom: this.bottomInset })
    .hitTestBehavior(HitTestMode.Default)
  }
}
