"use client";

import { useState } from "react";

interface QueuedOperation {
  opHash: string;
  executeAfter: number;
  executed: boolean;
  cancelled: boolean;
}

export default function QueuePage() {
  const [walletAddress, setWalletAddress] = useState(
    process.env.NEXT_PUBLIC_WALLET_ADDRESS || ""
  );
  const [operations, setOperations] = useState<QueuedOperation[]>([]);
  const [loading, setLoading] = useState(false);

  // In a full implementation, this would read from the smart contract
  // using wagmi/viem. For now, show the UI structure.

  const mockOps: QueuedOperation[] = [
    {
      opHash: "0xabc123...def456",
      executeAfter: Math.floor(Date.now() / 1000) + 1800,
      executed: false,
      cancelled: false,
    },
    {
      opHash: "0x789abc...123def",
      executeAfter: Math.floor(Date.now() / 1000) - 600,
      executed: false,
      cancelled: false,
    },
    {
      opHash: "0xdef789...abc123",
      executeAfter: Math.floor(Date.now() / 1000) - 3600,
      executed: true,
      cancelled: false,
    },
  ];

  const now = Math.floor(Date.now() / 1000);

  const getStatus = (op: QueuedOperation) => {
    if (op.executed) return { label: "Executed", color: "text-green-400 bg-green-400/10" };
    if (op.cancelled) return { label: "Cancelled", color: "text-gray-400 bg-gray-400/10" };
    if (now >= op.executeAfter) return { label: "Ready", color: "text-blue-400 bg-blue-400/10" };
    return { label: "Pending", color: "text-orange-400 bg-orange-400/10" };
  };

  const formatTimeRemaining = (executeAfter: number) => {
    const diff = executeAfter - now;
    if (diff <= 0) return "Ready to execute";
    const minutes = Math.floor(diff / 60);
    const seconds = diff % 60;
    return `${minutes}m ${seconds}s remaining`;
  };

  return (
    <div>
      <h2 className="text-2xl font-bold mb-2">Pending Queue</h2>
      <p className="text-gray-400 mb-6">
        High-risk operations waiting for their delay period to elapse
      </p>

      <div className="mb-6">
        <label className="block text-sm text-gray-400 mb-1">
          Wallet Address
        </label>
        <div className="flex gap-2">
          <input
            type="text"
            value={walletAddress}
            onChange={(e) => setWalletAddress(e.target.value)}
            placeholder="0x..."
            className="flex-1 bg-gray-900 border border-gray-700 rounded-lg px-4 py-2 text-sm font-mono focus:outline-none focus:border-blue-500"
          />
          <button
            onClick={() => setOperations(mockOps)}
            className="bg-gray-800 hover:bg-gray-700 px-4 py-2 rounded-lg text-sm transition"
          >
            Load Queue
          </button>
        </div>
      </div>

      {operations.length === 0 ? (
        <div className="bg-gray-900 border border-gray-800 rounded-lg p-8 text-center text-gray-500">
          No queued operations. Click &quot;Load Queue&quot; to fetch from the
          wallet contract.
        </div>
      ) : (
        <div className="space-y-3">
          {operations.map((op) => {
            const status = getStatus(op);
            return (
              <div
                key={op.opHash}
                className="bg-gray-900 border border-gray-800 rounded-lg p-4"
              >
                <div className="flex items-center justify-between mb-2">
                  <span className="font-mono text-sm text-gray-300">
                    {op.opHash}
                  </span>
                  <span
                    className={`px-2 py-0.5 rounded text-xs font-medium ${status.color}`}
                  >
                    {status.label}
                  </span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-gray-400">
                    Execute after:{" "}
                    {new Date(op.executeAfter * 1000).toLocaleString()}
                  </span>
                  <span className="text-gray-400">
                    {formatTimeRemaining(op.executeAfter)}
                  </span>
                </div>
                {!op.executed && !op.cancelled && (
                  <div className="flex gap-2 mt-3">
                    {now >= op.executeAfter && (
                      <button className="bg-green-600 hover:bg-green-700 text-white px-3 py-1.5 rounded text-sm transition">
                        Execute Now
                      </button>
                    )}
                    <button className="bg-red-600/20 hover:bg-red-600/30 text-red-400 border border-red-800 px-3 py-1.5 rounded text-sm transition">
                      Cancel
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
