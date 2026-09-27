/** Local pairing document for the running Desktop Host. */

import QRCode from 'qrcode'
import type { DesktopLocale } from './locale.ts'

function escapeHtml(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;')
}

/** Build a sandboxed pairing document with the current Host URL and editable computer name.
 * @param url - Authenticated Host URL carrying the display name.
 * @param name - Current Mac computer name.
 * @param messages - Localized Desktop copy.
 * @returns Self-contained pairing HTML.
 */
export async function mobilePairingPage(url: string, name: string, messages: DesktopLocale['messages']): Promise<string> {
  const qr = await QRCode.toDataURL(url, { width: 320, margin: 2, errorCorrectionLevel: 'M' })
  const title = escapeHtml(messages.connectMobileMenu)
  const detail = escapeHtml(messages.connectMobileDetail)
  const link = escapeHtml(url)
  const copy = escapeHtml(messages.copyMobileLink)
  const label = escapeHtml(messages.mobileComputerName)
  const save = escapeHtml(messages.saveMobileComputerName)
  const value = escapeHtml(name)
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action tapgo-pairing:"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{font:14px -apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:20px;background:#f8f9fc;color:#171923;text-align:center}h1{font-size:20px;margin:0 0 10px}p{line-height:1.5;color:#596171;margin:0 0 12px}form{display:flex;align-items:center;gap:8px;text-align:left;margin-bottom:10px}label{font-size:13px;white-space:nowrap}input{min-width:0;flex:1;padding:9px;border:1px solid #d6d9e2;border-radius:10px;font:inherit}img{width:260px;height:260px;background:#fff;border-radius:16px;padding:12px;box-sizing:border-box}textarea{box-sizing:border-box;width:100%;height:66px;margin:10px 0;padding:10px;border:1px solid #d6d9e2;border-radius:10px;resize:none;word-break:break-all;font:12px ui-monospace,SFMono-Regular,monospace}button{border:0;border-radius:10px;background:#171923;color:white;padding:9px 14px;font:inherit;white-space:nowrap}</style></head><body><h1>${title}</h1><form action="tapgo-pairing://computer-name" method="get"><label for="name">${label}</label><input id="name" name="value" maxlength="80" required value="${value}"><button type="submit">${save}</button></form><p>${detail}</p><img src="${qr}" alt="${title}"><textarea id="link" readonly>${link}</textarea><button id="copy">${copy}</button><script>document.getElementById('copy').addEventListener('click',()=>{const field=document.getElementById('link');field.select();document.execCommand('copy')})</script></body></html>`
}
