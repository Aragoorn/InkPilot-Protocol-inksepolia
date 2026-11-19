import { useState } from 'react'
import { toast } from 'sonner'
import { erc20Abi, type Address } from 'viem'
import { pilotAccountAbi, demoPoolAbi } from '@/abi/pilot'
import { LAB_ENABLED, POOL } from '@/lib/pilot'
import { USDC, useInviteLink, useMarketStatus, usePilot, useReferral } from '@/hooks/usePilot'
import { useTxFlow } from '@/hooks/useTxFlow'
import { useStartPlan } from '@/hooks/useStartPlan'
import { useActivity } from '@/hooks/useActivity'
import { BalanceCard } from '@/components/BalanceCard'
import { SecurityCard } from '@/components/SecurityCard'
import { ProfitToggle } from '@/components/ProfitToggle'
import { ProtectionCard } from '@/components/ProtectionCard'
import { ActivityList } from '@/components/ActivityList'
import { AmountSheet } from '@/components/AmountSheet'
import { ReceiptCard } from '@/components/ReceiptCard'
import { InviteCard } from '@/components/InviteCard'
import { DemoControls } from '@/components/DemoControls'
import { Onboarding } from '@/components/Onboarding'
import { LockedBanner } from '@/components/LockedBanner'

type Sheet = 'invest' | 'withdraw' | 'reserve' | null

