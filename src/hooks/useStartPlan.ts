import { useCallback } from 'react'
import { useAccount, usePublicClient } from 'wagmi'
import { erc20Abi, zeroAddress, type Address } from 'viem'
import { pilotAccountAbi, pilotFactoryAbi } from '@/abi/pilot'
import { CHAIN_ID, FACTORY } from '@/lib/pilot'
import { USDC } from '@/hooks/usePilot'
import type { Plan } from '@/lib/planner'
import type { Step } from '@/hooks/useTxFlow'
import type { Hash } from 'viem'

type Write = (p: { address: Address; abi: readonly unknown[]; functionName: string; args?: readonly unknown[] }) => Promise<Hash>

/** Turns a plan into real, ordered wallet transactions. Nothing is skipped or simulated. */
export function useStartPlan(write: Write, run: (steps: Step[]) => Promise<boolean>, referrer?: Address) {
  const { address } = useAccount()
  const client = usePublicClient({ chainId: CHAIN_ID })

  return useCallback(
    async (plan: Plan, existing?: Address): Promise<boolean> => {
      const amount = plan.amount
      if (!address || !client || !amount) return false
      const ctx: { account: Address | undefined } = { account: existing }
      const working = amount - plan.reserve
      const steps: Step[] = []
      if (!ctx.account) {
        steps.push({
          label: 'Create your account',
          run: () => write({ address: FACTORY, abi: pilotFactoryAbi, functionName: 'createAccount', args: [referrer ?? zeroAddress] }),
        })
      }
      steps.push({
        label: 'Allow USDC',
        run: async () => {
          if (!ctx.account) {
            ctx.account = (await client.readContract({ address: FACTORY, abi: pilotFactoryAbi, functionName: 'accountOf', args: [address] }))
          }
          return write({ address: USDC, abi: erc20Abi, functionName: 'approve', args: [ctx.account, amount] })
        },
      })
      steps.push({ label: 'Put your money to work', run: () => write({ address: ctx.account as Address, abi: pilotAccountAbi, functionName: 'deposit', args: [working] }) })
      if (plan.reserve > 0n) {
        steps.push({ label: 'Set aside protection reserve', run: () => write({ address: ctx.account as Address, abi: pilotAccountAbi, functionName: 'fundReserve', args: [plan.reserve] }) })
      }
      if (plan.mode === 1) {
        steps.push({ label: 'Turn on Auto-Compound', run: () => write({ address: ctx.account as Address, abi: pilotAccountAbi, functionName: 'setProfitMode', args: [1] }) })
      }
      if (plan.boost) {
        steps.push({ label: 'Turn on Boost', run: () => write({ address: ctx.account as Address, abi: pilotAccountAbi, functionName: 'boostTo', args: [20000n] }) })
      }
      return run(steps)
    },
    [address, client, write, run, referrer],
  )
}
