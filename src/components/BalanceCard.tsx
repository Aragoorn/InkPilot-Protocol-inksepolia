import { ArrowDownToLine, ArrowUpFromLine } from 'lucide-react'
import { usd, signedUsd } from '@/lib/format'
import type { Snapshot } from '@/lib/pilot'

interface Props {
  snapshot: Snapshot
  onInvest: () => void
  onWithdraw: () => void
}

export function BalanceCard({ snapshot, onInvest, onWithdraw }: Props) {
  const total = snapshot.equity + snapshot.reserve
  const profit = snapshot.lifetimeProfit
  return (
    <section className="ip-card p-5 sm:p-6" aria-label="Your balance">
      <p className="ip-label">Your balance</p>
      <p className="tabular mt-1 text-5xl font-extrabold ip-display">{usd(total)}</p>
      <div className="mt-4 grid grid-cols-2 gap-3">
        <div className="ip-inner p-3">
          <p className="ip-label">Profit earned</p>
          <p className="tabular mt-1 text-xl font-bold" style={{ color: profit >= 0n ? 'var(--green)' : 'var(--red)' }}>{signedUsd(profit, 4)}</p>
        </div>
        <div className="ip-inner p-3">
          <p className="ip-label">Savings and reserve</p>
          <p className="tabular mt-1 text-xl font-bold">{usd(snapshot.reserve)}</p>
        </div>
      </div>
      <div className="mt-4 grid grid-cols-2 gap-3">
        <button className="ip-btn ip-primary flex items-center justify-center gap-2" onClick={onInvest}>
          <ArrowDownToLine size={18} /> Invest more
        </button>
        <button className="ip-btn ip-ghost flex items-center justify-center gap-2" onClick={onWithdraw}>
          <ArrowUpFromLine size={18} /> Withdraw
        </button>
      </div>
    </section>
  )
}
