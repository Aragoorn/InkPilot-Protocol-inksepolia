import { FlaskConical } from 'lucide-react'

interface Props {
  frozen: boolean
  busy: boolean
  onFreeze: (v: boolean) => void
  onSpike: () => void
}

/** Testnet only. These buttons change a stand-in lending pool so you can watch Safe Mode react. */
export function DemoControls({ frozen, busy, onFreeze, onSpike }: Props) {
  return (
    <section className="ip-card p-5" aria-label="Testnet demo controls" style={{ borderStyle: 'dashed' }}>
      <div className="flex items-center gap-2"><FlaskConical size={18} color="var(--amber)" /><p className="ip-label" style={{ color: 'var(--amber)' }}>Testnet lab</p></div>
      <p className="mt-2 text-sm leading-relaxed" style={{ color: 'var(--muted)' }}>
        The testnet lending pool is a stand-in, so you can stress it. These switches are open to everyone on testnet and do not exist on a real market.
      </p>
      <div className="mt-3 grid grid-cols-2 gap-2">
        <button className="ip-btn ip-ghost" disabled={busy} onClick={() => onFreeze(!frozen)}>{frozen ? 'Unfreeze market' : 'Freeze market'}</button>
        <button className="ip-btn ip-ghost" disabled={busy} onClick={onSpike}>Spike borrowing cost</button>
      </div>
    </section>
  )
}
