/**
 * 同步体积上限共享策略。
 *
 * 第一性原则：内存安全决策必须在消费点（读取本身）强制执行，不能依赖服务器
 * 自报的元数据（PROPFIND size）——服务器可谎报体积、或在元数据与读取之间
 * 变更内容（TOCTOU）。引擎规划期的 size 检查只是省带宽的优化与防御纵深，
 * 真正的强制熔断在供应方读取路径（Content-Length 前置校验 + 分块累计熔断）。
 */

/** 单文件参与同步的体积上限（64MB）：超限文件跳过同步并记录警告。 */
export const MAX_SYNC_FILE_BYTES: number = 64 * 1024 * 1024;

/**
 * 读取期熔断上限：64MB + 1MB 余量，同时作为缓冲式请求（request + maxLimit）
 * 的响应上限。余量保证恰好在 64MB 以内的合法文件不会被边界条件误伤。
 */
export const STREAM_HARD_CAP_BYTES: number = MAX_SYNC_FILE_BYTES + 1024 * 1024;

/**
 * 远端读取体积熔断错误：读取路径判定远端内容超出同步体积上限时抛出
 * （来源：流式分块累计熔断、Content-Length 前置校验，或缓冲式请求
 * maxLimit 后备触发）。引擎按"持续性状态"处理：记录警告并跳过该文件，
 * 不计入 itemErrors，避免每轮同步永久报失败。
 */
export class SyncOversizedError extends Error {
  /** 触发熔断时的字节数（分块累计值、服务端自报值或后备上限）。 */
  readonly byteCount: number;

  constructor(byteCount: number, path: string) {
    super(`远端内容超出同步体积上限(${MAX_SYNC_FILE_BYTES}字节)，已跳过: ${path}`);
    this.byteCount = byteCount;
  }
}

/** 判定服务端自报的 Content-Length 是否预先超限（前置校验路径；0/负数视为未知，放行交给累计熔断）。 */
export function isDeclaredOverCap(declaredBytes: number): boolean {
  return declaredBytes > STREAM_HARD_CAP_BYTES;
}

/** 判定读取路径已接收的累计字节数是否触发熔断（分块累计路径，服务端谎报体积时的最终防线）。 */
export function isStreamOverCap(receivedBytes: number): boolean {
  return receivedBytes > STREAM_HARD_CAP_BYTES;
}
