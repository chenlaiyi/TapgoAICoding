/** APNs delivery for iOS Live Activities: registers per-activity push tokens and pushes turn progress. */

import { readFileSync, statSync } from 'node:fs'
import type { IncomingMessage, ServerResponse } from 'node:http'
import { Context, Service } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import type {} from '@deepseek-ai/dsh-host-webserver'
import type {} from '@deepseek-ai/dsh-session'
import {
  createApnsSender, isPushToken,
  type ApnsOutcome, type LiveActivityContentState,
} from './apns.ts'
import { applySessionEvent, type SessionEventLike, type SessionWork } from './detail.ts'

/** Route that registers one Live Activity push token. */
export const LIVE_ACTIVITY_REGISTER_PATH = '/live-activity/register'
/** Route that drops one Live Activity registration. */
export const LIVE_ACTIVITY_UNREGISTER_PATH = '/live-activity/unregister'

/** What the iOS app sends when its activity obtains a push token. */
export interface LiveActivityRegisterBody {
  readonly sessionId: string
  readonly activityId: string
  readonly token: string
  readonly title: string
  readonly project: string
}

/** Push delivery configuration; APNs credentials fall back to the TAPGO_APNS_* environment. */
export interface Config {
  /** Topic bundle identifier, normally the app's bundle id. */
  bundleId?: string
  /** Apple developer team identifier. */
  teamId?: string
  /** Key identifier of the APNs .p8 key. */
  keyId?: string
  /** Path to that .p8 key, readable only by its owner. */
  keyFile?: string
  /** APNs host family; production unless a development build needs the sandbox. */
  environment: 'development' | 'production'
  /** Minimum milliseconds between two pushes for the same Session. */
  minPushIntervalMs: number
  /** Seconds after which iOS may treat the pushed state as stale. */
  staleSeconds: number
}

/** Loader validation for Live Activity push delivery. */
export const Config: z<Partial<Config>, Config> = z.object({
  bundleId: z.string(),
  teamId: z.string(),
  keyId: z.string(),
  keyFile: z.string(),
  environment: z.union(['development', 'production']).default('production'),
  minPushIntervalMs: z.natural().min(1_000).max(60_000).default(5_000),
  staleSeconds: z.natural().min(30).max(900).default(120),
})

interface Registration extends LiveActivityRegisterBody {}

/** Trust surface consumed here; the browser-side connection package owns the full type. */
interface LiveActivityConnection {
  requestRejection(request: { readonly headers: IncomingMessage['headers'] }): 401 | 403 | undefined
}

/** The composition's connection service (typed locally: its package is browser-side). */
function connectionOf(ctx: Context): LiveActivityConnection {
  return Reflect.get(ctx, 'connection') as LiveActivityConnection
}

/** Request bodies here are small JSON objects; anything larger is hostile. */
const MAX_BODY_BYTES = 16 * 1024

function sendJson(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' })
  res.end(JSON.stringify(payload))
}

async function readJson(req: IncomingMessage): Promise<Record<string, unknown> | undefined> {
  const chunks: Buffer[] = []
  let size = 0
  for await (const chunk of req) {
    const bytes = typeof chunk === 'string' ? Buffer.from(chunk) : chunk as Buffer
    size += bytes.byteLength
    if (size > MAX_BODY_BYTES) return undefined
    chunks.push(bytes)
  }
  try {
    const value: unknown = JSON.parse(Buffer.concat(chunks).toString('utf8'))
    return typeof value === 'object' && value !== null && !Array.isArray(value)
      ? value as Record<string, unknown> : undefined
  } catch {
    return undefined
  }
}

function boundedString(value: unknown, max: number): string | undefined {
  if (typeof value !== 'string') return undefined
  const trimmed = value.trim()
  return trimmed === '' || trimmed.length > max ? undefined : trimmed
}

