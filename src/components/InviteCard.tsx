import { useState } from 'react'
import { Check, Copy, Gift } from 'lucide-react'

export function InviteCard({ link }: { link?: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <section className="ip-card p-5" aria-label="Invite friends">
      <div className="flex items-center gap-2"><Gift size={18} color="var(--purple)" /><p className="ip-label">Invite friends</p></div>
      <p className="mt-2 text-sm leading-relaxed" style={{ color: 'var(--muted)' }}>
        Your link records you as the inviter when a friend opens their account. Invite rewards are not live yet, so nothing is promised here.
      </p>
      <div className="mt-3 flex gap-2">
        <input readOnly className="ip-input text-sm" value={link ?? 'Preparing your link...'} aria-label="Your invite link" />
        <button
          className="ip-btn ip-ghost"
          disabled={!link}
          aria-label="Copy invite link"
          onClick={() => {
            if (!link) return
            void navigator.clipboard.writeText(link).then(() => {
              setCopied(true)
              setTimeout(() => setCopied(false), 1800)
            })
          }}
        >
          {copied ? <Check size={16} /> : <Copy size={16} />}
        </button>
      </div>
    </section>
  )
}
