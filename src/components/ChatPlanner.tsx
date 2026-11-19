import { useRef, useState } from 'react'
import { motion } from 'framer-motion'
import { Send, ShieldCheck } from 'lucide-react'
import { planFrom, type Plan, type Reply } from '@/lib/planner'

interface Msg {
  from: 'you' | 'pilot'
  text: string
  reply?: Reply
}

const SUGGESTIONS = ['I have 1,000 USDC. I want to invest safely.', 'Put 500 USDC to work with 2x boost and compound my profit']

interface Props {
  ctaLabel: string
  busy?: boolean
  onStart: (plan: Plan) => void
  disabledReason?: string
}

export function ChatPlanner({ ctaLabel, busy, onStart, disabledReason }: Props) {
  const [msgs, setMsgs] = useState<Msg[]>([
    { from: 'pilot', text: 'Hi, I am InkPilot. Tell me what you want to do with your money and I will set it up, step by step, for you to approve.' },
  ])
  const [text, setText] = useState('')
  const end = useRef<HTMLDivElement>(null)

  const send = (value: string) => {
    const t = value.trim()
    if (!t) return
    const reply = planFrom(t)
    setMsgs((m) => [...m, { from: 'you', text: t }, { from: 'pilot', text: reply.text, reply }])
    setText('')
    setTimeout(() => end.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' }), 50)
  }

  return (
    <div className="ip-card flex flex-col p-4 sm:p-5">
      <div className="flex max-h-[420px] min-h-[220px] flex-col gap-3 overflow-y-auto pr-1">
        {msgs.map((m, i) => (
          <motion.div key={i} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} className={m.from === 'you' ? 'self-end' : 'self-start'} style={{ maxWidth: '92%' }}>
            <div
              className="rounded-2xl px-4 py-3 text-[15px] leading-relaxed"
              style={{ background: m.from === 'you' ? 'linear-gradient(135deg,#4a6fd6,#7c55d6)' : 'var(--surface-strong)', border: '1px solid var(--line)' }}
            >
              {m.text}
              {m.reply?.honesty && (
                <p className="mt-3 flex gap-2 rounded-xl p-3 text-sm" style={{ background: 'rgba(255,200,87,.08)', color: '#ffd98a' }}>
                  <ShieldCheck size={16} className="mt-0.5 shrink-0" /> {m.reply.honesty}
                </p>
              )}
              {m.reply?.plan && (
                <div className="ip-inner mt-3 p-3">
                  <p className="ip-label mb-2">The plan</p>
                  <ol className="space-y-1.5 text-sm" style={{ color: 'var(--text)' }}>
                    {m.reply.plan.steps.map((s, k) => (
                      <li key={k} className="flex gap-2">
                        <span className="tabular" style={{ color: 'var(--blue)' }}>{k + 1}.</span> {s}
                      </li>
                    ))}
                  </ol>
                  <button className="ip-btn ip-primary mt-3 w-full" disabled={busy || !!disabledReason} onClick={() => m.reply?.plan && onStart(m.reply.plan)}>
                    {ctaLabel}
                  </button>
                  {disabledReason && <p className="mt-2 text-xs" style={{ color: 'var(--muted)' }}>{disabledReason}</p>}
                </div>
              )}
            </div>
          </motion.div>
        ))}
        <div ref={end} />
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        {SUGGESTIONS.map((s) => (
          <button key={s} className="ip-btn ip-ghost !min-h-[44px] !px-3 !text-[13px] !font-semibold" onClick={() => send(s)}>
            {s}
          </button>
        ))}
      </div>
      <form
        className="mt-3 flex gap-2"
        onSubmit={(e) => {
          e.preventDefault()
          send(text)
        }}
      >
        <input className="ip-input" value={text} onChange={(e) => setText(e.target.value)} placeholder="e.g. I have 1,000 USDC and want to invest safely" aria-label="Message InkPilot" />
        <button className="ip-btn ip-primary !px-4" aria-label="Send" type="submit">
          <Send size={18} />
        </button>
      </form>
    </div>
  )
}
