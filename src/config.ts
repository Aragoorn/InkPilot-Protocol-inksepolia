/**
 * wagmi configuration: Ink Sepolia (testnet) only.
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, createConfig } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { inkSepolia } from 'viem/chains'
import { registerChain } from './tracing'
import { RPC_URL } from './lib/pilot'

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(inkSepolia.id, RPC_URL)

export const config = createConfig({
  chains: [inkSepolia],
  connectors: [injected()],
  transports: {
    [inkSepolia.id]: http(RPC_URL),
  },
})
