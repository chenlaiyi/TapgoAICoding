/** External native SDK fixture usable by Vitest and test-only Node module hooks. */
import type { PrivateWorkerOptions } from '@trycua/cua-driver'

/** Upstream numeric standard permission mode. */
export const SessionPermissionMode = { Standard: 0 } as const

/** A valid one-pixel PNG keeps image admission on the real attachment path. */
export const screenshotBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAADElEQVQImWNgZGIGAAAOAAeCcsnOAAAAAElFTkSuQmCC'

/** Fixture-native tool inventory, using the upstream catalog fields. */
export const catalog = {
  schema_version: '1',
  capability_version: '1',
  tools: [
    {
      name: 'get_window_state',
      description: 'Capture a Cua Driver window screenshot.',
      inputSchema: { type: 'object', properties: { pid: { type: 'integer' }, window_id: { type: 'integer' } }, required: ['pid', 'window_id'] },
      outputSchema: { type: 'object', properties: { window_id: { type: 'integer' }, clicked: { type: 'boolean' } }, required: ['window_id', 'clicked'] },
    },
    {
      name: 'click',
      description: 'Click the selected Cua Driver window.',
      inputSchema: { type: 'object', properties: { pid: { type: 'integer' }, window_id: { type: 'integer' }, delivery_mode: { type: 'string', enum: ['background', 'foreground'] } }, required: ['pid', 'window_id'] },
    },
    {
      name: 'check_permissions',
      description: 'Read host desktop permissions without prompting.',
      inputSchema: { type: 'object', properties: {} },
    },
    {
      name: 'drag',
      description: 'Drag through native desktop coordinates.',
      inputSchema: { type: 'object', properties: {
        scope: { type: 'string', enum: ['desktop', 'window'] }, delivery_mode: { type: 'string', enum: ['background', 'foreground'] },
        from_x: { type: 'number' }, from_y: { type: 'number' }, to_x: { type: 'number' }, to_y: { type: 'number' },
      }, required: ['from_x', 'from_y', 'to_x', 'to_y'] },
    },
    {
      name: 'browser_click',
      description: 'Click an exactly-bound browser tab.',
      inputSchema: {
        type: 'object',
        properties: {
          target_id: { type: 'string' }, tab_id: { type: 'string' }, ref: { type: 'string' },
          input_route: { type: 'string', enum: ['trusted', 'dom_event'], default: 'trusted' },
          delivery_mode: { type: 'string', enum: ['background', 'foreground'], default: 'background' },
        },
        required: ['target_id', 'tab_id', 'ref'],
      },
    },
  ],
}

/** Mutable controls represent only the external native implementation. */
export const fixture: {
  workerOptions?: PrivateWorkerOptions
  creates: number
  createOptions?: { embedded: boolean; claudeCodeCompatibility: boolean }
  destroys: number
  shutdowns: number
  clicked: boolean
  calls: Array<{ name: string; args: Record<string, unknown>; signal?: AbortSignal }>
  createError?: Error
  list?: (signal?: AbortSignal) => Promise<string>
  call?: (name: string, args: Record<string, unknown>, signal?: AbortSignal) => Promise<unknown>
  shutdown?: () => Promise<void>
} = { creates: 0, destroys: 0, shutdowns: 0, clicked: false, calls: [] }

/** Reset the external fixture between independently owned test contexts. */
export function resetFixture(): void {
  fixture.creates = 0
  delete fixture.createOptions
  delete fixture.workerOptions
  fixture.destroys = 0
  fixture.shutdowns = 0
  fixture.clicked = false
  fixture.calls = []
  delete fixture.createError
  delete fixture.list
  delete fixture.call
  delete fixture.shutdown
}

/** The subset of the published SDK exercised by the provider. */
export class CuaDriver {
  static createPrivateWorker(options: PrivateWorkerOptions): CuaDriver {
    fixture.workerOptions = options
    return CuaDriver.create()
  }

  static create(options?: { embedded: boolean; claudeCodeCompatibility: boolean }): CuaDriver {
    fixture.creates += 1
    if (options) fixture.createOptions = options
    if (fixture.createError) throw fixture.createError
    return new CuaDriver()
  }

  async listToolsJson(options?: { signal: AbortSignal }): Promise<string> {
    return fixture.list ? fixture.list(options?.signal) : JSON.stringify(catalog)
  }

  async callTool(name: string, argsJson: string, options?: { signal: AbortSignal }): Promise<{ rawJson: string }> {
    const args = JSON.parse(argsJson) as Record<string, unknown>
    fixture.calls.push({ name, args, ...options ? { signal: options.signal } : {} })
    if (fixture.call) return { rawJson: JSON.stringify(await fixture.call(name, args, options?.signal)) }
    if (name === 'get_window_state') {
      return { rawJson: JSON.stringify({
        content: [
          { type: 'text', text: 'Cua Driver fixture window.' },
          { type: 'image', mimeType: 'image/png', data: screenshotBase64 },
        ],
        structuredContent: { window_id: 7, clicked: fixture.clicked },
      }) }
    }
    if (name === 'check_permissions') return { rawJson: JSON.stringify({ content: [{ type: 'text', text: 'Desktop permissions granted.' }], structuredContent: { source: { pid: 123 } } }) }
    if (name === 'drag') return { rawJson: JSON.stringify({ content: [{ type: 'text', text: 'Native drag posted; verify the drop.' }], structuredContent: { effect: 'unverifiable' } }) }
    if (name === 'click') fixture.clicked = true
    return { rawJson: JSON.stringify({ content: [{ type: 'text', text: name === 'click' ? 'Cua Driver fixture clicked.' : 'Desktop permissions granted.' }] }) }
  }

  async shutdown(): Promise<void> {
    fixture.shutdowns += 1
    await fixture.shutdown?.()
  }

  uniffiDestroy(): void {
    fixture.destroys += 1
  }
}
