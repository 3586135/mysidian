import { SearchHit } from '@ohos/domain';

/**
 * 全文搜索浮层。
 */
@ComponentV2
export struct SearchOverlay {
  @Param hits: SearchHit[] = [];
  @Param keyword: string = '';
  @Param busy: boolean = false;
  @Event onKeywordChange: (value: string) => void = (value: string): void => {};
  @Event onOpenNote: (path: string) => void = (path: string): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .opacity(0.5)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          TextInput({
            placeholder: $r('app.string.search_placeholder'),
            text: this.keyword
          })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.onKeywordChange(value);
            })
          Button($r('app.string.dialog_cancel'))
            .type(ButtonType.Normal)
            .margin({ left: 8 })
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding(12)

        if (this.hits.length === 0) {
          Text(this.busy ? $r('app.string.search_loading') : $r('app.string.search_empty'))
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .padding(16)
        } else {
          List() {
            ForEach(this.hits, (hit: SearchHit, index: number) => {
              ListItem() {
                Column() {
                  Text(hit.title)
                    .fontSize(15)
                    .fontColor($r('sys.color.ohos_id_color_text_primary'))
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(hit.snippet.length > 0 ? hit.snippet : hit.path)
                    .fontSize(12)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ top: 8, bottom: 8 })
                .onClick(() => {
                  this.onOpenNote(hit.path);
                })
              }
            }, (hit: SearchHit, index: number): string => `hit_${index}`)
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('92%')
      .height('70%')
      .borderRadius(14)
      .backgroundColor($r('sys.color.ohos_id_color_background'))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
