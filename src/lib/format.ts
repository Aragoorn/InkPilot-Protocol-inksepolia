import { formatUnitsFixed } from '@/onchain-money'

export const usd = (raw: bigint, digits = 2): string => `$${formatUnitsFixed(raw, 6, digits)}`
export const signedUsd = (raw: bigint, digits = 2): string =>
  raw < 0n ? `-$${formatUnitsFixed(-raw, 6, digits)}` : `+$${formatUnitsFixed(raw, 6, digits)}`
export const short = (a: string): string => `${a.slice(0, 6)}...${a.slice(-4)}`
export const ago = (ts: number): string => {
  const s = Math.max(0, Math.floor(Date.now() / 1000) - ts)
  if (s < 60) return 'just now'
  if (s < 3600) return `${Math.floor(s / 60)} min ago`
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`
  return `${Math.floor(s / 86400)} d ago`
}
