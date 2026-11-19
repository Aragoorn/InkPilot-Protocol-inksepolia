import { ShieldAlert, ShieldCheck, ShieldHalf } from 'lucide-react'
import { NO_DEBT_HF, securityOf, type Snapshot } from '@/lib/pilot'

const COLORS = { green: 'var(--green)', yellow: 'var(--amber)', red: 'var(--red)' } as const

interface Props {
  snapshot: Snapshot
  busy: boolean
  onProtect: () => void
}

export function SecurityCard({ snapshot, busy, onProtect }: Props) {
  const sec = securityOf(snapshot)
  const color = COLORS[sec.light]
  const Icon = sec.light === 'green' ? ShieldCheck : sec.light === 'yellow' ? ShieldHalf : ShieldAlert
  const hasDebt = snapshot.debt > 0n
  const hf = Number(snapshot.hfBps)
  const buffer = hasDebt && hf < NO_DEBT_HF ? Math.max(0, Math.min(100, ((hf / 10000 - 1) / 0.8) * 100)) : 100
  return (
    <section className="ip-card p-5" aria-label="Your security">
      <div className="flex items-start gap-3">
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full" style={{ background: `${color}22`, boxShadow: `0 0 24px ${color}44` }}>
          <Icon size={22} color={color} />
        </span>
        <div className="min-w-0 flex-1">
          <p className="ip-label">Your security</p>
          <h3 className="text-xl font-bold ip-display">{sec.title}</h3>
          <p className="mt-1 text-sm leading-relaxed" style={{ color: 'var(--muted)' }}>{sec.body}</p>
        </div>
      </div>
      {hasDebt && (
        <div className="mt-4">
          <div className="mb-1 flex justify-between text-xs" style={{ color: 'var(--muted)' }}>
            <span>Safety buffer</span>
            <span className="tabular">{(hf / 10000).toFixed(2)}x of the minimum</span>
          </div>
          <div className="h-2 overflow-hidden rounded-full" style={{ background: 'var(--surface-strong)' }}>
            <div className="h-full rounded-full" style={{ width: `${buffer}%`, background: color, transition: 'width .4s ease' }} />
          </div>
        </div>
      )}
      {hasDebt && sec.light !== 'green' && (
        <button className="ip-btn ip-ghost mt-4 w-full" onClick={onProtect} disabled={busy}>
          Run protection now
        </button>
      )}
    </section>
  )
}
