/** Mobile pairing methods on the mounted Host connection. */
import { Context } from '@deepseek-ai/cordis'
import { expect, it } from 'vitest'
import { BrowserAuth } from '../src/browser-auth.ts'
import { HostConnectionService } from '../src/rpc-host.ts'
import { RecordCredentials } from './browser-credentials.ts'

it('issues, lists, and revokes a phone link through the Host connection', async () => {
  const ctx = new Context()
  const auth = await BrowserAuth.create(ctx, new RecordCredentials() as never, 30)
  const fiber = ctx.plugin((pluginCtx) => { new HostConnectionService(pluginCtx, [], auth) })
  await fiber.await()
  try {
    const connection = ctx.get('connection') as HostConnectionService
    const created = await connection.createMobilePairing('https://phone.example/', 'Phone')
    expect(new URL(created.url).host).toBe('phone.example')
    expect(connection.listMobilePairings()).toEqual([created.pairing])
    await connection.revokeMobilePairing(created.pairing.id)
    expect(connection.listMobilePairings()).toEqual([])
  } finally {
    await fiber.dispose()
  }
})