/** APNs credentials resolved from Config, then the launch environment. */
function resolveCredentials(config: Config): { bundleId: string; teamId: string; keyId: string; privateKey: string } | undefined {
  const bundleId = config.bundleId ?? process.env.TAPGO_APNS_BUNDLE_ID
  const teamId = config.teamId ?? process.env.TAPGO_APNS_TEAM_ID
  const keyId = config.keyId ?? process.env.TAPGO_APNS_KEY_ID
  const keyFile = config.keyFile ?? process.env.TAPGO_APNS_KEY_FILE
  if (bundleId === undefined || teamId === undefined || keyId === undefined || keyFile === undefined) return undefined
  if (process.platform !== 'win32' && (statSync(keyFile).mode & 0o077) !== 0) {
    throw new Error('live-activity: the APNs key file must be readable only by its owner')
  }
  return { bundleId, teamId, keyId, privateKey: readFileSync(keyFile, 'utf8') }
}

/**
 * Host half of iOS Live Activity updates. Mounting registers two authenticated
 * routes and one Session-event listener; with APNs credentials it forwards the
 * current turn state to the activity's push token while the phone is elsewhere.
 */
export default class LiveActivityPush extends Service {
  static inject = ['webServer', 'connection']
  static Config = Config

  private readonly sender: ReturnType<typeof createApnsSender> | undefined
  private readonly registrations = new Map<string, Registration>()
  private readonly bySession = new Map<string, Set<string>>()
  private readonly work = new Map<string, SessionWork>()
  private readonly pending = new Map<string, NodeJS.Timeout>()
  private readonly lastPush = new Map<string, number>()
  private readonly intervalMs: number

  constructor(ctx: Context, config: Config) {
    super(ctx, 'liveActivityPush')
    this.intervalMs = config.minPushIntervalMs
    const credentials = resolveCredentials(config)
    if (credentials === undefined) {
      ctx.logger.info('live-activity: APNs credentials are not configured; activities update only in the foreground')
    } else {
      this.sender = createApnsSender({ ...credentials, environment: config.environment,
        staleSeconds: config.staleSeconds })
    }
    ctx.effect(() => ctx.webServer.register({
      kind: 'exact',
      path: LIVE_ACTIVITY_REGISTER_PATH,
      handler: (req, res) => { void this.handleRegister(req, res) },
    }))
    ctx.effect(() => ctx.webServer.register({
      kind: 'exact',
      path: LIVE_ACTIVITY_UNREGISTER_PATH,
      handler: (req, res) => { void this.handleUnregister(req, res) },
    }))
    ctx.on('session/event', (session, event) => { this.observe(session.id, event as SessionEventLike) })
    ctx.effect(() => () => {
      for (const timer of this.pending.values()) clearTimeout(timer)
      this.pending.clear()
      this.registrations.clear()
      this.bySession.clear()
      this.work.clear()
      this.lastPush.clear()
    })
  }

  private rejected(req: IncomingMessage, res: ServerResponse): boolean {
    const rejection = connectionOf(this.ctx).requestRejection({ headers: req.headers })
    if (rejection === undefined) return false
    res.writeHead(rejection)
    res.end(rejection === 401 ? 'unauthorized' : 'forbidden')
    return true
  }

  private async handleRegister(req: IncomingMessage, res: ServerResponse): Promise<void> {
    if (req.method !== 'POST' || this.rejected(req, res)) return
    const body = await readJson(req)
    const sessionId = boundedString(body?.['sessionId'], 200)
    const activityId = boundedString(body?.['activityId'], 200)
    const token = boundedString(body?.['token'], 200)
    const title = boundedString(body?.['title'], 200)
    const project = boundedString(body?.['project'], 200)
    if (sessionId === undefined || activityId === undefined || token === undefined
      || title === undefined || project === undefined || !isPushToken(token)) {
      sendJson(res, 400, { accepted: false, reason: 'invalid' })
      return
    }
    if (this.sender === undefined) {
      sendJson(res, 200, { accepted: false, reason: 'unconfigured' })
      return
    }
    this.store({ sessionId, activityId, token, title, project })
    sendJson(res, 200, { accepted: true })
    this.schedule(sessionId, 0)
  }

