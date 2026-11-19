import { useEffect, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { X } from 'lucide-react'
import { formatUsdc, parseUsdc } from '@/onchain-money'
import { usd } from '@/lib/format'
import { TxProgress } from '@/components/TxProgress'
import type { FlowStatus } from '@/hooks/useTxFlow'

interface Props {
  open: boolean
  title: string
  cta: string
  max: bigint
  maxLabel: string
  note?: string
  status: FlowStatus
  onClose: () => void
  onConfirm: (amount: bigint) => void
}

export function AmountSheet({ open, title, cta, max, maxLabel, note, status, onClose, onConfirm }: Props) {
  const [value, setValue] = useState('')
  useEffect(() => {
    if (!open) setValue('')
  }, [open])
  let parsed: bigint | null = null
  let parseError: string | null = null
  try {
    parsed = value ? parseUsdc(value) : null
  } catch {
    parsed = null
    if (value) parseError = 'Enter a valid USDC amount with up to 6 decimal places.'
  }
  const invalid = parsed === null || parsed <= 0n || parsed > max
  const tooHigh = parsed !== null && parsed > max
  return (
    <AnimatePresence>
      {open && (
        <motion.div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} style={{ background: 'rgba(3,4,10,.7)' }} onClick={onClose}>
          <motion.div
            role="dialog"
            aria-label={title}
            className="ip-card w-full max-w-md p-5 sm:mb-0"
            style={{ background: '#0e1020', borderBottomLeftRadius: 0, borderBottomRightRadius: 0 }}
            initial={{ y: 60 }}
            animate={{ y: 0 }}
            exit={{ y: 60 }}
            transition={{ type: 'spring', stiffness: 380, damping: 34 }}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-4 flex items-center justify-between">
              <h3 className="text-lg font-bold">{title}</h3>
              <button className="ip-btn ip-ghost !min-h-[44px] !px-3" onClick={onClose} aria-label="Close">
                <X size={18} />
              </button>
            </div>
            <label className="ip-label" htmlFor="amt">Amount in USDC</label>
            <div className="mt-2 flex gap-2">
              <input
                id="amt"
                className="ip-input tabular text-2xl font-bold"
                inputMode="decimal"
                placeholder="0.00"
                value={value}
                onChange={(e) => {
                  const next = e.target.value.replace(/[^0-9.]/g, '')
                  const parts = next.split('.')
                  setValue(parts.length <= 2 ? next : `${parts[0]}.${parts.slice(1).join('')}`)
                }}
              />
              <button className="ip-btn ip-ghost" onClick={() => setValue(formatUsdc(max))} disabled={max <= 0n}>Max</button>
            </div>
            <p className="mt-2 text-sm" style={{ color: 'var(--muted)' }}>{maxLabel}: <span className="tabular">{usd(max)}</span></p>
            {parseError && <p className="mt-2 text-sm" style={{ color: 'var(--red)' }}>{parseError}</p>}
            {tooHigh && !parseError && <p className="mt-2 text-sm" style={{ color: 'var(--red)' }}>Amount is higher than available.</p>}
            {note && <p className="mt-2 text-sm" style={{ color: 'var(--muted)' }}>{note}</p>}
            <button className="ip-btn ip-primary mt-4 w-full" disabled={invalid || status.running} onClick={() => parsed && onConfirm(parsed)}>
              {status.running ? 'Working...' : cta}
            </button>
            <TxProgress status={status} />
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
