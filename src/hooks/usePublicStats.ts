import { useQuery } from '@tanstack/react-query'
import { getAbiItem, type Address } from 'viem'
import { usePublicClient } from 'wagmi'
import { pilotAccountAbi, pilotFactoryAbi } from '@/abi/pilot'
import { CHAIN_ID, CONFIG_READY, DEPLOY_BLOCK, FACTORY } from '@/lib/pilot'
import { incremental } from '@/lib/logs'

export interface PublicStats {
  accounts: number
  supplied: bigint
  volume: bigint
  protections: number
  receipts: { account: Address; tier: number; amount: bigint; block: bigint; tx: string; ts?: number }[]
  headBlock: bigint
}

const created = getAbiItem({ abi: pilotFactoryAbi, name: 'AccountCreated' })
const protectedEv = getAbiItem({ abi: pilotAccountAbi, name: 'Protected' })
const deposited = getAbiItem({ abi: pilotAccountAbi, name: 'Deposited' })

/** Everything here is read straight from chain events and contract state. Nothing is stored or estimated. */
export function usePublicStats() {
  const client = usePublicClient({ chainId: CHAIN_ID })
  return useQuery({
    queryKey: ['public-stats', FACTORY, String(DEPLOY_BLOCK)],
    enabled: !!client && CONFIG_READY,
    refetchInterval: 20000,
    queryFn: async (): Promise<PublicStats> => {
      if (!client) throw new Error('no client')
      const headBlock = await client.getBlockNumber()
      const makers = await incremental(`stats:created:${FACTORY}:${DEPLOY_BLOCK}`, DEPLOY_BLOCK, headBlock, (fromBlock, toBlock) =>
        client.getLogs({ address: FACTORY, event: created, fromBlock, toBlock }),
      )
      const accounts = makers.map((l) => l.args.account as Address)
      if (accounts.length === 0) return { accounts: 0, supplied: 0n, volume: 0n, protections: 0, receipts: [], headBlock }
      const snaps = await client.multicall({
        allowFailure: true,
        contracts: accounts.map((a) => ({ address: a, abi: pilotAccountAbi, functionName: 'snapshot' as const })),
      })
      let supplied = 0n
      for (const s of snaps) if (s.status === 'success') supplied += (s.result as { collateral: bigint }).collateral
      const evs = await incremental(`stats:events:${FACTORY}:${DEPLOY_BLOCK}`, DEPLOY_BLOCK, headBlock, (fromBlock, toBlock) =>
        client.getLogs({ address: accounts, events: [protectedEv, deposited], fromBlock, toBlock }),
      )
      let volume = 0n
      const receipts: PublicStats['receipts'] = []
      for (const l of evs) {
        if (l.eventName === 'Deposited') volume += (l.args as { amount: bigint }).amount
        else if (l.eventName === 'Protected') {
          const a = l.args as { tier: number; amount: bigint }
          receipts.push({ account: l.address, tier: Number(a.tier), amount: a.amount, block: l.blockNumber, tx: l.transactionHash })
        }
      }
      receipts.reverse()
      const top = receipts.slice(0, 6)
      await Promise.all(
        top.map(async (r) => {
          r.ts = Number((await client.getBlock({ blockNumber: r.block })).timestamp)
        }),
      )
      return { accounts: accounts.length, supplied, volume, protections: receipts.length, receipts: top, headBlock }
    },
  })
}
