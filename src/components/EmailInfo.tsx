import { AnimatePresence, motion } from 'framer-motion'
import { X } from 'lucide-react'

export function EmailInfo({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div className="fixed inset-0 z-50 grid place-items-center p-4" style={{ background: 'rgba(3,4,10,.7)' }} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={onClose}>
          <motion.div role="dialog" aria-label="Start without a wallet" className="ip-card max-w-md p-5" style={{ background: '#0e1020' }} initial={{ y: 20 }} animate={{ y: 0 }} onClick={(e) => e.stopPropagation()}>
            <div className="flex items-start justify-between gap-3">
              <h3 className="text-lg font-bold">Start without a wallet</h3>
              <button className="ip-btn ip-ghost !px-3" onClick={onClose} aria-label="Close"><X size={18} /></button>
            </div>
            <p className="mt-2 text-sm leading-relaxed" style={{ color: 'var(--muted)' }}>
              Email and Apple sign-in creates a passkey wallet you control, with no app to install. It is not switched on in this build yet, because it needs the app owner to register this site with Circle (a client key and this site's domain). Nothing is held for you in the meantime.
            </p>
            <p className="mt-3 text-sm leading-relaxed" style={{ color: 'var(--muted)' }}>Until then, connect any browser wallet. On Ink Sepolia network fees are paid in free test ETH. Paying fees in USDC would need a paymaster, which is not built yet.</p>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
