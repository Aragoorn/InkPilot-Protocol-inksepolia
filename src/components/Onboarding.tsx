import { Lock } from 'lucide-react'
import { toast } from 'sonner'
import { FaucetButton } from '@/components/FaucetButton'
import { ChatPlanner } from '@/components/ChatPlanner'
import { TxProgress } from '@/components/TxProgress'
import { usd } from '@/lib/format'
import type { useTxFlow } from '@/hooks/useTxFlow'
import type { Plan } from '@/lib/planner'
import type { MarketStatusName } from '@/lib/pilot'
import type { Address } from 'viem'

interface Props {
  existing?: Address
  market?: MarketStatusName
  flow: ReturnType<typeof useTxFlow>
  walletUsdc?: bigint
  onStart: (plan: Plan) => void
  onFunded: () => void
}

/** First screen after connecting: say what you want, approve the steps, done. */
export function Onboarding({ market, flow, walletUsdc, onStart, onFunded }: Props) {
  const locked = market !== undefined && market !== 'Active'
  return (
    <div className="mx-auto max-w-xl px-4 pb-24 pt-8">
      <h1 className="text-3xl font-extrabold ip-display">What would you like to do with your money?</h1>
      <p className="mt-2 text-[15px]" style={{ color: 'var(--muted)' }}>Wallet balance: <span className="tabular">{walletUsdc === undefined ? '...' : usd(walletUsdc)}</span> USDC.</p>
      <div className="mt-3"><FaucetButton onDone={onFunded} /></div>
      {locked && (
        <p className="ip-card mt-4 flex gap-2 p-3 text-sm" style={{ borderColor: 'rgba(255,200,87,.4)' }}>
          <Lock size={16} color="var(--amber)" className="mt-0.5 shrink-0" /> Safe but locked: the lending market is not accepting new deposits right now. Nothing was sent.
        </p>
      )}
      <div className="mt-5">
        <ChatPlanner
          ctaLabel="Start this plan"
          busy={flow.status.running}
          disabledReason={
            locked
              ? 'Waiting for the market to reopen.'
              : market === undefined
                ? 'Checking market status...'
                : walletUsdc !== undefined && walletUsdc === 0n
                  ? 'Your wallet has no USDC yet.'
                  : undefined
          }
          onStart={(p) => {
            if (p.amount && walletUsdc !== undefined && p.amount > walletUsdc) {
              flow.reset()
              toast.error(`You asked for ${usd(p.amount)} but your wallet holds ${usd(walletUsdc)}.`)
              return
            }
            onStart(p)
          }}
        />
        <TxProgress status={flow.status} />
      </div>
    </div>
  )
}
