import { Lock } from 'lucide-react'
import type { MarketStatusName } from '@/lib/pilot'

/** "Safe but locked": the market is frozen or paused, so nothing was sent and nothing reverts. */
export function LockedBanner({ market }: { market: MarketStatusName }) {
  return (
    <div className="ip-card flex items-start gap-3 p-4" style={{ borderColor: 'rgba(255,200,87,.4)' }} role="status">
      <Lock size={18} color="var(--amber)" className="mt-0.5 shrink-0" />
      <p className="text-sm leading-relaxed">
        <b>Safe but locked.</b> The lending market is {market === 'Paused' ? 'paused' : 'not fully open'} right now, so new deposits and Boost wait. Your position is untouched{market === 'Frozen' ? ' and you can still withdraw' : ''}.
      </p>
    </div>
  )
}
