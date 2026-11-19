import { parseUsdc } from '@/onchain-money'
import { usd } from '@/lib/format'

export interface Plan {
  amount: bigint | null
  boost: boolean
  /** 0 = Save Profits, 1 = Auto-Compound */
  mode: 0 | 1
  reserve: bigint
  steps: string[]
}

export interface Reply {
  text: string
  honesty?: string
  plan?: Plan
}

/**
 * Rule-based planner. It reads the message with plain pattern matching and never custodies anything.
 * It only proposes steps; every step still needs a wallet signature from the user.
 */
export function planFrom(message: string): Reply {
  const m = message.toLowerCase()
  const amount = readAmount(message)
  const wantsBoost = /\b2x\b|leverage|boost|aggressive|max(imum)? (yield|return)/.test(m)
  const compound = /compound|reinvest|auto/.test(m)
  const safety = /never lose|no loss|can'?t lose|without (any )?risk|safe|protect|secure/.test(m)

  if (!amount) {
    return {
      text: 'Tell me how much USDC you want to put to work, for example: "I have 1,000 USDC. I want to invest safely." or "Put 500 USDC to work with 2x boost."',
    }
  }
  const boost = wantsBoost
  const reserve = boost ? amount / 5n : 0n
  const working = amount - reserve
  const mode: 0 | 1 = compound ? 1 : 0
  const steps = [
    'Create your personal InkPilot account (one time, you stay the only owner)',
    `Allow InkPilot to use ${usd(amount)} USDC`,
    `Put ${usd(working)} to work in the lending market`,
    ...(reserve > 0n ? [`Set aside ${usd(reserve)} as your protection reserve`] : []),
    ...(boost ? ['Turn on Boost at up to 2x (your choice, easy to turn off)'] : []),
    mode === 1 ? 'Reinvest your profit automatically' : 'Keep your profit in a savings balance you can withdraw any time',
  ]
  const text = boost
    ? `Here is a plan for ${usd(amount)}. Boost can raise earnings and risk, so I keep ${usd(reserve)} aside as a safety reserve and Safe Mode watches your position.`
    : `Here is a plan for ${usd(amount)}. You earn lending yield with no borrowing, so there is nothing that can be liquidated.`
  const honesty = safety
    ? 'I cannot promise you will never lose money. What this setup can do: without Boost there is no liquidation risk, and with Boost Safe Mode can act before liquidation. Remaining risks include the lending market, smart contracts, and the stablecoin.'
    : undefined
  return { text, honesty, plan: { amount, boost, mode, reserve, steps } }
}

function readAmount(message: string): bigint | null {
  const cleaned = message.replace(/,/g, '')
  const match = cleaned.match(/(\d+(?:\.\d{1,6})?|\.\d{1,6})\s*(k|thousand)?\b/i)
  if (!match) return null
  const num = match[1].startsWith('.') ? `0${match[1]}` : match[1]
  const suffix = match[2]?.toLowerCase()
  try {
    let raw: bigint
    if (suffix === 'k' || suffix === 'thousand') {
      const [whole, frac = ''] = num.split('.')
      const micros = `${whole}${frac.padEnd(3, '0').slice(0, 3)}${''.padEnd(Math.max(0, frac.length - 3), '0')}`
      // k = * 1000 in USDC units: parse base micros-equivalent by shifting decimal 3 places
      const baseMicros = BigInt(micros.padEnd(micros.length + Math.max(0, 3 - frac.length), '0'))
      // easier: parse integer+frac then multiply carefully
      const scaled = scaleDecimalStringByThousand(num)
      raw = parseUsdc(scaled)
    } else {
      raw = parseUsdc(num)
    }
    return raw > 0n ? raw : null
  } catch {
    return null
  }
}

function scaleDecimalStringByThousand(value: string): string {
  const [whole, frac = ''] = value.split('.')
  const digits = `${whole}${frac}`
  const shift = 3
  if (frac.length <= shift) {
    return `${digits}${'0'.repeat(shift - frac.length)}`
  }
  const cut = digits.length - (frac.length - shift)
  return `${digits.slice(0, cut)}.${digits.slice(cut)}`
}
