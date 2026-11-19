import type { PublicClient } from 'viem'

/** The Ink Sepolia RPC rejects log queries wider than 1,000 blocks, so stay safely under that. */
const STEP = 990n
const PARALLEL = 8

/** Runs a range query over [from, to] in bounded chunks, several at a time, keeping block order. */
export async function chunked<T>(from: bigint, to: bigint, run: (from: bigint, to: bigint) => Promise<T[]>): Promise<T[]> {
  const ranges: [bigint, bigint][] = []
  for (let f = from; f <= to; f += STEP) ranges.push([f, f + STEP - 1n > to ? to : f + STEP - 1n])
  const out: T[] = []
  for (let i = 0; i < ranges.length; i += PARALLEL) {
    const batch = await Promise.all(ranges.slice(i, i + PARALLEL).map(([f, t]) => run(f, t)))
    for (const items of batch) out.push(...items)
  }
  return out
}

const cache = new Map<string, { next: bigint; items: unknown[] }>()

/**
 * Incremental scan: the first call reads from `from` to `head`, later calls read only the new blocks.
 * The caller picks `head` once, so related scans (for example accounts and their events) share one height.
 */
export async function incremental<T>(
  key: string,
  from: bigint,
  head: bigint,
  run: (from: bigint, to: bigint) => Promise<T[]>,
): Promise<T[]> {
  const entry = cache.get(key) ?? { next: from, items: [] }
  if (entry.next <= head) {
    const fresh = await chunked(entry.next, head, run)
    entry.items = [...entry.items, ...fresh]
    entry.next = head + 1n
    cache.set(key, entry)
  }
  return entry.items as T[]
}

export type { PublicClient }
