import { describe, expect, it } from 'vitest'
import { applySessionEvent, categoryOf } from '../src/detail.ts'

describe('Live Activity turn summary', () => {
  it('tracks a running turn from start to end', () => {
    const started = applySessionEvent(undefined, { type: 'turn/start', data: { turn: 1 }, time: 1_700_000_000_000 })
    expect(started).toEqual({ startedAt: 1_700_000_000, detail: '正在处理', running: true })
    const tool = applySessionEvent(started, {
      type: 'tool/call',
      data: { name: 'bash', callId: 'call-1', arguments: JSON.stringify({ command: 'git status' }) },
      time: 1_700_000_004_000,
    })
    expect(tool).toEqual({ startedAt: 1_700_000_000, detail: '正在运行命令 · git status', running: true })
    const ended = applySessionEvent(tool, { type: 'turn/end', data: { turn: 1 }, time: 1_700_000_010_000 })
    expect(ended).toEqual({ startedAt: 1_700_000_000, detail: '正在运行命令 · git status', running: false })
  })

  it('uses readable argument hints and category fallbacks', () => {
    expect(categoryOf('read_image')).toBe('读取文件')
    expect(categoryOf('terminal_open')).toBe('运行命令')
    expect(categoryOf('mystery_tool')).toBe('调用工具')
    const tool = applySessionEvent(undefined, {
      type: 'tool/call',
      data: { name: 'read', callId: 'call-2', arguments: JSON.stringify({ path: 'src/index.ts' }) },
      time: 1,
    })
    expect(tool?.detail).toBe('正在读取文件 · src/index.ts')
    const unnamed = applySessionEvent(undefined, { type: 'tool/call', data: { name: 'grep', callId: 'call-3' }, time: 1 })
    expect(unnamed?.detail).toBe('正在搜索代码 · grep')
  })

  it('ignores events that do not change the visible summary', () => {
    expect(applySessionEvent(undefined, { type: 'tool/result', data: {} })).toBeUndefined()
    expect(applySessionEvent(undefined, { type: 'assistant/message', data: {} })).toBeUndefined()
    expect(applySessionEvent(undefined, { type: 'tool/call', data: { name: 'bash' } })).toBeUndefined()
  })
})
