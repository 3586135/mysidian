import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { AbilityContextHolder } from './AbilityContextHolder';

const DOMAIN = 0x0000;

export default class DefaultAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 注册 Ability 上下文，供视图模型启动外部链接（系统浏览器）。
    AbilityContextHolder.context = this.context;
    this.extractShortcutWant(want);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    this.extractShortcutWant(want);
  }

  private extractShortcutWant(want: Want): void {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return;
    }
    const actionRaw: Object | undefined = params['shortcutAction'];
    if (typeof actionRaw === 'string' && actionRaw.length > 0) {
      AbilityContextHolder.pendingShortcutAction = actionRaw;
      if (AbilityContextHolder.onShortcutAction !== null) {
        AbilityContextHolder.onShortcutAction();
      }
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 唯一 @Entry：Material 3 单页架构（首页四页签 + 页内工作台全屏子视图）。
    windowStage.loadContent('pages/DesignIndex', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      // 键盘避让默认压缩模式：弹窗与浮层不会被键盘遮挡。
      // 窄屏编辑器进入键盘交互态时，DesignIndex 会临时切换为 NONE 避让，
      // 使底部悬浮导航栏沉到键盘下方、编辑工具栏紧贴键盘上沿。
      windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set layout fullscreen. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