export function Dashboard() {
  const pilot = usePilot()
  const { status: market } = useMarketStatus()
  const flow = useTxFlow()
  const referrer = useReferral(pilot.address)
  const startPlan = useStartPlan(flow.write, flow.run, referrer)
  const activity = useActivity(pilot.account)
  const invite = useInviteLink(pilot.address)
  const [sheet, setSheet] = useState<Sheet>(null)

  const snap = pilot.snapshot
  const account = pilot.account
  const marketKnown = market !== undefined
  const locked = marketKnown && market !== 'Active'
  const busy = flow.status.running

  const finish = async (ok: boolean, done: string) => {
    if (ok) {
      toast.success(done)
      await pilot.refresh()
      await activity.refetch()
    }
    return ok
  }
  const single = async (label: string, run: () => Promise<`0x${string}`>, done: string) => finish(await flow.run([{ label, run }]), done)
  const acct = (functionName: string, args?: readonly unknown[]) => () =>
    flow.write({ address: account as Address, abi: pilotAccountAbi, functionName, args })

  const withApprove = async (label: string, amount: bigint, functionName: 'deposit' | 'fundReserve', done: string) => {
    const ok = await flow.run([
      { label: 'Allow USDC', run: () => flow.write({ address: USDC, abi: erc20Abi, functionName: 'approve', args: [account, amount] }) },
      { label, run: acct(functionName, [amount]) },
    ])
    if (await finish(ok, done)) setSheet(null)
  }

  const onWithdraw = async (amount: bigint) => {
    if (!snap) return
    const total = snap.equity + snap.reserve
    const fn = amount >= total ? acct('withdrawAll') : acct('withdraw', [amount])
    if (await single('Withdraw to your wallet', fn, 'Withdrawn to your wallet')) setSheet(null)
  }

  const hasPosition = !!snap && (snap.equity + snap.reserve > 0n || snap.debt > 0n)
  const lastRescue = activity.data?.find((a) => a.kind === 'Protected')

  if (!pilot.isConnected) return null
  if (pilot.accountLoading || (account && !snap)) {
    return <div className="mx-auto max-w-5xl px-4 py-16 text-center" style={{ color: 'var(--muted)' }}>Loading your account from the chain...</div>
  }
  if (!account || !snap || !hasPosition) {
    return (
      <Onboarding
        existing={account}
        market={market}
        flow={flow}
        walletUsdc={pilot.walletUsdc}
        onFunded={() => void pilot.refresh()}
        onStart={(plan) => {
          void startPlan(plan, account).then((ok) => finish(ok, 'Your money is at work'))
        }}
      />
    )
  }

  return (
    <div className="mx-auto grid max-w-5xl gap-4 px-4 pb-24 pt-6 lg:grid-cols-[1.1fr_1fr]">
      {locked && market && <div className="lg:col-span-2"><LockedBanner market={market} /></div>}
      <div className="space-y-4">
        <BalanceCard snapshot={snap} onInvest={() => { flow.reset(); setSheet('invest') }} onWithdraw={() => { flow.reset(); setSheet('withdraw') }} />
        <SecurityCard snapshot={snap} busy={busy} onProtect={() => void single('Run protection', acct('protect'), 'Protection ran')} />
        <ProfitToggle mode={Number(snap.profitMode)} busy={busy} onChange={(m) => void single('Change profit handling', acct('setProfitMode', [m]), m === 0 ? 'Saving profits' : 'Auto-compounding')} />
        {flow.status.labels.length > 0 && !sheet && <div className="ip-card p-4"><p className="ip-label">Latest action</p>{flow.status.error ? <p className="mt-2 text-sm" style={{ color: 'var(--red)' }}>{flow.status.error}</p> : <p className="mt-2 text-sm" style={{ color: 'var(--muted)' }}>{flow.status.running ? 'Waiting for confirmation...' : 'Done.'}</p>}</div>}
        <ActivityList items={activity.data ?? []} loading={activity.isLoading} />
      </div>
      <div className="space-y-4">
        {lastRescue && <ReceiptCard link={invite} receipt={{ tier: lastRescue.tier ?? 0, amount: lastRescue.amount ?? 0n, hfBefore: lastRescue.hfBefore, hfAfter: lastRescue.hfAfter, ts: lastRescue.ts }} />}
        <ProtectionCard
          snapshot={snap}
          busy={busy}
          locked={locked || !marketKnown}
          onBoost={(on) => void (on ? single('Turn on Boost', acct('boostTo', [20000n]), 'Boost is on') : single('Turn Boost off', acct('deleverageTo', [10000n]), 'Boost is off'))}
          onFundReserve={() => { flow.reset(); setSheet('reserve') }}
        />
        <InviteCard link={invite} />
        {LAB_ENABLED && <DemoControls
          frozen={market === 'Frozen'}
          busy={busy}
          onFreeze={(v) => void single(v ? 'Freeze the test market' : 'Unfreeze the test market', () => flow.write({ address: POOL, abi: demoPoolAbi, functionName: 'demoSetFrozen', args: [v] }), v ? 'Test market frozen' : 'Test market open')}
          onSpike={() => void single('Spike borrowing cost', () => flow.write({ address: POOL, abi: demoPoolAbi, functionName: 'demoAccrue', args: [0n, 1500n] }), 'Borrowing cost spiked 15%')}
        />}
      </div>
      <AmountSheet
        open={sheet === 'invest'}
        title="Invest more"
        cta="Invest"
        max={pilot.walletUsdc ?? 0n}
        maxLabel="In your wallet"
        note={
          !marketKnown
            ? 'Checking market status... deposits are only allowed when the market is active.'
            : locked
              ? 'Safe but locked: deposits are paused until the market reopens.'
              : undefined
        }
        status={flow.status}
        onClose={() => setSheet(null)}
        onConfirm={(a) =>
          void (!marketKnown
            ? toast.error('Checking market status. Please try again in a moment.')
            : locked
              ? toast.error('Safe but locked: the market is not accepting deposits right now.')
              : withApprove('Put your money to work', a, 'deposit', 'Added to your position'))
        }
      />
      <AmountSheet open={sheet === 'reserve'} title="Add to protection reserve" cta="Add to reserve" max={pilot.walletUsdc ?? 0n} maxLabel="In your wallet" note="Your reserve stays yours and can be withdrawn any time." status={flow.status} onClose={() => setSheet(null)} onConfirm={(a) => void withApprove('Move to reserve', a, 'fundReserve', 'Reserve topped up')} />
      <AmountSheet open={sheet === 'withdraw'} title="Withdraw" cta="Withdraw" max={snap.equity + snap.reserve} maxLabel="Available" note={snap.debt > 0n ? 'If Boost is on, it is reduced automatically so your position stays safe.' : undefined} status={flow.status} onClose={() => setSheet(null)} onConfirm={(a) => void onWithdraw(a)} />
    </div>
  )
}
