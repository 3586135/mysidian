import { common } from '@kit.AbilityKit';

/**
 * Ability 上下文持有者。
 * 视图模型等非 UI 层需要启动外部链接（系统浏览器）时，通过这里拿到 UIAbilityContext。
 * 由 DefaultAbility.onCreate 注册，进程内单例。
 */
export class AbilityContextHolder {
  /** 当前 UIAbility 上下文；未注册时为 undefined。 */
  public static context: common.UIAbilityContext | undefined = undefined;
  /** 桌面长按快捷方式待消费动作（quick_note / daily_note / search）。 */
  public static pendingShortcutAction: string = '';
  /** 热启动快捷方式动作回调（由 DesignIndex 注册）。 */
  public static onShortcutAction: (() => void) | null = null;
  /** 外部文件管理器或其他应用传入的待打开文件 URI。 */
  public static pendingOpenUri: string = '';
  /** 热启动打开外部文件回调（由 DesignIndex 注册）。 */
  public static onOpenUri: (() => void) | null = null;
  /** 应用回到前台回调（由 DesignIndex 注册，用于触发无感静默同步）。 */
  public static onForeground: (() => void) | null = null;
}
