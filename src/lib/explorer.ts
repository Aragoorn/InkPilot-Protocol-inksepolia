import { CHAIN } from '@/lib/pilot'

const base = (CHAIN.blockExplorers?.default.url ?? '').replace(/\/+$/, '')

export const addressUrl = (address: string): string => `${base}/address/${address}`
export const txUrl = (hash: string): string => `${base}/tx/${hash}`
