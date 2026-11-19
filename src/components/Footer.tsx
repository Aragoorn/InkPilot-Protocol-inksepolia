export function Footer() {
  return (
    <footer className="mx-auto max-w-5xl px-4 pb-24 pt-8 text-sm" style={{ color: 'var(--muted)', borderTop: '1px solid var(--line)' }}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <nav className="flex flex-wrap gap-4" aria-label="Footer">
          <a href="#how" className="underline-offset-4 hover:underline">How it works</a>
          <a href="#stats" className="underline-offset-4 hover:underline">Contract status</a>
        </nav>
        <p>Testnet demo. Not financial advice. Protection reduces risk, it does not remove it.</p>
      </div>
    </footer>
  )
}
