import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/** 回收站条目显示名：去掉回收时添加的时间戳前缀。 */
function trashDisplayName(item: string): string {
  const parts: string[] = item.split('/');
  const name: string = parts.length > 0 ? parts[parts.length - 1] : item;
  const underscore: number = name.indexOf('_');
  if (underscore < 0) {
    return name;
  }
  return name.substring(underscore + 1);
}

/**
 * Material 3 回收站浮层：查看已删除笔记，可逐条恢复或清空。
 * 清空前经 AlertDialog 二次确认（危险操作）。
 */
@ComponentV2
export struct TrashSheet {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onClose: () => void = (): void => {};
  @Event onNoteMutated: () => void = (): void => {};

  /** 回收站条目（含时间戳前缀的沙箱相对路径）。 */
  @Local trashList: string[] = [];

  aboutToAppear(): void {
    this.reloadTrash();
  }

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.design_dim'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Friction }))
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          Text($r('app.string.trash_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
          Stack() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([$r('app.color.design_text_secondary')])
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('app.color.design_elevated'))
          .alignContent(Alignment.Center)
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 12 })

        if (this.trashList.length === 0) {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(30)
              .fontColor([$r('app.color.design_text_secondary')])
              .opacity(0.65)
            Text($r('app.string.trash_empty'))
              .fontSize(13)
              .fontColor($r('app.color.design_text_secondary'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ top: 28, bottom: 28, left: 16, right: 16 })
          .borderRadius(16)
          .backgroundColor($r('app.color.design_elevated'))
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column() {
              ForEach(this.trashList, (item: string, index: number) => {
                this.trashRow(item, index)
              }, (item: string, index: number): string => `trash_${index}_${item}`)
            }
            .width('100%')
          }
          .width('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .constraintSize({ maxHeight: 320 })

          Row() {
            Button($r('app.string.action_empty_trash'))
              .type(ButtonType.Capsule)
              .height(40)
              .fontSize(15)
              .backgroundColor($r('app.color.design_elevated'))
              .fontColor($r('app.color.design_danger'))
              .layoutWeight(1)
              .onClick(() => {
                this.confirmEmptyTrash();
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
      }
      .width('88%')
      .constraintSize({ maxWidth: 460 })
      .padding(20)
      .borderRadius(28)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 32, color: $r('app.color.design_shadow'), offsetY: 10 })
      .transition(TransitionEffect.scale({ x: 0.92, y: 0.92 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }

  /** 回收站条目：文件名 + 恢复按钮。 */
  @Builder
  trashRow(item: string, index: number) {
    Row() {
      Text(trashDisplayName(item))
        .fontSize(14)
        .fontColor($r('app.color.design_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text($r('app.string.trash_restore'))
        .fontSize(12)
        .fontColor($r('app.color.design_accent'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor($r('app.color.design_accent_weak'))
        .onClick(() => {
          this.restoreFromTrash(item);
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  /** 重新拉取回收站列表。 */
  private reloadTrash(): void {
    this.vm.listTrash().then((items: string[]): void => {
      this.trashList = items;
    });
  }

  /** 从回收站恢复笔记。 */
  private restoreFromTrash(item: string): void {
    this.vm.restoreNote(item).then((ok: boolean): void => {
      if (!ok) {
        this.toast($r('app.string.msg_restore_failed'));
        return;
      }
      this.toast($r('app.string.trash_restored'));
      this.onNoteMutated();
      this.reloadTrash();
    });
  }

  /** 确认清空回收站（AlertDialog 二次确认）。 */
  private confirmEmptyTrash(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.dialog_empty_trash_title'),
      message: $r('app.string.dialog_empty_trash_msg'),
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.action_empty_trash'),
        fontColor: $r('app.color.design_danger'),
        action: (): void => {
          this.vm.emptyTrash().then((count: number): void => {
            this.toast($r('app.string.msg_empty_trash_done'));
            this.trashList = [];
            this.onNoteMutated();
          });
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
