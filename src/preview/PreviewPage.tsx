import { useState } from 'react'
import { Info } from 'lucide-react'
import { BalanceCard } from '@/components/BalanceCard'
import { SecurityCard } from '@/components/SecurityCard'
import { ProfitToggle } from '@/components/ProfitToggle'
import { ProtectionCard } from '@/components/ProtectionCard'
import { ActivityList } from '@/components/ActivityList'
import { ReceiptCard } from '@/components/ReceiptCard'
import { InviteCard } from '@/components/InviteCard'
import { LockedBanner } from '@/components/LockedBanner'
import { describe, type Activity } from '@/hooks/useActivity'
import type { MarketStatusName, Snapshot } from '@/lib/pilot'

/**
 * Design preview. Every number on this page is SAMPLE data so the screens can be reviewed before any
 * contract exists. It is only reachable with ?preview=1 and never reads or writes the chain.
 */
const M = 1_000_000n
const base: Snapshot = {
  collateral: 1600n * M, debt: 800n * M, reserve: 200n * M, equity: 800n * M, invested: 800n * M,
  netDeposits: 1000n * M, lifetimeProfit: 3_420_000n, hfBps: 16000n, leverageBps: 20000n,
  status: 0, profitMode: 0, maxTip: 0n, lastProtectAt: 0n, liquidationsAllowed: true,
}

const SCENES: { id: string; label: string; snap: Snapshot; market: MarketStatusName }[] = [
  { id: 'earn', label: 'Earn mode', market: 'Active', snap: { ...base, collateral: 1000n * M, debt: 0n, reserve: 0n, equity: 1000n * M, invested: 1000n * M, hfBps: 65535n, leverageBps: 10000n, lifetimeProfit: 2_100_000n } },
  { id: 'ok', label: 'Protected', market: 'Active', snap: base },
  { id: 'watch', label: 'Watching', market: 'Active', snap: { ...base, hfBps: 13500n, lifetimeProfit: -1_250_000n } },
  { id: 'risk', label: 'Needs protection', market: 'Active', snap: { ...base, hfBps: 11800n, lifetimeProfit: -9_800_000n } },
  { id: 'locked', label: 'Safe but locked', market: 'Frozen', snap: { ...base, status: 1 } },
]

const T = 1_700_000_000
const NOW = Math.floor(Date.now() / 1000)
const sample = (kind: string, args: Record<string, unknown>, id: string, ago: number): Activity => {
  const d = describe(kind, args)
  return { id, block: 0n, ts: NOW - ago, kind, tier: d.tier, amount: d.amount, text: d.text, tx: `0x${T}` }
}
const ACTIVITY: Activity[] = [
  sample('Protected', { tier: 1, amount: 50n * M }, 'a', 5400),
  sample('Boosted', { leverageBps: 20000n }, 'b', 86000),
  sample('ReserveFunded', { amount: 200n * M }, 'c', 90000),
  sample('Deposited', { amount: 800n * M }, 'd', 91000),
]

export function PreviewPage() {
  const [scene, setScene] = useState(SCENES[1].id)
  const [mode, setMode] = useState<0 | 1>(0)
  const s = SCENES.find((x) => x.id === scene) ?? SCENES[1]
  const snap = { ...s.snap, profitMode: mode }
  const locked = s.market !== 'Active'
  const noop = () => undefined
  return (
    <div className="mx-auto max-w-5xl px-4 pb-24 pt-6">
      <div className="ip-card flex items-start gap-3 p-4" style={{ borderColor: 'rgba(91,140,255,.45)' }}>
        <Info size={18} color="var(--blue)" className="mt-0.5 shrink-0" />
        <p className="text-sm leading-relaxed"><b>Design preview.</b> Every value here is sample data, not an account. Pick a state to see how the dashboard looks and feels. <a className="underline" href="/">Back to the site</a>.</p>
      </div>
      <div role="tablist" aria-label="Preview state" className="mt-4 flex gap-2 overflow-x-auto pb-1">
        {SCENES.map((x) => (
          <button key={x.id} role="tab" aria-selected={x.id === scene} onClick={() => setScene(x.id)} className="ip-btn shrink-0 !px-4" style={{ background: x.id === scene ? 'rgba(91,140,255,.18)' : 'var(--surface)', border: `1px solid ${x.id === scene ? 'var(--blue)' : 'var(--line)'}` }}>
            {x.label}
          </button>
        ))}
      </div>
      <div className="mt-4 grid gap-4 lg:grid-cols-[1.1fr_1fr]">
        {locked && <div className="lg:col-span-2"><LockedBanner market={s.market} /></div>}
        <div className="space-y-4">
          <BalanceCard snapshot={snap} onInvest={noop} onWithdraw={noop} />
          <SecurityCard snapshot={snap} busy={false} onProtect={noop} />
          <ProfitToggle mode={mode} busy={false} onChange={setMode} />
          <ActivityList items={ACTIVITY} loading={false} />
        </div>
        <div className="space-y-4">
          <ReceiptCard link={window.location.origin} receipt={{ tier: 1, amount: 50n * M, hfBefore: 12400n, hfAfter: 14500n, ts: NOW - 5400 }} />
          <ProtectionCard snapshot={snap} busy={false} locked={locked} onBoost={noop} onFundReserve={noop} />
          <InviteCard link={window.location.origin} />
        </div>
      </div>
    </div>
  )
}
