import { Check, Loader2, X, Circle } from 'lucide-react'
import type { FlowStatus } from '@/hooks/useTxFlow'

const LABEL = { waiting: 'Waiting', wallet: 'Confirm in your wallet', confirming: 'Confirming', done: 'Done', failed: 'Failed' } as const

export function TxProgress({ status }: { status: FlowStatus }) {
  if (status.labels.length === 0) return null
  return (
    <div className="ip-inner mt-4 space-y-2 p-3" role="status" aria-live="polite">
      {status.labels.map((l, i) => {
        const s = status.states[i]
        return (
          <div key={l} className="flex items-center gap-3 text-sm">
            {s === 'done' ? <Check size={16} color="var(--green)" /> : s === 'failed' ? <X size={16} color="var(--red)" /> : s === 'waiting' ? <Circle size={14} color="var(--muted)" /> : <Loader2 size={16} className="animate-spin" color="var(--blue)" />}
            <span className="flex-1">{l}</span>
            <span style={{ color: 'var(--muted)' }}>{LABEL[s]}</span>
          </div>
        )
      })}
      {status.error && <p className="pt-1 text-sm" style={{ color: 'var(--red)' }}>{status.error}</p>}
    </div>
  )
}
