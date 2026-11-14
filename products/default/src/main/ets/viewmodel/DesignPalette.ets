import { resourceManager } from '@kit.LocalizationKit';

/**
 * design_ 色板运行时取色工具。
 * Canvas 的 fillStyle/strokeStyle 只接受字符串色值，无法直接用 $r 资源引用；
 * 本工具经 resourceManager 按当前系统深浅色解析 design_* 资源，
 * 把 ARGB 整数转为 '#RRGGBB' 字符串，深浅色切换后重新调用即得新模式色值。
 */
export class DesignPalette {
  /** 颜色资源名集合（与各 resources 目录下 element 里 color.json 的 design_ 前缀项对应）。 */
  public static readonly NAMES: string[] = [
    'design_bg', 'design_surface', 'design_surface_solid', 'design_elevated',
    'design_text_primary', 'design_text_secondary', 'design_accent', 'design_accent_weak',
    'design_stroke', 'design_divider', 'design_dim', 'design_shadow'
  ];

  /** 按 ARGB 整数生成 '#RRGGBB' 字符串（忽略 alpha 通道）。 */
  public static hex(argb: number): string {
    const red: number = (argb >> 16) & 0xFF;
    const green: number = (argb >> 8) & 0xFF;
    const blue: number = argb & 0xFF;
    const text: string = `#${red.toString(16).padStart(2, '0')}` +
      `${green.toString(16).padStart(2, '0')}${blue.toString(16).padStart(2, '0')}`;
    return text;
  }

  /** 把 '#RRGGBB' 转为 'rgba(r,g,b,a)'，alpha 取 0~1。 */
  public static rgba(hex: string, alpha: number): string {
    const red: number = parseInt(hex.substring(1, 3), 16);
    const green: number = parseInt(hex.substring(3, 5), 16);
    const blue: number = parseInt(hex.substring(5, 7), 16);
    return `rgba(${red},${green},${blue},${alpha})`;
  }

  /** 解析 design_* 色板（跟随系统深浅色）。失败时返回 '#808080' 兜底。 */
  public static color(mgr: resourceManager.ResourceManager, name: string): string {
    try {
      const argb: number = mgr.getColorByNameSync(name);
      return DesignPalette.hex(argb);
    } catch (error) {
      return '#808080';
    }
  }

  /** 当前模式是否为深色（按 design_text_primary 亮度判断，>0.5 为浅色模式）。 */
  public static isDarkMode(mgr: resourceManager.ResourceManager): boolean {
    try {
      const argb: number = mgr.getColorByNameSync('design_text_primary');
      const red: number = (argb >> 16) & 0xFF;
      const green: number = (argb >> 8) & 0xFF;
      const blue: number = argb & 0xFF;
      const brightness: number = (red * 299 + green * 587 + blue * 114) / 1000;
      return brightness > 128;
    } catch (error) {
      return true;
    }
  }
}
