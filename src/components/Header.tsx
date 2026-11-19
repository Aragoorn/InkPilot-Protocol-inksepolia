import { ConnectKitButton } from 'connectkit'
import { Compass } from 'lucide-react'
import { short } from '@/lib/format'

export function Header() {
  return (
    <header className="sticky top-0 z-40" style={{ background: 'rgba(7,8,15,.72)', backdropFilter: 'blur(14px)', borderBottom: '1px solid var(--line)' }}>
      <div className="mx-auto flex h-16 max-w-5xl items-center justify-between px-4">
        <a href="/" className="flex items-center gap-2 text-lg font-extrabold ip-display" aria-label="InkPilot home">
          <span className="grid h-8 w-8 place-items-center rounded-lg" style={{ background: 'linear-gradient(135deg,var(--blue),var(--purple))' }}><Compass size={18} /></span>
          InkPilot
        </a>
        <div className="flex items-center gap-2">
        <span className="hidden rounded-full px-3 py-1 text-xs font-bold sm:block" style={{ background: 'rgba(155,107,255,.14)', color: '#c3a6ff' }}>Ink Sepolia testnet</span>
        <ConnectKitButton.Custom>
          {({ isConnected, show, address }) => (
            <button className={`ip-btn ${isConnected ? 'ip-ghost' : 'ip-primary'}`} onClick={show}>
              {isConnected && address ? short(address) : 'Connect wallet'}
            </button>
          )}
        </ConnectKitButton.Custom>
        </div>
      </div>
    </header>
  )
}
