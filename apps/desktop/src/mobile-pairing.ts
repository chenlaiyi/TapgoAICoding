/** Local pairing document for the running Desktop Host. */

import QRCode from 'qrcode'
import type { DesktopLocale } from './locale.ts'

function escapeHtml(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;')
}

/** Build a self-contained, sandboxed document with the current Host URL. */
export async function mobilePairingPage(url: string, messages: DesktopLocale['messages']): Promise<string> {
  const qr = await QRCode.toDataURL(url, { width: 320, margin: 2, errorCorrectionLevel: 'M' })
  const title = escapeHtml(messages.connectMobileMenu)
  const detail = escapeHtml(messages.connectMobileDetail)
  const link = escapeHtml(url)
  const copy = escapeHtml(messages.copyMobileLink)
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{font:14px -apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:24px;background:#f8f9fc;color:#171923;text-align:center}h1{font-size:20px;margin:0 0 10px}p{line-height:1.5;color:#596171;margin:0 0 14px}img{width:280px;height:280px;background:#fff;border-radius:16px;padding:12px;box-sizing:border-box}textarea{box-sizing:border-box;width:100%;height:72px;margin:14px 0 10px;padding:10px;border:1px solid #d6d9e2;border-radius:10px;resize:none;word-break:break-all;font:12px ui-monospace,SFMono-Regular,monospace}button{border:0;border-radius:10px;background:#171923;color:white;padding:10px 20px;font:inherit;cursor:pointer}</style></head><body><h1>${title}</h1><p>${detail}</p><img src="${qr}" alt="${title}"><textarea id="link" readonly>${link}</textarea><button id="copy">${copy}</button><script>document.getElementById('copy').addEventListener('click',()=>{const field=document.getElementById('link');field.select();document.execCommand('copy')})</script></body></html>`
}
