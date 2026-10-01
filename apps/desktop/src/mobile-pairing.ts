/** Local pairing document for the running Desktop Host. */

import QRCode from 'qrcode'
import type { DesktopLocale } from './locale.ts'
import type { DesktopMobilePairing } from './host-process.ts'

function escapeHtml(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;')
}

/** Build a sandboxed pairing document with the current Host URL and editable computer name.
 * @param url - Authenticated Host URL carrying the display name.
 * @param name - Current Mac computer name.
 * @param messages - Localized Desktop copy.
 * @param version - Actual running Desktop version.
 * @param pairings - Active revocable phone links, without tokens.
 * @returns Self-contained pairing HTML.
 */
export async function mobilePairingPage(url: string, name: string, messages: DesktopLocale['messages'], version = '',
  pairings: readonly DesktopMobilePairing[] = []): Promise<string> {
  const qr = await QRCode.toDataURL(url, { width: 320, margin: 2, errorCorrectionLevel: 'M' })
  const title = escapeHtml(messages.connectMobileMenu)
  const detail = escapeHtml(messages.connectMobileDetail)
  const link = escapeHtml(url)
  const copy = escapeHtml(messages.copyMobileLink)
  const label = escapeHtml(messages.mobileComputerName)
  const save = escapeHtml(messages.saveMobileComputerName)
  const value = escapeHtml(name)
  const checking = escapeHtml(messages.mobileConnectionChecking)
  const retry = escapeHtml(messages.mobileConnectionRetry)
  const versionText = version === '' ? '' : `<small>${escapeHtml(messages.mobileConnectionVersion.replace('{version}', version))}</small>`
  const pairingRows = pairings.map(pairing => `<li><span>${escapeHtml(pairing.name)} · ${escapeHtml(pairing.id.slice(0, 6))}</span><button type="button" data-revoke="${escapeHtml(pairing.id)}">${escapeHtml(messages.mobileRevoke)}</button></li>`).join('')
  const legacyNotice = escapeHtml(messages.mobileLegacyNotice)
  const pairingList = pairings.length === 0 ? '' : `<section><h2>${escapeHtml(messages.mobilePairings)}</h2><ul>${pairingRows}</ul></section>`
  const newPairing = pairings.length === 0 ? '' : `<form action="tapgo-pairing://new" method="get"><label for="phone-name">${escapeHtml(messages.mobilePairingLabel)}</label><input id="phone-name" name="name" maxlength="80" required placeholder="${escapeHtml(messages.mobilePairingName)}"><button type="submit">${escapeHtml(messages.mobileAddPairing)}</button></form>`
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action tapgo-pairing:"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{font:14px -apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:20px;background:#f8f9fc;color:#171923;text-align:center}h1{font-size:20px;margin:0 0 10px}p{line-height:1.5;color:#596171;margin:0 0 12px}form{display:flex;align-items:center;gap:8px;text-align:left;margin-bottom:10px}label{font-size:13px;white-space:nowrap}input{min-width:0;flex:1;padding:9px;border:1px solid #d6d9e2;border-radius:10px;font:inherit}img{width:260px;height:260px;background:#fff;border-radius:16px;padding:12px;box-sizing:border-box}textarea{box-sizing:border-box;width:100%;height:66px;margin:10px 0;padding:10px;border:1px solid #d6d9e2;border-radius:10px;resize:none;word-break:break-all;font:12px ui-monospace,SFMono-Regular,monospace}button{border:0;border-radius:10px;background:#171923;color:white;padding:9px 14px;font:inherit;white-space:nowrap}.status{display:flex;align-items:center;justify-content:space-between;gap:10px;margin:14px 0;padding:10px 12px;border-radius:12px;background:#fff;text-align:left}.status button,li button{background:transparent;color:#2457a7;padding:4px}.meta{display:block;color:#596171;margin-top:8px}section{text-align:left;margin-top:18px}h2{font-size:14px;font-weight:500}ul{list-style:none;padding:0}li{display:flex;align-items:center;justify-content:space-between;padding:6px 0;border-top:1px solid #d6d9e2}@media(prefers-color-scheme:dark){body{background:#171923;color:#f8f9fc}p,.meta{color:#b6bfd0}.status{background:#252a35}input,textarea{background:#252a35;color:#f8f9fc;border-color:#4b5364}li{border-color:#4b5364}.status button,li button{color:#82b1ff}}</style></head><body><h1>${title}</h1><form action="tapgo-pairing://computer-name" method="get"><label for="name">${label}</label><input id="name" name="value" maxlength="80" required value="${value}"><button type="submit">${save}</button></form><p>${detail}</p><div class="status"><span id="connection-status" role="status">${checking}</span><button id="recheck" type="button">${retry}</button></div><img src="${qr}" alt="${title}"><textarea id="link" readonly>${link}</textarea><button id="copy">${copy}</button><span class="meta">${versionText}</span>${pairingList}${newPairing}<p class="legacy">${legacyNotice}</p><script>document.getElementById('copy').addEventListener('click',()=>{const field=document.getElementById('link');field.select();document.execCommand('copy')});document.getElementById('recheck').addEventListener('click',()=>{location.href='tapgo-pairing://check-connection'});document.querySelectorAll('[data-revoke]').forEach(button=>button.addEventListener('click',()=>{location.href='tapgo-pairing://revoke?id='+encodeURIComponent(button.dataset.revoke)}))</script></body></html>`
}
