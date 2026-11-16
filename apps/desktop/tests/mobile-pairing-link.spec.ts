import { describe, expect, it } from 'vitest'
import { pairingLink } from '../src/mobile-pairing.ts'

describe('mobile pairing link', () => {
  it('carries the fallback route inside the primary link', () => {
    const link = pairingLink('http://192.168.1.20:19389/?name=Mac&token=lan',
      'https://mac.remote.example/?name=Mac&token=relay')
    const parsed = new URL(link)
    expect(parsed.origin).toBe('http://192.168.1.20:19389')
    expect(parsed.searchParams.get('token')).toBe('lan')
    expect(parsed.searchParams.get('name')).toBe('Mac')
    const fallback = new URL(parsed.searchParams.get('fallback') ?? '')
    expect(fallback.origin).toBe('https://mac.remote.example')
    expect(fallback.searchParams.get('token')).toBe('relay')
  })

  it('keeps a single-route link unchanged', () => {
    expect(pairingLink('https://mac.remote.example/?token=relay')).toBe('https://mac.remote.example/?token=relay')
  })
})
