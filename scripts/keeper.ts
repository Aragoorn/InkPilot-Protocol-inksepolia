/**
 * InkPilot keeper: an optional off-chain helper that calls the permissionless protect() on accounts
 * that need it, and sends Telegram alerts. It never holds user funds. The only key it needs pays gas.
 * protect() is public, so anyone (including users themselves) can do the same without this script.
 *
 * Run:  KEEPER_PRIVATE_KEY=0x... bun run keeper
 * Optional: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID for alerts, KEEPER_INTERVAL_SECONDS (default 30).
 */
import { createPublicClient, createWalletClient, getAbiItem, http, type Address, type Hex } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { inkSepolia } from 'viem/chains'
import { pilotAccountAbi, pilotFactoryAbi } from '../src/abi/pilot'

const NO_DEBT_HF = 60000n
/** Ink Sepolia RPC rejects log ranges over ~1,000 blocks; keep scans safely below that. */
const LOG_STEP = 990n
const factory = process.env.VITE_PILOT_FACTORY as Address | undefined
const fromBlock = BigInt((process.env.VITE_PILOT_DEPLOY_BLOCK ?? '0').replace(/\D/g, '') || '0')
const key = process.env.KEEPER_PRIVATE_KEY as Hex | undefined
if (!factory || !key) {
  console.error('Set VITE_PILOT_FACTORY (already in .env) and KEEPER_PRIVATE_KEY (gas only, never a user key).')
  process.exit(1)
}

const rpcUrl = process.env.INK_SEPOLIA_RPC_URL ?? inkSepolia.rpcUrls.default.http[0]

const publicClient = createPublicClient({ chain: inkSepolia, transport: http(rpcUrl) })
const wallet = createWalletClient({ account: privateKeyToAccount(key), chain: inkSepolia, transport: http(rpcUrl) })
const created = getAbiItem({ abi: pilotFactoryAbi, name: 'AccountCreated' })
const accounts = new Set<Address>()
let scanned = fromBlock
const lastStatus = new Map<Address, number>()

async function alert(text: string) {
  const stamped = `[${new Date().toISOString()}] ${text}`
  console.log(stamped)
  const t = process.env.TELEGRAM_BOT_TOKEN
  const c = process.env.TELEGRAM_CHAT_ID
  if (!t || !c) return
  await fetch(`https://api.telegram.org/bot${t}/sendMessage`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ chat_id: c, text: stamped }),
  }).catch((err) => console.warn('telegram alert failed', err))
}

async function discover() {
  const head = await publicClient.getBlockNumber()
  if (scanned > head) return
  for (let from = scanned; from <= head; from += LOG_STEP) {
    const to = from + LOG_STEP - 1n > head ? head : from + LOG_STEP - 1n
    const logs = await publicClient.getLogs({ address: factory, event: created, fromBlock: from, toBlock: to })
    for (const l of logs) {
      if (l.args.account) accounts.add(l.args.account as Address)
    }
  }
  scanned = head + 1n
}

async function check(account: Address) {
  const s = await publicClient.readContract({ address: account, abi: pilotAccountAbi, functionName: 'snapshot' })
  const prev = lastStatus.get(account)
  if (prev !== s.status) {
    lastStatus.set(account, s.status)
    if (s.status === 1 || s.status === 2) {
      await alert(`Safe but locked: the market is ${s.status === 2 ? 'paused' : 'frozen'}. Account ${account} is untouched.`)
    }
  }
  // Paused markets block pool actions including protect(); frozen markets may still allow repay flows depending on pool behavior.
  if (s.debt === 0n || s.hfBps >= NO_DEBT_HF || s.status === 2) return
  const risk = await publicClient.readContract({ address: account, abi: pilotAccountAbi, functionName: 'riskParams' })
  if (s.hfBps >= BigInt(risk.tier1Bps)) return
  try {
    const { request } = await publicClient.simulateContract({ address: account, abi: pilotAccountAbi, functionName: 'protect', account: wallet.account })
    const hash = await wallet.writeContract(request)
    const receipt = await publicClient.waitForTransactionReceipt({ hash })
    if (receipt.status !== 'success') throw new Error('protect reverted')
    await alert(`Protection ran for ${account}. Buffer was ${(Number(s.hfBps) / 10000).toFixed(2)}x. Tx ${hash}`)
  } catch (e) {
    console.log(`protect() skipped for ${account}: ${(e as { shortMessage?: string }).shortMessage ?? (e as Error).message ?? 'reverted'}`)
  }
}

const every = Math.max(5, Number(process.env.KEEPER_INTERVAL_SECONDS ?? '30') || 30) * 1000
console.log(`[${new Date().toISOString()}] Keeper watching factory ${factory} every ${every / 1000}s as ${wallet.account.address}`)
for (;;) {
  try {
    await discover()
    for (const a of accounts) await check(a)
  } catch (e) {
    console.error(`[${new Date().toISOString()}] cycle failed: ${(e as { shortMessage?: string }).shortMessage ?? (e as Error).message ?? 'rpc error'}`)
  }
  await new Promise((r) => setTimeout(r, every))
}
