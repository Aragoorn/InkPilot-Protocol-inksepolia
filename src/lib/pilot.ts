import { isAddress, zeroAddress, type Address } from 'viem'
import { inkSepolia } from 'viem/chains'

/** InkPilot targets Ink Sepolia (testnet) only. Chain data comes from viem's chain definition. */
export const CHAIN = inkSepolia
export const CHAIN_ID = inkSepolia.id
/** Public RPC only: every VITE_ value is shipped to the browser, so never put a keyed RPC URL here. */
const rpcOverride: unknown = import.meta.env.VITE_INK_SEPOLIA_RPC_URL
export const RPC_URL: string = typeof rpcOverride === 'string' && rpcOverride.startsWith('https://') ? rpcOverride : inkSepolia.rpcUrls.default.http[0]

const addr = (v: unknown): Address => (typeof v === 'string' && isAddress(v) ? v : zeroAddress)

export const FACTORY = addr(import.meta.env.VITE_PILOT_FACTORY)
export const POOL = addr(import.meta.env.VITE_PILOT_POOL)
export const ASSET = addr(import.meta.env.VITE_PILOT_ASSET)
export const TIMELOCK = addr(import.meta.env.VITE_PILOT_TIMELOCK)
export const ACCOUNT_IMPL = addr(import.meta.env.VITE_PILOT_ACCOUNT_IMPL)
export const FACTORY_IMPL = addr(import.meta.env.VITE_PILOT_FACTORY_IMPL)
export const DEPLOY_BLOCK = BigInt(String(import.meta.env.VITE_PILOT_DEPLOY_BLOCK ?? '0').replace(/\D/g, '') || '0')

/** True once ./deploy.sh has written the contract addresses into .env. */
export const CONFIG_READY = [FACTORY, POOL, ASSET, TIMELOCK, ACCOUNT_IMPL, FACTORY_IMPL].every((a) => a !== zeroAddress)
/** The in-app "Get test USDC" button exists only when deploy.sh deployed the public-faucet TestUSDC. */
export const FAUCET_ENABLED = import.meta.env.VITE_PILOT_FAUCET === 'true'
/** The "Testnet lab" switches exist only when the pool is the open demo pool, never for a real market. */
export const LAB_ENABLED = import.meta.env.VITE_PILOT_DEMO_POOL === 'true'

export const MARKET_STATUS = ['Active', 'Frozen', 'Paused', 'LtvZero', 'Inactive'] as const
export type MarketStatusName = (typeof MARKET_STATUS)[number]
export const NO_DEBT_HF = 60000

export interface Snapshot {
  collateral: bigint
  debt: bigint
  reserve: bigint
  equity: bigint
  invested: bigint
  netDeposits: bigint
  lifetimeProfit: bigint
  hfBps: bigint
  leverageBps: bigint
  status: number
  profitMode: number
  maxTip: bigint
  lastProtectAt: bigint
  liquidationsAllowed: boolean
}

export type Light = 'green' | 'yellow' | 'red'

/** Plain-language security status derived from the real onchain snapshot. */
export function securityOf(s: Snapshot): { light: Light; title: string; body: string } {
  const status = MARKET_STATUS[s.status] ?? 'Active'
  if (status === 'Paused') {
    return { light: 'yellow', title: 'Safe but locked', body: 'The lending market is paused. Nothing can move right now, and your position is untouched. We will tell you when it reopens.' }
  }
  if (status === 'Frozen') {
    return { light: 'yellow', title: 'Safe but locked', body: 'The market is frozen for new deposits. You can still withdraw and repay, and protection keeps working.' }
  }
  if (s.debt === 0n) {
    return { light: 'green', title: 'No liquidation risk', body: 'You are in Earn mode with no borrowing, so there is nothing to liquidate.' }
  }
  const hf = Number(s.hfBps) / 10000
  if (hf < 1.2) return { light: 'red', title: 'Protection needed', body: 'Your position is close to its limit. Safe Mode acts on it automatically, or you can run protection now.' }
  if (hf < 1.4) return { light: 'yellow', title: 'Watching closely', body: 'Safe Mode is active and ready to step in if your buffer shrinks.' }
  return { light: 'green', title: 'Protected', body: 'Safe Mode is active. Your position has a comfortable buffer.' }
}
