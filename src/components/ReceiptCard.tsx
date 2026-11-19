import { useState } from 'react'
import { Check, Copy, Send, Share2, ShieldCheck } from 'lucide-react'
import { NO_DEBT_HF } from '@/lib/pilot'
import { usd, ago } from '@/lib/format'

export interface ReceiptData {
  tier: number
  amount: bigint
  hfBefore?: bigint
  hfAfter?: bigint
  ts?: number
}

const hfText = (v?: bigint) => (v === undefined ? '' : v > BigInt(NO_DEBT_HF) ? 'Earn mode' : `${(Number(v) / 10000).toFixed(2)}x`)

export function receiptSentence(r: ReceiptData): string {
  const move = r.hfBefore !== undefined && r.hfAfter !== undefined ? ` My safety buffer went from ${hfText(r.hfBefore)} to ${hfText(r.hfAfter)}.` : ''
  return `InkPilot's Safe Mode protected my position before it got close to liquidation.${move}`
}

/** A shareable proof of a real, onchain protection action. Only real data is shown. */
export function ReceiptCard({ receipt, link }: { receipt: ReceiptData; link?: string }) {
  const [copied, setCopied] = useState(false)
  const text = receiptSentence(receipt)
  const canShare = typeof navigator !== 'undefined' && 'share' in navigator
  const enc = (s: string) => encodeURIComponent(s)
  const copy = async () => {
    if (!link) return
    await navigator.clipboard.writeText(`${text} ${link}`)
    setCopied(true)
    setTimeout(() => setCopied(false), 1800)
  }
  const nativeShare = async () => {
    if (!link) return copy()
    try {
      await navigator.share({ text, url: link })
    } catch {
      /* cancelled */
    }
  }
  return (
    <div className="rounded-2xl p-[1px]" style={{ background: 'linear-gradient(135deg, rgba(91,140,255,.7), rgba(155,107,255,.7))' }}>
      <div className="rounded-2xl p-5" style={{ background: '#0c0e1d' }}>
        <div className="flex items-center gap-2" style={{ color: 'var(--green)' }}>
          <ShieldCheck size={18} /> <span className="ip-label" style={{ color: 'var(--green)' }}>Liquidation dodged</span>
        </div>
        <p className="mt-3 text-lg font-bold leading-snug ip-display">{text}</p>
        <div className="mt-4 grid grid-cols-3 gap-2 text-center">
          <div className="ip-inner p-2"><p className="ip-label">Used</p><p className="tabular font-bold">{usd(receipt.amount)}</p></div>
          <div className="ip-inner p-2"><p className="ip-label">Before</p><p className="tabular font-bold">{hfText(receipt.hfBefore) || '-'}</p></div>
          <div className="ip-inner p-2"><p className="ip-label">After</p><p className="tabular font-bold">{hfText(receipt.hfAfter) || '-'}</p></div>
        </div>
        {receipt.ts && <p className="mt-3 text-xs" style={{ color: 'var(--muted)' }}>{ago(receipt.ts)} · verified onchain</p>}
        <div className="mt-4 flex flex-wrap gap-2">
          <a className={`ip-btn ip-ghost flex items-center gap-2 ${link ? '' : 'pointer-events-none opacity-50'}`} target="_blank" rel="noopener noreferrer" href={link ? `https://twitter.com/intent/tweet?text=${enc(text)}&url=${enc(link)}` : undefined} style={{ lineHeight: '44px', padding: '0 16px' }}>
            <Share2 size={16} /> Post on X
          </a>
          <a className={`ip-btn ip-ghost flex items-center gap-2 ${link ? '' : 'pointer-events-none opacity-50'}`} target="_blank" rel="noopener noreferrer" href={link ? `https://t.me/share/url?url=${enc(link)}&text=${enc(text)}` : undefined} style={{ lineHeight: '44px', padding: '0 16px' }}>
            <Send size={16} /> Telegram
          </a>
          <button className="ip-btn ip-ghost flex items-center gap-2" disabled={!link} onClick={() => void (canShare ? nativeShare() : copy())}>
            {copied ? <Check size={16} /> : <Copy size={16} />} {copied ? 'Copied' : 'Copy'}
          </button>
        </div>
      </div>
    </div>
  )
}
