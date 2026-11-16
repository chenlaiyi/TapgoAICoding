/** Turn summary derived from durable Session events for Live Activity pushes. */

/** Work currently shown for one Session. */
export interface SessionWork {
  /** When the running turn started, in epoch seconds. */
  readonly startedAt: number
  /** `正在运行命令 · git status`-style summary. */
  readonly detail: string
  /** Whether the turn still runs. */
  readonly running: boolean
}

const CATEGORIES: Readonly<Record<string, string>> = {
  read: '读取文件',
  read_image: '读取文件',
  grep: '搜索代码',
  glob: '搜索代码',
  write: '修改文件',
  edit: '修改文件',
  apply_patch: '修改文件',
  bash: '运行命令',
  pwsh: '运行命令',
  exec_command: '运行命令',
  write_stdin: '运行命令',
  run_code: '运行代码',
  web_search: '访问网页',
  web_fetch: '访问网页',
}

const DETAIL_KEYS = ['title', 'description', 'command', 'cmd', 'file_path', 'path', 'query', 'pattern'] as const

/**
 * Category label for one tool name.
 * @param name - Tool name reported by the Session event.
 * @returns The Chinese category shown in the Live Activity.
 */
export function categoryOf(name: string): string {
  if (name.startsWith('terminal_')) return '运行命令'
  if (name.endsWith('_inspect')) return '搜索代码'
  return CATEGORIES[name] ?? '调用工具'
}

/** First human-readable argument of one tool call. */
function detailOf(name: string, args: unknown): string {
  if (typeof args !== 'object' || args === null) return name
  for (const key of DETAIL_KEYS) {
    const value = Reflect.get(args, key)
    if (typeof value === 'string' && value.trim() !== '') return value.slice(0, 120)
  }
  return name
}

/** Event facts this module reads; structural, so SessionEvent's full payload stays at the caller. */
export interface SessionEventLike {
  readonly type: string
  readonly data?: unknown
  readonly time?: number
}

/**
 * Fold one durable Session event into the current work summary.
 * @param current - Summary before this event.
 * @param event - Committed Session event.
 * @returns The next summary, or `undefined` for events that change nothing shown.
 */
export function applySessionEvent(current: SessionWork | undefined, event: SessionEventLike): SessionWork | undefined {
  const data = typeof event.data === 'object' && event.data !== null ? event.data : {}
  const time = typeof event.time === 'number' ? Math.floor(event.time / 1000) : Math.floor(Date.now() / 1000)
  if (event.type === 'turn/start') {
    return { startedAt: time, detail: current?.detail ?? '正在处理', running: true }
  }
  if (event.type === 'turn/end') {
    return { startedAt: current?.startedAt ?? time, detail: current?.detail ?? '正在处理', running: false }
  }
  if (event.type !== 'tool/call') return undefined
  const name = Reflect.get(data, 'name')
  const call = Reflect.get(data, 'callId')
  if (typeof name !== 'string' || typeof call !== 'string') return undefined
  const rawArguments = Reflect.get(data, 'arguments')
  let parsed: unknown
  if (typeof rawArguments === 'string') {
    try { parsed = JSON.parse(rawArguments) } catch { parsed = undefined }
  }
  const category = categoryOf(name)
  const detail = detailOf(name, parsed)
  return {
    startedAt: current?.startedAt ?? time,
    detail: `正在${category} · ${detail}`,
    running: true,
  }
}
