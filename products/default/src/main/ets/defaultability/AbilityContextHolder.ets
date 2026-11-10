import { common } from '@kit.AbilityKit';

/**
 * Ability 上下文持有者。
 * 视图模型等非 UI 层需要启动外部链接（系统浏览器）时，通过这里拿到 UIAbilityContext。
 * 由 DefaultAbility.onCreate 注册，进程内单例。
 */
export class AbilityContextHolder {
  /** 当前 UIAbility 上下文；未注册时为 undefined。 */
  public static context: common.UIAbilityContext | undefined = undefined;
}
