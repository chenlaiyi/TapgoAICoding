import { describe, expect, it } from 'vitest'
import { resolveMobileOrigin } from '../src/mobile-origin.ts'

describe('mobile HTTPS origin', () => {
  it('keeps the Host private until an exact HTTPS authority is configured', () => {
    expect(resolveMobileOrigin(undefined)).toBeUndefined()
    expect(resolveMobileOrigin('https://mac.tailnet.example:8443')).toEqual({
      origin: 'https://mac.tailnet.example:8443', authority: 'mac.tailnet.example:8443',
    })
    for (const value of ['http://mac.tailnet.example', 'https://mac.tailnet.example/path',
      'https://mac.tailnet.example/?token=secret', 'https://user:pass@mac.tailnet.example', 'invalid']) {
      expect(() => resolveMobileOrigin(value)).toThrow('TAPGO_MOBILE_HTTPS_ORIGIN')
    }
  })
})
