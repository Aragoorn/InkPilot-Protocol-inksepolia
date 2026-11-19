import { useEffect, useMemo, useState } from 'react'
import { useAccount, useReadContract } from 'wagmi'
import { zeroAddress, type Address } from 'viem'
import { pilotAccountAbi, pilotFactoryAbi, demoPoolAbi } from '@/abi/pilot'
import { ASSET, CHAIN_ID, CONFIG_READY, FACTORY, MARKET_STATUS, POOL, type MarketStatusName } from '@/lib/pilot'
import { buildShareLink } from '@/lib/share'

/** The stablecoin InkPilot runs on: the 6-decimal asset set in .env by deploy.sh. */
export const USDC: Address = ASSET

/** Reads the status flags of the lending market directly from its reserve configuration. */
export function statusFromConfig(config: bigint): MarketStatusName {
  const bit = (n: bigint) => ((config >> n) & 1n) === 1n
  if (bit(60n)) return 'Paused'
  if (!bit(56n)) return 'Inactive'
  if (bit(57n)) return 'Frozen'
  if ((config & 0xffffn) === 0n) return 'LtvZero'
  return MARKET_STATUS[0]
}

export function useMarketStatus() {
  const { data, refetch } = useReadContract({
    address: POOL,
    abi: demoPoolAbi,
    functionName: 'getReserveData',
    args: [USDC],
    chainId: CHAIN_ID,
    query: { enabled: CONFIG_READY, refetchInterval: 8000 },
  })
  const status = data ? statusFromConfig(data.configuration) : undefined
  return { status, refetch }
}

export function usePilot() {
  const { address, isConnected } = useAccount()
  const owner = address ?? zeroAddress
  const accountQ = useReadContract({
    address: FACTORY,
    abi: pilotFactoryAbi,
    functionName: 'accountOf',
    args: [owner],
    chainId: CHAIN_ID,
    query: { enabled: isConnected && CONFIG_READY },
  })
  const account = accountQ.data && accountQ.data !== zeroAddress ? (accountQ.data) : undefined
  const snapQ = useReadContract({
    address: account,
    abi: pilotAccountAbi,
    functionName: 'snapshot',
    chainId: CHAIN_ID,
    query: { enabled: !!account, refetchInterval: 6000 },
  })
  const usdcBal = useReadContract({
    address: USDC,
    abi: [{ type: 'function', name: 'balanceOf', stateMutability: 'view', inputs: [{ name: 'a', type: 'address' }], outputs: [{ type: 'uint256' }] }] as const,
    functionName: 'balanceOf',
    args: [owner],
    chainId: CHAIN_ID,
    query: { enabled: isConnected, refetchInterval: 8000 },
  })
  const refresh = async () => {
    await accountQ.refetch()
    await snapQ.refetch()
    await usdcBal.refetch()
  }
  return {
    address,
    isConnected,
    account,
    accountLoading: accountQ.isLoading,
    snapshot: snapQ.data,
    walletUsdc: usdcBal.data,
    refresh,
  }
}

/** Stores a valid ?ref= address once, so it can be passed to account creation. */
export function useReferral(self?: Address): Address | undefined {
  const [ref] = useState<Address | undefined>(() => {
    const valid = (v: string | null): v is string => !!v && /^0x[0-9a-fA-F]{40}$/.test(v)
    const q = new URLSearchParams(window.location.search).get('ref')
    if (valid(q)) localStorage.setItem('inkpilot.ref', q)
    const stored = localStorage.getItem('inkpilot.ref')
    return valid(stored) ? (stored as Address) : undefined
  })
  return ref && ref.toLowerCase() !== self?.toLowerCase() ? ref : undefined
}

/** Share link for inviting a friend. Resolved once on mount (see share helper rules). */
export function useInviteLink(address?: Address): string | undefined {
  const [link, setLink] = useState<string>()
  useEffect(() => {
    let live = true
    if (!address) return
    void buildShareLink(`/?ref=${address}`).then((l) => { if (live) setLink(l) })
    return () => {
      live = false
    }
  }, [address])
  return useMemo(() => (address ? link : undefined), [address, link])
}
