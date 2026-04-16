import { Link, useLocation } from "react-router-dom";
import { useAccount, useConnect, useDisconnect } from "wagmi";

const NAV_ITEMS = [
  { path: "/", label: "Dashboard" },
  { path: "/setup", label: "Setup" },
  { path: "/logs", label: "Action Log" },
];

function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-3">
        <span className="text-sm text-slate-400 font-mono">
          {address.slice(0, 6)}...{address.slice(-4)}
        </span>
        <button
          onClick={() => disconnect()}
          className="px-3 py-1.5 text-sm rounded-lg border border-slate-600 text-slate-300 hover:bg-slate-700 transition-colors cursor-pointer"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <button
      onClick={() => connect({ connector: connectors[0] })}
      className="px-4 py-2 rounded-lg bg-guardian text-white font-medium hover:bg-guardian-dark transition-colors cursor-pointer"
    >
      Connect Wallet
    </button>
  );
}

export default function Layout({ children }: { children: React.ReactNode }) {
  const location = useLocation();

  return (
    <div className="min-h-screen bg-slate-950">
      {/* Background gradient */}
      <div className="fixed inset-0 bg-gradient-to-br from-guardian/5 via-transparent to-purple-900/5 pointer-events-none" />

      {/* Nav */}
      <nav className="relative z-10 border-b border-slate-800/80">
        <div className="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
          <div className="flex items-center gap-8">
            <Link to="/" className="flex items-center gap-2 no-underline">
              <div className="w-8 h-8 rounded-lg bg-guardian/20 flex items-center justify-center">
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  className="w-5 h-5 text-guardian-light"
                >
                  <path
                    d="M12 2L3 7v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-9-5z"
                    fill="currentColor"
                    opacity="0.2"
                  />
                  <path
                    d="M12 2L3 7v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-9-5z"
                    stroke="currentColor"
                    strokeWidth="1.5"
                  />
                </svg>
              </div>
              <span className="font-semibold text-white text-lg">
                Guardian
              </span>
            </Link>

            <div className="flex gap-1">
              {NAV_ITEMS.map((item) => (
                <Link
                  key={item.path}
                  to={item.path}
                  className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors no-underline ${
                    location.pathname === item.path
                      ? "bg-guardian/15 text-guardian-light"
                      : "text-slate-400 hover:text-slate-200 hover:bg-slate-800/50"
                  }`}
                >
                  {item.label}
                </Link>
              ))}
            </div>
          </div>

          <ConnectButton />
        </div>
      </nav>

      {/* Main content */}
      <main className="relative z-10 max-w-6xl mx-auto px-6 py-8">
        {children}
      </main>
    </div>
  );
}
