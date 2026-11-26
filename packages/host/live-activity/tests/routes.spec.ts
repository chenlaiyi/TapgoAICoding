/** Live Activity routes rely on WebServer admission and never reach Connection internals. */
import { Context } from '@deepseek-ai/cordis'
import { afterEach, expect, it, vi } from 'vitest'
import { IncomingMessage, type ServerResponse } from 'node:http'
import { Socket } from 'node:net'
import type { WebRoute, WebServer } from '@deepseek-ai/dsh-host-webserver'
import LiveActivityPush from '../src/index.ts'

type RoutePeer = Parameters<WebRoute['handler']>[2]

const roots: Context[] = []
afterEach(async () => {
  vi.unstubAllEnvs()
  for (const ctx of roots.splice(0)) await ctx.fiber.dispose()
})

async function mounted() {
  for (const name of ['TAPGO_APNS_BUNDLE_ID', 'TAPGO_APNS_TEAM_ID', 'TAPGO_APNS_KEY_ID', 'TAPGO_APNS_KEY_FILE']) {
    vi.stubEnv(name, undefined)
  }
  const ctx = new Context(); roots.push(ctx)
  const routes: WebRoute[] = []
  ctx.provide('webServer', {
    register(route: WebRoute) { routes.push(route); return () => { routes.splice(routes.indexOf(route), 1) } },
  } as WebServer)
  await ctx.plugin(LiveActivityPush, {}).await()
  return routes
}

function post(body: string): IncomingMessage {
  const req = new IncomingMessage(new Socket())
  req.method = 'POST'
  req.url = '/live-activity/register'
  req.push(body)
  req.push(null)
  return req
}

function response() {
  const state: { status?: number; body?: string | undefined } = {}
  const done = Promise.withResolvers<undefined>()
  const res = {
    writeHead(status: number) { state.status = status; return res },
    end(body?: string) { state.body = body; done.resolve(undefined) },
  } as ServerResponse
  return { res, state, done: done.promise }
}

it('registers both routes with the default required admission', async () => {
  const routes = await mounted()
  expect(routes.map(route => [route.path, route.auth])).toEqual([
    ['/live-activity/register', undefined],
    ['/live-activity/unregister', undefined],
  ])
})

it('refuses a request WebServer passed without an admitted Peer', async () => {
  const [register] = await mounted()
  const { res, state, done } = response()
  void register!.handler(post('{}'), res)
  await done
  expect(state).toEqual({ status: 401, body: 'unauthorized' })
})

it('reads the body of an admitted request instead of throwing', async () => {
  const [register] = await mounted()
  const { res, state, done } = response()
  void register!.handler(post('{}'), res, { id: 'phone' } as RoutePeer)
  await done
  expect(state.status).toBe(400)
})
