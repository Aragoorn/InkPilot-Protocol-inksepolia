import { useCallback, useState } from 'react'
import { useAccount, usePublicClient, useSwitchChain, useWriteContract } from 'wagmi'
import type { Abi, Address, Hash } from 'viem'
import { CHAIN_ID } from '@/lib/pilot'
import { plainError } from '@/lib/errors'

export interface Step {
  label: string
  run: () => Promise<Hash>
}
export type StepState = 'waiting' | 'wallet' | 'confirming' | 'done' | 'failed'
export interface FlowStatus {
  labels: string[]
  states: StepState[]
  error: string | null
  running: boolean
  hashes: Hash[]
}

const IDLE: FlowStatus = { labels: [], states: [], error: null, running: false, hashes: [] }

/** Runs real wallet transactions in order and reports the real state of each one. */
export function useTxFlow() {
  const { chainId } = useAccount()
  const { switchChainAsync } = useSwitchChain()
  const { writeContractAsync } = useWriteContract()
  const client = usePublicClient({ chainId: CHAIN_ID })
  const [status, setStatus] = useState<FlowStatus>(IDLE)

  const write = useCallback(
    async (p: { address: Address; abi: Abi | readonly unknown[]; functionName: string; args?: readonly unknown[] }) => {
      if (chainId !== CHAIN_ID) await switchChainAsync({ chainId: CHAIN_ID })
      return writeContractAsync({ ...p, abi: p.abi as Abi, chainId: CHAIN_ID })
    },
    [chainId, switchChainAsync, writeContractAsync],
  )

  const run = useCallback(
    async (steps: Step[]): Promise<boolean> => {
      const states: StepState[] = steps.map(() => 'waiting')
      const hashes: Hash[] = []
      const push = (error: string | null, running: boolean) =>
        setStatus({ labels: steps.map((s) => s.label), states: [...states], error, running, hashes: [...hashes] })
      push(null, true)
      if (!client) {
        push('Wallet client is not ready yet. Reconnect and try again.', false)
        return false
      }
      for (let i = 0; i < steps.length; i++) {
        try {
          states[i] = 'wallet'
          push(null, true)
          const hash = await steps[i].run()
          states[i] = 'confirming'
          push(null, true)
          const receipt = await client.waitForTransactionReceipt({ hash })
          if (receipt.status !== 'success') throw new Error('reverted')
          hashes.push(hash)
          states[i] = 'done'
          push(null, true)
        } catch (e) {
          states[i] = 'failed'
          push(plainError(e), false)
          return false
        }
      }
      push(null, false)
      return true
    },
    [client],
  )

  const reset = useCallback(() => setStatus(IDLE), [])
  return { status, run, write, reset }
}
