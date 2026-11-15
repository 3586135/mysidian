/**
 * Material 3 设计系统令牌（Design Tokens）。
 * 统一字号阶梯、间距、圆角与常用尺寸，避免组件内散落魔法数字。
 */
export class DesignTokens {
  // ===== 字号阶梯（fp） =====
  public static readonly FONT_XS: number = 11;
  public static readonly FONT_SM: number = 12;
  public static readonly FONT_MD: number = 14;
  public static readonly FONT_BODY: number = 15;
  public static readonly FONT_LG: number = 16;
  public static readonly FONT_TITLE: number = 18;
  public static readonly FONT_HEADING: number = 22;
  public static readonly FONT_DISPLAY: number = 26;

  // ===== 间距阶梯（vp） =====
  public static readonly SPACE_XXS: number = 2;
  public static readonly SPACE_XS: number = 4;
  public static readonly SPACE_SM: number = 8;
  public static readonly SPACE_MD: number = 12;
  public static readonly SPACE_LG: number = 16;
  public static readonly SPACE_XL: number = 20;
  public static readonly SPACE_XXL: number = 24;

  // ===== 圆角阶梯（vp） =====
  public static readonly RADIUS_SM: number = 8;
  public static readonly RADIUS_MD: number = 12;
  public static readonly RADIUS_LG: number = 16;
  public static readonly RADIUS_XL: number = 20;
  public static readonly RADIUS_SHEET: number = 28;

  // ===== 触控与图标尺寸（vp） =====
  public static readonly ICON_SM: number = 16;
  public static readonly ICON_MD: number = 20;
  public static readonly ICON_LG: number = 24;
  public static readonly TOUCH_TARGET_SM: number = 36;
  public static readonly TOUCH_TARGET_MD: number = 42;
  public static readonly TOUCH_TARGET_LG: number = 48;

  // ===== 阅读最大宽度（宽屏居中排版，vp） =====
  public static readonly READING_MAX_WIDTH: number = 720;
}
