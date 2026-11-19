import { ExternalLink } from 'lucide-react'
import { usePublicStats } from '@/hooks/usePublicStats'
import { usd } from '@/lib/format'
import { addressUrl } from '@/lib/explorer'
import { ACCOUNT_IMPL, FACTORY, FACTORY_IMPL, LAB_ENABLED, POOL, TIMELOCK } from '@/lib/pilot'

const CONTRACTS = [
  { name: 'Factory (proxy)', address: FACTORY },
  { name: 'Factory logic', address: FACTORY_IMPL },
  { name: 'Account logic', address: ACCOUNT_IMPL },
  { name: '48h timelock', address: TIMELOCK },
  { name: LAB_ENABLED ? 'Demo lending pool' : 'Lending pool', address: POOL },
]

/** Public, verifiable numbers. Every figure is computed from chain events and contract state at load time. */
export function PublicStats() {
  const { data, isLoading, isError } = usePublicStats()
  const cell = (label: string, value: string) => (
    <div className="ip-card p-4"><p className="ip-label">{label}</p><p className="tabular mt-1 text-2xl font-extrabold">{isLoading ? '...' : isError ? 'n/a' : value}</p></div>
  )
  return (
    <section id="stats" className="mx-auto max-w-5xl px-4 py-12" aria-label="Public stats">
      <p className="ip-label">Verified onchain</p>
      <h2 className="mt-1 text-3xl font-extrabold ip-display">Numbers anyone can check</h2>
      <div className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        {cell('Active accounts', String(data?.accounts ?? 0))}
        {cell('Supplied to the market', usd(data?.supplied ?? 0n, 0))}
        {cell('Total invested', usd(data?.volume ?? 0n, 0))}
        {cell('Times Safe Mode acted', String(data?.protections ?? 0))}
      </div>
      <p className="mt-3 text-xs" style={{ color: 'var(--muted)' }}>Ink Sepolia testnet. Counted from factory and account events, up to block {data ? String(data.headBlock) : '...'}. {LAB_ENABLED ? 'The lending pool here is a demo stand-in, so these numbers are demo activity, not Tydro volume.' : 'Testnet numbers only.'}</p>
      <div className="ip-card mt-6 p-5">
        <p className="ip-label mb-3">Contract status</p>
        <ul className="grid gap-2 sm:grid-cols-2">
          {CONTRACTS.map((c) => (
            <li key={c.address}>
              <a className="flex items-center justify-between rounded-xl p-3 text-sm ip-inner" href={addressUrl(c.address)} target="_blank" rel="noopener noreferrer">
                <span>{c.name}</span><span className="flex items-center gap-1 tabular" style={{ color: 'var(--muted)' }}>{c.address.slice(0, 6)}...{c.address.slice(-4)} <ExternalLink size={12} /></span>
              </a>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
