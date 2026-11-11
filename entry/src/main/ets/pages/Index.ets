import { router } from '@kit.ArkUI';
import { WatchTable } from '../prototype/WatchTable';

@Entry
@Component
struct Index {
  build() {
    Column() {
      Row() {
        Text('自选股')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#15171C')
        Blank()
        Button('V0.4 V2')
          .fontSize(12)
          .height(32)
          .margin({ right: 8 })
          .backgroundColor('#EEF1F6')
          .fontColor('#5B6270')
          .onClick(() => {
            router.pushUrl({ url: 'pages/V2Probe' });
          })
        Button('V0.3 图表')
          .fontSize(12)
          .height(32)
          .backgroundColor('#EEF1F6')
          .fontColor('#5B6270')
          .onClick(() => {
            router.pushUrl({ url: 'pages/ChartProbe' });
          })
      }
      .width('100%')
      .height(64)
      .padding({ left: 20, right: 16 })
      .alignItems(VerticalAlign.Center)

      Text('V0.2 原型 · 11 列冻结横滑')
        .fontSize(11)
        .fontColor('#8D95A3')
        .width('100%')
        .padding({ left: 20, bottom: 8 })

      WatchTable()
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
