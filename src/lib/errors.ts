/** Turns wallet and RPC errors into one plain sentence. Never shows raw error text. */
export function plainError(error: unknown): string {
  const e = error as { message?: string; shortMessage?: string; code?: number; cause?: { code?: number } } | null
  const m = `${e?.shortMessage ?? ''} ${e?.message ?? ''}`.toLowerCase()
  if (e?.code === 4001 || e?.cause?.code === 4001 || m.includes('user rejected') || m.includes('user denied') || m.includes('cancelled') || m.includes('canceled')) {
    return 'Cancelled in your wallet.'
  }
  if (m.includes('wallet client is not ready')) return 'Wallet is not ready yet. Reconnect and try again.'
  if (m.includes('insufficient funds') || m.includes('exceeds balance') || m.includes('transfer amount exceeds')) {
    return 'Not enough funds for this or for network fees. You need test USDC and a little Ink Sepolia ETH for fees.'
  }
  if (m.includes('chain') && (m.includes('switch') || m.includes('wrong') || m.includes('unsupported'))) {
    return 'Please switch to Ink Sepolia in your wallet and try again.'
  }
  if (m.includes('marketnotactive') || m.includes('market not active')) return 'Safe but locked: the lending market is not accepting new deposits right now.'
  if (m.includes('marketpaused') || m.includes('market paused')) return 'Safe but locked: the lending market is paused, so nothing can move yet.'
  if (m.includes('borrowingdisabled') || m.includes('borrowing disabled')) return 'Borrowing is not available in this market right now.'
  if (m.includes('breakeractive') || m.includes('breaker active')) return 'This action is paused by the safety breaker right now. Withdrawals and protection still work.'
  if (m.includes('healthtoolow') || m.includes('health too low')) return 'That would leave your position too close to its limit. Try a smaller amount.'
  if (m.includes('healthy')) return 'Your position is healthy, so there is nothing to protect right now.'
  if (m.includes('cooldownactive') || m.includes('cooldown active')) return 'Protection just ran. Try again in a minute.'
  if (m.includes('noprogress') || m.includes('no progress')) return 'Protection could not improve this position right now.'
  if (m.includes('nothingtoprotect') || m.includes('nothing to protect')) return 'You have no borrowing, so there is nothing to protect.'
  if (m.includes('faucetcooldown') || m.includes('faucet cooldown')) return 'You already claimed test USDC recently. You can claim again every 6 hours.'
  if (m.includes('accountalreadyexists') || m.includes('account already exists')) return 'You already have an InkPilot account.'
  if (m.includes('network') || m.includes('timeout') || m.includes('failed to fetch') || m.includes('econn')) {
    return 'Network issue. Check your connection and try again.'
  }
  return 'That did not go through. Please try again.'
}
