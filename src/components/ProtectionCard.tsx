import { useState } from 'react'
import { Zap } from 'lucide-react'
import { usd } from '@/lib/format'
import type { Snapshot } from '@/lib/pilot'

interface Props {
  snapshot: Snapshot
  busy: boolean
  locked: boolean
  onBoost: (on: boolean) => void
  onFundReserve: () => void
}

export function ProtectionCard({ snapshot, busy, locked, onBoost, onFundReserve }: Props) {
  const boosted = snapshot.debt > 0n
  const [confirm, setConfirm] = useState(false)
  return (
    <section className="ip-card p-5" aria-label="Boost and reserve">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="ip-label">Boost (optional)</p>
          <h3 className="text-lg font-bold">{boosted ? `Boost is on at ${(Number(snapshot.leverageBps) / 10000).toFixed(2)}x` : 'Earn more, with a little more risk'}</h3>
        </div>
        <Zap size={20} color="var(--purple)" />
      </div>
      <p className="mt-2 text-sm leading-relaxed" style={{ color: 'var(--muted)' }}>
        Boost borrows against your own deposit to earn on up to 2x your money. Safe Mode watches it, and your reserve ({usd(snapshot.reserve)}) is used first if your buffer shrinks.
      </p>
      {boosted ? (
        <button className="ip-btn ip-ghost mt-4 w-full" disabled={busy} onClick={() => onBoost(false)}>Turn Boost off</button>
      ) : confirm ? (
        <div className="ip-inner mt-4 p-3 text-sm">
          <p>Boost can be paused, but it does add risk. Without enough reserve, Safe Mode may have to move you back to Earn mode to stay safe.</p>
          <div className="mt-3 grid grid-cols-2 gap-2">
            <button className="ip-btn ip-primary" disabled={busy || locked} onClick={() => { setConfirm(false); onBoost(true) }}>I understand, turn on</button>
            <button className="ip-btn ip-ghost" onClick={() => setConfirm(false)}>Cancel</button>
          </div>
        </div>
      ) : (
        <button className="ip-btn ip-ghost mt-4 w-full" disabled={busy || locked} onClick={() => setConfirm(true)}>Turn on Boost (up to 2x)</button>
      )}
      <button className="ip-btn ip-ghost mt-3 w-full" disabled={busy} onClick={onFundReserve}>Add to protection reserve</button>
      {locked && <p className="mt-2 text-xs" style={{ color: 'var(--amber)' }}>Safe but locked: new borrowing is unavailable while the market is not fully open.</p>}
    </section>
  )
}
