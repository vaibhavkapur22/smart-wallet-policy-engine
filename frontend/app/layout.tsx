import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Policy Smart Wallet",
  description: "Risk-based authorization for on-chain transactions",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen">
        <nav className="border-b border-gray-800 px-6 py-4">
          <div className="max-w-7xl mx-auto flex items-center justify-between">
            <h1 className="text-xl font-bold tracking-tight">
              Policy Smart Wallet
            </h1>
            <div className="flex gap-6 text-sm text-gray-400">
              <a href="/" className="hover:text-white transition">
                Dashboard
              </a>
              <a href="/send" className="hover:text-white transition">
                Send Transaction
              </a>
              <a href="/queue" className="hover:text-white transition">
                Pending Queue
              </a>
              <a href="/admin" className="hover:text-white transition">
                Admin
              </a>
            </div>
          </div>
        </nav>
        <main className="max-w-7xl mx-auto px-6 py-8">{children}</main>
      </body>
    </html>
  );
}
