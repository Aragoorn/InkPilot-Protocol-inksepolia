import { useQuery } from '@tanstack/react-query'
import { getAbiItem, type Address, type Hash } from 'viem'
import { usePublicClient } from 'wagmi'
import { pilotAccountAbi } from '@/abi/pilot'
import { CHAIN_ID, CONFIG_READY, DEPLOY_BLOCK } from '@/lib/pilot'
import { incremental } from '@/lib/logs'
import { usd } from '@/lib/format'

const NAMES = ['Deposited', 'ReserveFunded', 'Withdrawn', 'Protected', 'ProtectionSkipped', 'ProfitHarvested', 'ProfitModeChanged', 'Boosted', 'Deleveraged', 'ExitedToEarn'] as const
export const accountEvents = NAMES.map((name) => getAbiItem({ abi: pilotAccountAbi, name }))

export interface Activity {
  id: string
  block: bigint
  ts?: number
  kind: string
  tier?: number
  amount?: bigint
  hfBefore?: bigint
  hfAfter?: bigint
  text: string
  tx: string
}

type Args = Record<string, unknown>
interface AccLog {
  blockNumber: bigint
  eventName: string
  args: Args
  transactionHash: Hash
  logIndex: number
}
const num = (v: unknown): bigint => (typeof v === 'bigint' ? v : 0n)

export function describe(name: string, a: Args): { text: string; tier?: number; amount?: bigint } {
  switch (name) {
    case 'Deposited':
      return { text: `You added ${usd(num(a.amount))} to grow.`, amount: num(a.amount) }
    case 'ReserveFunded':
      return { text: `You set aside ${usd(num(a.amount))} as your protection reserve.`, amount: num(a.amount) }
    case 'Withdrawn':
      return { text: `You withdrew ${usd(num(a.amount))}.`, amount: num(a.amount) }
    case 'Protected': {
      const tier = Number(a.tier)
      const amt = usd(num(a.amount))
      const text =
        tier === 1
          ? `Your position was protected. ${amt} from your reserve was added as a safety buffer.`
          : tier === 2
            ? `Your position was protected. ${amt} from your reserve paid down borrowing.`
            : tier === 3
              ? 'Your position was moved back to safe Earn mode to keep it protected.'
              : `Your position was protected. ${amt} of your own earnings paid down borrowing.`
      return { text, tier, amount: num(a.amount) }
    }
    case 'ProtectionSkipped':
      return { text: 'Safe Mode checked your position and decided no action was needed yet.' }
    case 'ProfitHarvested':
      return { text: `${usd(num(a.amount))} of profit was moved to your savings.`, amount: num(a.amount) }
    case 'ProfitModeChanged':
      return { text: Number(a.mode) === 0 ? 'Profit handling set to Save Profits.' : 'Profit handling set to Auto-Compound.' }
    case 'Boosted':
      return { text: `Boost turned on at ${(Number(a.leverageBps) / 10000).toFixed(2)}x.` }
    case 'Deleveraged':
      return { text: `Boost reduced to ${(Number(a.leverageBps) / 10000).toFixed(2)}x.` }
    case 'ExitedToEarn':
      return { text: 'Your position was moved back to safe Earn mode.' }
    default:
      return { text: name }
  }
}

export function useActivity(account?: Address) {
  const client = usePublicClient({ chainId: CHAIN_ID })
  return useQuery({
    queryKey: ['activity', account, String(DEPLOY_BLOCK)],
    enabled: !!account && !!client && CONFIG_READY,
    refetchInterval: 12000,
    queryFn: async (): Promise<Activity[]> => {
      if (!client || !account) return []
      const head = await client.getBlockNumber()
      const logs = await incremental<AccLog>(
        `activity:${account}:${DEPLOY_BLOCK}`,
        DEPLOY_BLOCK,
        head,
        async (fromBlock, toBlock) => await client.getLogs({ address: account, events: accountEvents, fromBlock, toBlock }),
      )
      const blocks = [...new Set(logs.map((l) => l.blockNumber))].slice(-30)
      const stamps = new Map<bigint, number>()
      await Promise.all(
        blocks.map(async (b) => {
          const blk = await client.getBlock({ blockNumber: b })
          stamps.set(b, Number(blk.timestamp))
        }),
      )
      return logs
        .map((l) => {
          const d = describe(String(l.eventName), l.args)
          const a = l.args
          return {
            id: `${l.transactionHash}-${l.logIndex}`,
            block: l.blockNumber,
            ts: stamps.get(l.blockNumber),
            kind: String(l.eventName),
            tier: d.tier,
            amount: d.amount,
            hfBefore: typeof a.hfBefore === 'bigint' ? a.hfBefore : undefined,
            hfAfter: typeof a.hfAfter === 'bigint' ? a.hfAfter : undefined,
            text: d.text,
            tx: l.transactionHash,
          }
        })
        .reverse()
    },
  })
}
