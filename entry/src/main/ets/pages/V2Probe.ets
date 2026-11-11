/**
 * V0.4 验证：ArkUI 状态管理 V2 + Navigation / NavPathStack
 */
@ComponentV2
struct CounterCard {
  @Param label: string = '';
  @Param value: number = 0;
  @Event onPlus: () => void = () => {
  };

  build() {
    Row() {
      Text(this.label).fontSize(14).fontColor('#5B6270')
      Blank()
      Text(String(this.value)).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#15171C')
      Button('+1')
        .height(32)
        .fontSize(12)
        .margin({ left: 12 })
        .onClick(() => {
          this.onPlus();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#F7F8FA')
    .borderRadius(12)
  }
}

@Entry
@ComponentV2
struct V2Probe {
  @Local count: number = 0;
  @Local stack: NavPathStack = new NavPathStack();

  @Builder
  PageMap(name: string) {
    NavDestination() {
      Column({ space: 12 }) {
        Text('NavDestination: ' + name)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
        Text('返回栈与参数传递验证')
          .fontSize(12)
          .fontColor('#8D95A3')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .title('详情')
    .backgroundColor('#FFFFFF')
  }

  build() {
    Navigation(this.stack) {
      Column({ space: 14 }) {
        Text('V0.4 · 状态管理 V2 + Navigation')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .width('100%')

        Text('@Local 变化应立即刷新；@Param / @Event 由子组件驱动父组件。')
          .fontSize(11)
          .fontColor('#8D95A3')
          .width('100%')

        CounterCard({
          label: '点击计数',
          value: this.count,
          onPlus: () => {
            this.count = this.count + 1;
          }
        })

        Button('进入 NavDestination')
          .width('100%')
          .height(44)
          .onClick(() => {
            this.stack.pushPath({ name: 'detail' });
          })

        Button('返回上一页')
          .width('100%')
          .height(44)
          .backgroundColor('#EEF1F6')
          .fontColor('#5B6270')
          .onClick(() => {
            this.stack.pop();
          })
      }
      .width('100%')
      .height('100%')
      .padding(16)
    }
    .navDestination(this.PageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor('#FFFFFF')
  }
}
