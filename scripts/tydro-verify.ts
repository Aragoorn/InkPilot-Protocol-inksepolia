/**
 * Reads a Tydro (Aave V3) market on Ink Sepolia and checks it against what InkPilot v1 needs.
 * It takes every address from you. Nothing is hardcoded, so you must copy the addresses from Tydro's own
 * documentation (https://docs.tydro.com, "Contract Addresses") or from the Tydro app in testnet mode.
 *
 *   bun run tydro:verify -- --pool 0x... --asset 0x...
 *   bun run tydro:verify -- --provider 0x... --asset 0x...      (PoolAddressesProvider)
 *   options: --rpc <url>  --json
 *
 * Env: INK_SEPOLIA_RPC_URL (default: Ink's public Sepolia RPC), EXPECT_CHAIN_ID (default 763373).
 */
import { createPublicClient, decodeErrorResult, http, isAddress, parseAbi, zeroAddress, type Address } from 'viem'
import { inkSepolia } from 'viem/chains'

const arg = (name: string): string | undefined => {
  const i = process.argv.indexOf(`--${name}`)
  return i > -1 ? process.argv[i + 1] : undefined
}
const asJson = process.argv.includes('--json')
const rpc = arg('rpc') ?? process.env.INK_SEPOLIA_RPC_URL ?? inkSepolia.rpcUrls.default.http[0]
const expectChain = Number(process.env.EXPECT_CHAIN_ID ?? inkSepolia.id)
const asset = arg('asset') as Address | undefined
let pool = arg('pool') as Address | undefined
let provider = arg('provider') as Address | undefined

if (!asset || !isAddress(asset) || (!pool && !provider) || (pool && !isAddress(pool)) || (provider && !isAddress(provider))) {
  console.error('Usage: bun run tydro:verify -- (--pool 0x... | --provider 0x...) --asset 0x... [--rpc URL] [--json]')
  process.exit(2)
}

const client = createPublicClient({ transport: http(rpc) })
type Level = 'PASS' | 'WARN' | 'FAIL'
const rows: { level: Level; check: string; detail: string }[] = []
const add = (level: Level, check: string, detail: string) => rows.push({ level, check, detail })
const tryRead = async <T>(fn: () => Promise<T>): Promise<T | undefined> => {
  try {
    return await fn()
  } catch {
    return undefined
  }
}

const poolAbi = parseAbi([
  'function ADDRESSES_PROVIDER() view returns (address)',
  'function getReserveData(address) view returns ((uint256 configuration,uint128 liquidityIndex,uint128 currentLiquidityRate,uint128 variableBorrowIndex,uint128 currentVariableBorrowRate,uint128 currentStableBorrowRate,uint40 lastUpdateTimestamp,uint16 id,address aTokenAddress,address stableDebtTokenAddress,address variableDebtTokenAddress,address interestRateStrategyAddress,uint128 accruedToTreasury,uint128 unbacked,uint128 isolationModeTotalDebt))',
  'function repayWithATokens(address,uint256,uint256) returns (uint256)',
])
const providerAbi = parseAbi([
  'function getPool() view returns (address)',
  'function getPoolDataProvider() view returns (address)',
  'function getPriceOracleSentinel() view returns (address)',
])
const dataAbi = parseAbi([
  'function getReserveConfigurationData(address) view returns (uint256 decimals,uint256 ltv,uint256 liquidationThreshold,uint256 liquidationBonus,uint256 reserveFactor,bool usageAsCollateralEnabled,bool borrowingEnabled,bool stableBorrowRateEnabled,bool isActive,bool isFrozen)',
  'function getPaused(address) view returns (bool)',
  'function getReserveCaps(address) view returns (uint256 borrowCap,uint256 supplyCap)',
  'function getReserveData(address) view returns (uint256 unbacked,uint256 accruedToTreasuryScaled,uint256 totalAToken,uint256 totalStableDebt,uint256 totalVariableDebt,uint256 liquidityRate,uint256 variableBorrowRate,uint256 stableBorrowRate,uint256 averageStableBorrowRate,uint256 liquidityIndex,uint256 variableBorrowIndex,uint40 lastUpdateTimestamp)',
])
const sentinelAbi = parseAbi([
  'function isBorrowAllowed() view returns (bool)',
  'function isLiquidationAllowed() view returns (bool)',
  'function getGracePeriod() view returns (uint256)',
])
const erc20Abi = parseAbi(['function decimals() view returns (uint8)', 'function symbol() view returns (string)'])

