import { useAccount } from 'wagmi'
import { Header } from '@/components/Header'
import { Landing } from '@/components/Landing'
import { Dashboard } from '@/components/Dashboard'
import { Rescues } from '@/components/Rescues'
import { PublicStats } from '@/components/PublicStats'
import { Footer } from '@/components/Footer'
import { SetupNeeded } from '@/components/SetupNeeded'
import { PreviewPage } from '@/preview/PreviewPage'
import { CONFIG_READY } from '@/lib/pilot'

const isPreview = new URLSearchParams(window.location.search).get('preview') === '1'

export default function App() {
  const { isConnected } = useAccount()
  return (
    <div className="ip-glow min-h-dvh">
      <Header />
      <main>
        {isPreview ? (
          <PreviewPage />
        ) : !CONFIG_READY ? (
          <>
            {isConnected ? <SetupNeeded /> : <Landing />}
            <div className="mx-auto max-w-5xl px-4 pb-4">
              <p className="ip-card p-4 text-sm" style={{ color: 'var(--muted)' }}>
                The contracts are not deployed yet, so live data is off. See the screens with sample values in the <a className="underline" href="/?preview=1">design preview</a>, or follow the README to deploy.
              </p>
            </div>
          </>
        ) : (
          <>
            {isConnected ? <Dashboard /> : <Landing />}
            {!isConnected && <Rescues />}
            <PublicStats />
          </>
        )}
      </main>
      <Footer />
    </div>
  )
}
