import { toast } from 'sonner'
import { Droplets } from 'lucide-react'
import { testUsdcAbi } from '@/abi/pilot'
import { ASSET, FAUCET_ENABLED } from '@/lib/pilot'
import { useTxFlow } from '@/hooks/useTxFlow'

const ETH_FAUCETS = 'https://docs.inkonchain.com/tools/faucets'

/** Claims free test USDC from the TestUSDC contract that deploy.sh deployed. Hidden when that contract does not exist. */
export function FaucetButton({ onDone }: { onDone: () => void }) {
  const flow = useTxFlow()
  if (!FAUCET_ENABLED) {
    return (
      <p className="text-sm" style={{ color: 'var(--muted)' }}>
        You need the test stablecoin this deployment uses, plus a little Ink Sepolia ETH for fees. <a className="underline" href={ETH_FAUCETS} target="_blank" rel="noopener noreferrer">Get test ETH</a>.
      </p>
    )
  }
  return (
    <div>
      <button
        className="ip-btn ip-ghost flex items-center gap-2"
        disabled={flow.status.running}
        onClick={() =>
          void flow
            .run([{ label: 'Claim test USDC', run: () => flow.write({ address: ASSET, abi: testUsdcAbi, functionName: 'faucet' }) }])
            .then((ok) => {
              if (ok) {
                toast.success('1,000 test USDC added to your wallet')
                onDone()
              }
            })
        }
      >
        <Droplets size={16} /> {flow.status.running ? 'Claiming...' : 'Get test USDC'}
      </button>
      {flow.status.error && <p className="mt-2 text-sm" style={{ color: 'var(--red)' }}>{flow.status.error}</p>}
      <p className="mt-2 text-xs" style={{ color: 'var(--muted)' }}>
        Fees are paid in test ETH. <a className="underline" href={ETH_FAUCETS} target="_blank" rel="noopener noreferrer">Get test ETH</a>.
      </p>
    </div>
  )
}
