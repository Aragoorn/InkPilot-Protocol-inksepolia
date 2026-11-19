import { ExternalLink } from 'lucide-react'
import type { Activity } from '@/hooks/useActivity'
import { ago } from '@/lib/format'
import { txUrl } from '@/lib/explorer'

export function ActivityList({ items, loading }: { items: Activity[]; loading: boolean }) {
  return (
    <section className="ip-card p-5" aria-label="History">
      <p className="ip-label mb-3">What happened</p>
      {loading && items.length === 0 && <p className="text-sm" style={{ color: 'var(--muted)' }}>Loading your history from the chain...</p>}
      {!loading && items.length === 0 && <p className="text-sm" style={{ color: 'var(--muted)' }}>Nothing yet. Your deposits and every protection action will show up here in plain words.</p>}
      <ul className="space-y-3">
        {items.slice(0, 12).map((a) => (
          <li key={a.id} className="flex items-start gap-3 text-sm">
            <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full" style={{ background: a.kind === 'Protected' ? 'var(--green)' : 'var(--blue)' }} />
            <div className="min-w-0 flex-1">
              <p className="leading-snug">{a.text}</p>
              <p className="mt-0.5 text-xs" style={{ color: 'var(--muted)' }}>{a.ts ? ago(a.ts) : `Block ${a.block}`}</p>
            </div>
            <a href={txUrl(a.tx)} target="_blank" rel="noopener noreferrer" aria-label="View on explorer" className="p-2" style={{ color: 'var(--muted)' }}>
              <ExternalLink size={14} />
            </a>
          </li>
        ))}
      </ul>
    </section>
  )
}