const bit = (v: bigint, n: bigint) => ((v >> n) & 1n) === 1n

async function main() {
  const chainId = await client.getChainId()
  if (chainId !== expectChain) {
    console.error(`RPC reports chain ${chainId}, expected ${expectChain}. Stopping.`)
    process.exit(2)
  }
  add('PASS', 'Chain', `${chainId}`)

  if (!pool && provider) {
    pool = await tryRead(() => client.readContract({ address: provider as Address, abi: providerAbi, functionName: 'getPool' }))
    if (!pool || pool === zeroAddress) {
      add('FAIL', 'Pool from provider', 'provider.getPool() failed. Check the PoolAddressesProvider address.')
      return
    }
  }
  const poolAddr = pool as Address
  if (((await client.getCode({ address: poolAddr })) ?? '0x') === '0x') {
    add('FAIL', 'Pool has code', `${poolAddr} has no contract code on this chain`)
    return
  }
  add('PASS', 'Pool has code', poolAddr)

  const dec = await tryRead(() => client.readContract({ address: asset as Address, abi: erc20Abi, functionName: 'decimals' }))
  const sym = await tryRead(() => client.readContract({ address: asset as Address, abi: erc20Abi, functionName: 'symbol' }))
  if (dec === undefined) add('FAIL', 'Asset is an ERC-20', `${asset} did not answer decimals()`)
  else add(dec === 6 ? 'PASS' : 'FAIL', 'Asset has 6 decimals', `${sym ?? '?'} reports ${dec} (InkPilot v1 requires 6)`)

  const reserve = await tryRead(() => client.readContract({ address: poolAddr, abi: poolAbi, functionName: 'getReserveData', args: [asset as Address] }))
  if (!reserve || reserve.aTokenAddress === zeroAddress) {
    add('FAIL', 'Asset is a reserve', 'getReserveData failed or the asset has no aToken. This asset is not listed in this pool.')
    return
  }
  const c = reserve.configuration
  const flags = {
    ltv: Number(c & 0xffffn),
    liquidationThreshold: Number((c >> 16n) & 0xffffn),
    liquidationBonus: Number((c >> 32n) & 0xffffn),
    active: bit(c, 56n),
    frozen: bit(c, 57n),
    borrowing: bit(c, 58n),
    paused: bit(c, 60n),
  }
  add(flags.active ? 'PASS' : 'FAIL', 'Reserve active', String(flags.active))
  add(!flags.paused ? 'PASS' : 'FAIL', 'Reserve not paused', String(flags.paused))
  add(!flags.frozen ? 'PASS' : 'WARN', 'Reserve not frozen', flags.frozen ? 'Frozen: new deposits are blocked, Safe but locked' : 'false')
  add(flags.ltv > 0 ? 'PASS' : 'WARN', 'LTV above zero', `${flags.ltv / 100}% (0 means no borrowing against it, Earn only)`)
  add(flags.borrowing ? 'PASS' : 'WARN', 'Borrowing enabled', flags.borrowing ? 'true' : 'false: Boost cannot be used, Earn mode only')
  add(flags.liquidationThreshold >= flags.ltv && flags.liquidationThreshold > 0 ? 'PASS' : 'FAIL', 'Liquidation threshold sane', `LT ${flags.liquidationThreshold / 100}% vs LTV ${flags.ltv / 100}%`)
  add(flags.liquidationBonus > 10000 ? 'PASS' : 'WARN', 'Liquidation bonus above 100%', `${flags.liquidationBonus} bps scale (10500 = 5% penalty)`)

  // Cross-check our bit decoding against the pool's own data provider (catches a changed config layout).
  const prov = await tryRead(() => client.readContract({ address: poolAddr, abi: poolAbi, functionName: 'ADDRESSES_PROVIDER' }))
  provider = provider ?? prov
  const dp = provider ? await tryRead(() => client.readContract({ address: provider as Address, abi: providerAbi, functionName: 'getPoolDataProvider' })) : undefined
  if (dp && dp !== zeroAddress) {
    const cfg = await tryRead(() => client.readContract({ address: dp, abi: dataAbi, functionName: 'getReserveConfigurationData', args: [asset as Address] }))
    const paused = await tryRead(() => client.readContract({ address: dp, abi: dataAbi, functionName: 'getPaused', args: [asset as Address] }))
    if (cfg) {
      const same = Number(cfg[1]) === flags.ltv && Number(cfg[2]) === flags.liquidationThreshold && cfg[8] === flags.active && cfg[9] === flags.frozen && cfg[6] === flags.borrowing && (paused === undefined || paused === flags.paused)
      add(same ? 'PASS' : 'FAIL', 'Flag layout matches data provider', same ? 'bit decoding agrees with getReserveConfigurationData' : 'MISMATCH: do not deploy, the configuration layout differs from what InkPilot reads')
    } else add('WARN', 'Flag layout cross-check', 'data provider did not answer')
    const caps = await tryRead(() => client.readContract({ address: dp, abi: dataAbi, functionName: 'getReserveCaps', args: [asset as Address] }))
    if (caps) add('PASS', 'Caps', `borrow cap ${caps[0]}, supply cap ${caps[1]} (whole tokens, 0 = none)`)
    const tot = await tryRead(() => client.readContract({ address: dp, abi: dataAbi, functionName: 'getReserveData', args: [asset as Address] }))
    if (tot && tot[2] > 0n) {
      const util = Number(((tot[3] + tot[4]) * 10000n) / tot[2]) / 100
      add(util < 90 ? 'PASS' : 'WARN', 'Utilization', `${util}%. Above ~90% withdrawals and profit harvests can fail for lack of liquidity (aToken repay still works)`)
    }
  } else add('WARN', 'Data provider', 'no PoolDataProvider found from the addresses provider, skipped cross-checks')

  // Liquidation grace period after a sequencer outage (price oracle sentinel).
  const sentinel = provider ? await tryRead(() => client.readContract({ address: provider as Address, abi: providerAbi, functionName: 'getPriceOracleSentinel' })) : undefined
  if (!sentinel || sentinel === zeroAddress) {
    add('WARN', 'Oracle sentinel (sequencer grace period)', 'none set. After a sequencer outage there is no liquidation grace period. Do not offer Boost on a market like this without accepting that.')
  } else {
    const g = await tryRead(() => client.readContract({ address: sentinel, abi: sentinelAbi, functionName: 'getGracePeriod' }))
    const liq = await tryRead(() => client.readContract({ address: sentinel, abi: sentinelAbi, functionName: 'isLiquidationAllowed' }))
    add('PASS', 'Oracle sentinel', `${sentinel}, grace period ${g === undefined ? 'unreadable' : `${g}s`}, liquidations allowed now: ${liq}`)
  }

  // repayWithATokens must exist: a missing selector reverts with empty data, a real function reverts with a reason.
  const probe = await tryRead(async () => {
    try {
      await client.simulateContract({ address: poolAddr, abi: poolAbi, functionName: 'repayWithATokens', args: [asset as Address, 0n, 2n], account: '0x000000000000000000000000000000000000dEaD' })
      return 'ok'
    } catch (e) {
      const data = (e as { data?: `0x${string}`; cause?: { data?: `0x${string}`; raw?: `0x${string}` } }).cause?.raw ?? (e as { data?: `0x${string}` }).data
      if (!data || data === '0x') return 'missing'
      try {
        decodeErrorResult({ abi: [{ type: 'error', name: 'Error', inputs: [{ name: 'm', type: 'string' }] }], data })
      } catch {
        /* custom error also proves the function exists */
      }
      return 'exists'
    }
  })
  add(probe === 'missing' ? 'FAIL' : 'PASS', 'repayWithATokens available', probe === 'missing' ? 'selector not found: Tier 3 exit would not work' : 'function responds (reverts only on the zero amount we sent)')
}

await main()
const fails = rows.filter((r) => r.level === 'FAIL').length
if (asJson) console.log(JSON.stringify({ rpc, pool, provider, asset, rows, compatible: fails === 0 }, null, 2))
else {
  console.log(`\nInkPilot v1 compatibility report\n  pool ${pool ?? '?'}\n  asset ${asset}\n`)
  for (const r of rows) console.log(`  ${r.level.padEnd(4)}  ${r.check.padEnd(40)} ${r.detail}`)
  console.log(`\n${fails === 0 ? 'No blocking problems found.' : `${fails} blocking problem(s). Do not deploy against this market.`}`)
  console.log('Warnings are not blockers, but read each one. Always compare the addresses above with docs.tydro.com or the Tydro app.\n')
}
process.exit(fails === 0 ? 0 : 1)
