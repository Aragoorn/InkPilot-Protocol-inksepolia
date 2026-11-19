import { useState } from 'react'
import { useModal } from 'connectkit'
import { motion } from 'framer-motion'
import { LineChart, ShieldCheck, Wallet } from 'lucide-react'
import { ChatPlanner } from '@/components/ChatPlanner'
import { EmailInfo } from '@/components/EmailInfo'
import { SafeModeExplainer } from '@/components/SafeModeExplainer'

const CARDS = [
  { icon: LineChart, title: 'Automated investing', body: 'Say how much you want to put to work. InkPilot sets it up and you approve each step.' },
  { icon: ShieldCheck, title: 'Capital protection', body: 'Safe Mode watches your position all day and acts before it gets close to its limit.' },
  { icon: Wallet, title: 'Withdraw anytime', body: 'Your money stays in an account only you control. Take it out whenever you like.' },
]

export function Landing() {
  const { setOpen } = useModal()
  const [email, setEmail] = useState(false)
  return (
    <>
      <section className="mx-auto max-w-5xl px-4 pb-8 pt-16 text-center sm:pt-24">
        <motion.h1 initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} className="mx-auto max-w-3xl text-5xl font-extrabold ip-display sm:text-7xl">
          Grow your assets{' '}
          <span style={{ background: 'linear-gradient(135deg,var(--blue),var(--purple))', WebkitBackgroundClip: 'text', color: 'transparent' }}>safely.</span>
          <br />No complexity.
        </motion.h1>
        <p className="mx-auto mt-5 max-w-xl text-lg" style={{ color: 'var(--muted)' }}>
          Tell InkPilot what you want in plain words. It sets it up, watches it, and steps in to protect it.
        </p>
        <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <button className="ip-btn ip-primary !min-h-[52px] !px-8 !text-base" onClick={() => setOpen(true)}>Connect wallet</button>
          <button className="ip-btn ip-ghost !min-h-[52px] !px-8 !text-base" onClick={() => setEmail(true)}>Start without a wallet</button>
        </div>
        <p className="mt-4 text-xs" style={{ color: 'var(--muted)' }}>Live on Ink Sepolia (testnet) with test tokens. Nothing here uses real money.</p>
      </section>

      <section className="mx-auto grid max-w-5xl gap-3 px-4 py-8 sm:grid-cols-3" aria-label="What you get">
        {CARDS.map((c) => (
          <div key={c.title} className="ip-card p-5">
            <span className="grid h-10 w-10 place-items-center rounded-xl" style={{ background: 'rgba(91,140,255,.14)' }}><c.icon size={20} color="var(--blue)" /></span>
            <h3 className="mt-3 text-lg font-bold">{c.title}</h3>
            <p className="mt-1 text-sm leading-relaxed" style={{ color: 'var(--muted)' }}>{c.body}</p>
          </div>
        ))}
      </section>

      <section id="how" className="mx-auto max-w-3xl px-4 py-10" aria-label="Try it">
        <p className="ip-label text-center">Try it</p>
        <h2 className="mt-1 text-center text-3xl font-extrabold ip-display">Just say what you want</h2>
        <div className="mt-6">
          <ChatPlanner ctaLabel="Connect wallet to start" onStart={() => setOpen(true)} />
        </div>
        <p className="mt-3 text-center text-xs" style={{ color: 'var(--muted)' }}>This preview only builds a plan. Nothing moves until you connect and approve each step in your wallet.</p>
      </section>
      <SafeModeExplainer />
      <EmailInfo open={email} onClose={() => setEmail(false)} />
    </>
  )
}
