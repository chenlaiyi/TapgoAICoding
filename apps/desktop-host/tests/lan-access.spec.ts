import { describe, expect, it } from 'vitest'
import { lanAddress, resolveLanAccess } from '../src/lan-access.ts'

function interfaces(entries: readonly { address: string; family: string; internal: boolean }[]): ReturnType<typeof import('node:os').networkInterfaces> {
  return { en0: entries.map(entry => ({ ...entry, netmask: '255.255.255.0', mac: '00:00:00:00:00:00', cidr: null })) }
}

describe('LAN access', () => {
  it('picks the first private, non-internal IPv4 address', () => {
    expect(lanAddress(interfaces([]))).toBeUndefined()
    expect(lanAddress(interfaces([{ address: '127.0.0.1', family: 'IPv4', internal: true }]))).toBeUndefined()
    expect(lanAddress(interfaces([{ address: '8.8.8.8', family: 'IPv4', internal: false }]))).toBeUndefined()
    expect(lanAddress(interfaces([
      { address: '127.0.0.1', family: 'IPv4', internal: true },
      { address: 'fe80::1', family: 'IPv6', internal: false },
      { address: '192.168.1.20', family: 'IPv4', internal: false },
      { address: '10.0.0.7', family: 'IPv4', internal: false },
    ]))).toBe('192.168.1.20')
  })

  it('resolves the default LAN origin and honours the environment override', () => {
    expect(resolveLanAccess({}, 19389)?.port ?? 19389).toBe(19389)
    expect(resolveLanAccess({ TAPGO_MOBILE_LAN_ORIGIN: 'off' })).toBeUndefined()
    expect(resolveLanAccess({ TAPGO_MOBILE_LAN_ORIGIN: 'http://10.0.0.7:19389/' })).toEqual({
      origin: 'http://10.0.0.7:19389', authority: '10.0.0.7:19389', address: '10.0.0.7', port: 19389,
    })
    for (const value of ['https://10.0.0.7:19389/', 'http://8.8.8.8:19389/', 'http://10.0.0.7/path', 'nonsense']) {
      expect(() => resolveLanAccess({ TAPGO_MOBILE_LAN_ORIGIN: value })).toThrow('TAPGO_MOBILE_LAN_ORIGIN')
    }
  })
})
