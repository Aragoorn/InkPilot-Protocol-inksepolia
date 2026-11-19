interface Props {
  mode: number
  busy: boolean
  onChange: (mode: 0 | 1) => void
}

export function ProfitToggle({ mode, busy, onChange }: Props) {
  const opts = [
    { v: 0 as const, title: 'Save profits', body: 'Profit goes to a savings balance you can withdraw any time.' },
    { v: 1 as const, title: 'Auto-compound', body: 'Profit is reinvested so your balance grows faster.' },
  ]
  return (
    <section className="ip-card p-5" aria-label="Profit handling">
      <p className="ip-label mb-3">What happens to profit</p>
      <div role="radiogroup" className="grid grid-cols-2 gap-2">
        {opts.map((o) => {
          const on = Number(mode) === o.v
          return (
            <button
              key={o.v}
              role="radio"
              aria-checked={on}
              disabled={busy}
              onClick={() => !on && onChange(o.v)}
              className="min-h-[44px] rounded-xl p-3 text-left transition"
              style={{ background: on ? 'rgba(91,140,255,.14)' : 'var(--surface)', border: `1px solid ${on ? 'var(--blue)' : 'var(--line)'}` }}
            >
              <span className="block text-sm font-bold">{o.title}</span>
              <span className="mt-1 block text-xs leading-snug" style={{ color: 'var(--muted)' }}>{o.body}</span>
            </button>
          )
        })}
      </div>
    </section>
  )
}
