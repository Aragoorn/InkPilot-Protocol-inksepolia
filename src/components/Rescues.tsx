import { ShieldCheck } from 'lucide-react'
import { usePublicStats } from '@/hooks/usePublicStats'
import { usd, ago, short } from '@/lib/format'
import { txUrl } from '@/lib/explorer'
import { LAB_ENABLED } from '@/lib/pilot'
import { ReceiptCard } from '@/components/ReceiptCard'

const WHAT = ['', 'added a safety buffer', 'paid down borrowing', 'moved back to safe Earn mode', 'used own earnings to reduce borrowing']

/** Recent real protection actions read from the chain. Empty until someone has actually been protected. */
export function Rescues() {
  const { data, isLoading } = usePublicStats()
  return (
    <section className="mx-auto max-w-5xl px-4 py-12" aria-label="Rescue receipts">
      <p className="ip-label">Rescue receipts</p>
      <h2 className="mt-1 text-3xl font-extrabold ip-display">Every time Safe Mode steps in, it leaves a receipt</h2>
      <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {isLoading && <p className="text-sm" style={{ color: 'var(--muted)' }}>Reading the chain...</p>}
        {!isLoading && (data?.receipts.length ?? 0) === 0 && (
          <>
            <div className="ip-card p-5 sm:col-span-2 lg:col-span-1">
              <p className="font-bold">No rescues yet.</p>
              <p className="mt-1 text-sm leading-relaxed" style={{ color: 'var(--muted)' }}>This list is read live from the chain and shows only real events. {LAB_ENABLED ? 'Open an account, turn on Boost, spike the borrowing cost in the testnet lab, and your first receipt will appear here.' : 'Your first receipt will appear here the first time Safe Mode protects a position.'}</p>
            </div>
            <div className="sm:col-span-2">
              <p className="ip-label mb-2">Example receipt (sample values)</p>
              <ReceiptCard receipt={{ tier: 1, amount: 50_000_000n, hfBefore: 12400n, hfAfter: 14500n }} />
            </div>
          </>
        )}
        {data?.receipts.map((r) => (
          <a key={r.tx} href={txUrl(r.tx)} target="_blank" rel="noopener noreferrer" className="ip-card block p-4">
            <div className="flex items-center gap-2" style={{ color: 'var(--green)' }}><ShieldCheck size={16} /><span className="text-sm font-bold">Position protected</span></div>
            <p className="mt-2 text-sm">{short(r.account)} {WHAT[r.tier] ?? 'was protected'}{r.amount > 0n ? ` (${usd(r.amount)})` : ''}.</p>
            <p className="mt-2 text-xs" style={{ color: 'var(--muted)' }}>{r.ts ? ago(r.ts) : `Block ${r.block}`}</p>
          </a>
        ))}
      </div>
    </section>
  )
}
