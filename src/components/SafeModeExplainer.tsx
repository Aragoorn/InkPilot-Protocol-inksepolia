import { ArrowRight } from 'lucide-react'

const STEPS = [
  { n: '1', title: 'You choose', body: 'Earn with no borrowing, or add Boost up to 2x.' },
  { n: '2', title: 'It watches', body: 'Anyone can trigger protection, so it never depends on one server.' },
  { n: '3', title: 'It steps in', body: 'Adds a buffer from your reserve, pays down borrowing, or moves you back to safe Earn mode.' },
]

export function SafeModeExplainer() {
  return (
    <section className="mx-auto max-w-5xl px-4 py-10" aria-label="How Safe Mode works">
      <p className="ip-label text-center">Safe Mode</p>
      <h2 className="mt-1 text-center text-3xl font-extrabold ip-display">Protection that acts before it is late</h2>
      <ol className="mt-6 grid gap-3 sm:grid-cols-3">
        {STEPS.map((s, i) => (
          <li key={s.n} className="ip-card relative p-5">
            <span className="tabular grid h-8 w-8 place-items-center rounded-full text-sm font-extrabold" style={{ background: 'linear-gradient(135deg,var(--blue),var(--purple))' }}>{s.n}</span>
            <h3 className="mt-3 text-lg font-bold">{s.title}</h3>
            <p className="mt-1 text-sm leading-relaxed" style={{ color: 'var(--muted)' }}>{s.body}</p>
            {i < STEPS.length - 1 && <ArrowRight size={16} className="absolute right-4 top-5 hidden sm:block" color="var(--muted)" />}
          </li>
        ))}
      </ol>
    </section>
  )
}