  private async handleUnregister(req: IncomingMessage, res: ServerResponse): Promise<void> {
    if (req.method !== 'POST' || this.rejected(req, res)) return
    const body = await readJson(req)
    const activityId = boundedString(body?.['activityId'], 200)
    if (activityId === undefined) {
      sendJson(res, 400, { accepted: false, reason: 'invalid' })
      return
    }
    this.remove(activityId)
    sendJson(res, 200, { accepted: true })
  }

  private store(registration: Registration): void {
    this.remove(registration.activityId)
    this.registrations.set(registration.activityId, registration)
    const ids = this.bySession.get(registration.sessionId) ?? new Set<string>()
    ids.add(registration.activityId)
    this.bySession.set(registration.sessionId, ids)
  }

  private remove(activityId: string): void {
    const registration = this.registrations.get(activityId)
    if (registration === undefined) return
    this.registrations.delete(activityId)
    this.lastPush.delete(activityId)
    const ids = this.bySession.get(registration.sessionId)
    ids?.delete(activityId)
    if (ids !== undefined && ids.size === 0) this.bySession.delete(registration.sessionId)
  }

  private observe(sessionId: string, event: SessionEventLike): void {
    const next = applySessionEvent(this.work.get(sessionId), event)
    if (next === undefined) return
    this.work.set(sessionId, next)
    if (!next.running) {
      void this.finish(sessionId)
      return
    }
    this.schedule(sessionId, 0)
  }

  private stateOf(sessionId: string): LiveActivityContentState {
    const work = this.work.get(sessionId)
    return {
      startedAt: work?.startedAt ?? Math.floor(Date.now() / 1000),
      detail: work?.detail ?? '正在处理',
      running: work?.running ?? true,
    }
  }

  private schedule(sessionId: string, delayMs: number): void {
    if (this.sender === undefined) return
    const ids = this.bySession.get(sessionId)
    if (ids === undefined || ids.size === 0) return
    if (this.pending.has(sessionId)) return
    const now = Date.now()
    const earliest = Math.min(...[...ids].map(id => (this.lastPush.get(id) ?? 0) + this.intervalMs))
    const wait = Math.max(delayMs, earliest - now)
    if (wait <= 0) {
      void this.flush(sessionId)
      return
    }
    const timer = setTimeout(() => {
      this.pending.delete(sessionId)
      void this.flush(sessionId)
    }, wait)
    timer.unref?.()
    this.pending.set(sessionId, timer)
  }

  private async flush(sessionId: string): Promise<void> {
    const sender = this.sender
    if (sender === undefined) return
    const ids = this.bySession.get(sessionId)
    if (ids === undefined) return
    const state = this.stateOf(sessionId)
    for (const activityId of [...ids]) {
      const registration = this.registrations.get(activityId)
      if (registration === undefined) continue
      this.lastPush.set(activityId, Date.now())
      const outcome = await sender.update(registration.token, state)
      this.settle(activityId, outcome)
    }
  }

  private async finish(sessionId: string): Promise<void> {
    const ids = this.bySession.get(sessionId)
    if (ids === undefined) return
    const timer = this.pending.get(sessionId)
    if (timer !== undefined) {
      clearTimeout(timer)
      this.pending.delete(sessionId)
    }
    const state = this.stateOf(sessionId)
    for (const activityId of [...ids]) {
      const registration = this.registrations.get(activityId)
      this.remove(activityId)
      if (registration === undefined || this.sender === undefined) continue
      await this.sender.end(registration.token, { ...state, running: false })
    }
    this.work.delete(sessionId)
  }

  private settle(activityId: string, outcome: ApnsOutcome): void {
    if (outcome === 'unregistered') this.remove(activityId)
  }
}
