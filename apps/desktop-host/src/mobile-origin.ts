/** Validate the private HTTPS proxy origin used by the iOS companion.
 * @param value - Configured HTTPS origin, or absent when mobile access is disabled.
 * @returns The origin and HTTP authority for Host trust configuration.
 */
export function resolveMobileOrigin(value: string | undefined): { origin: string; authority: string } | undefined {
  if (value === undefined) return undefined
  let url: URL
  try { url = new URL(value) } catch { throw new Error('TAPGO_MOBILE_HTTPS_ORIGIN must be an HTTPS origin') }
  if (url.protocol !== 'https:' || url.origin !== value || url.username !== '' || url.password !== '') {
    throw new Error('TAPGO_MOBILE_HTTPS_ORIGIN must be an HTTPS origin without credentials or a path')
  }
  return { origin: value, authority: url.host }
}
