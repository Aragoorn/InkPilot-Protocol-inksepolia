import { Terminal } from 'lucide-react'

/** Shown until deploy.sh has written the contract addresses into .env. */
export function SetupNeeded() {
  return (
    <div className="mx-auto max-w-xl px-4 py-20">
      <span className="grid h-12 w-12 place-items-center rounded-xl" style={{ background: 'rgba(91,140,255,.14)' }}><Terminal size={22} color="var(--blue)" /></span>
      <h1 className="mt-4 text-3xl font-extrabold ip-display">InkPilot is not deployed on Ink Sepolia yet</h1>
      <p className="mt-2 text-[15px] leading-relaxed" style={{ color: 'var(--muted)' }}>
        The app reads its contract addresses from <code>.env</code>. Deploy once, and they are filled in for you:
      </p>
      <pre className="ip-inner mt-4 overflow-x-auto p-4 text-sm leading-relaxed"><code>{`cp .env.example .env     # then set PRIVATE_KEY
./deploy.sh check
./deploy.sh simulate
./deploy.sh deploy
bun run dev`}</code></pre>
      <p className="mt-3 text-sm" style={{ color: 'var(--muted)' }}>Full steps are in README.md.</p>
    </div>
  )
}
