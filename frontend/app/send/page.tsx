"use client";

import { useState } from "react";
import { decide, type PolicyDecision } from "@/lib/api";

const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID || 11155111);

const DECISION_STYLES: Record<string, { bg: string; text: string; label: string }> = {
  ALLOW: { bg: "bg-green-900/30 border-green-700", text: "text-green-400", label: "Approved — Execute immediately" },
  REQUIRE_SECOND_SIGNATURE: { bg: "bg-yellow-900/30 border-yellow-700", text: "text-yellow-400", label: "Guardian co-signature required" },
  REQUIRE_DELAY: { bg: "bg-orange-900/30 border-orange-700", text: "text-orange-400", label: "Queued — 1 hour delay required" },
  DENY: { bg: "bg-red-900/30 border-red-700", text: "text-red-400", label: "Denied — Transaction blocked" },
};

export default function SendTransaction() {
  const [target, setTarget] = useState("");
  const [value, setValue] = useState("");
  const [data, setData] = useState("0x");
  const [wallet, setWallet] = useState(
    process.env.NEXT_PUBLIC_WALLET_ADDRESS || ""
  );
  const [decision, setDecision] = useState<PolicyDecision | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError("");
    setDecision(null);

    try {
      // Convert ETH to wei
      const valueWei = value
        ? BigInt(Math.floor(parseFloat(value) * 1e18)).toString()
        : "0";

      const result = await decide({
        wallet,
        chain_id: CHAIN_ID,
        target,
        value: valueWei,
        data: data || "0x",
      });
      setDecision(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to get decision");
    } finally {
      setLoading(false);
    }
  };

  const style = decision ? DECISION_STYLES[decision.decision] : null;

  return (
    <div className="max-w-2xl">
      <h2 className="text-2xl font-bold mb-2">Send Transaction</h2>
      <p className="text-gray-400 mb-6">
        Preview risk assessment before executing
      </p>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">
            Wallet Address
          </label>
          <input
            type="text"
            value={wallet}
            onChange={(e) => setWallet(e.target.value)}
            placeholder="0x..."
            className="w-full bg-gray-900 border border-gray-700 rounded-lg px-4 py-2 text-sm font-mono focus:outline-none focus:border-blue-500"
          />
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-1">
            Recipient / Target
          </label>
          <input
            type="text"
            value={target}
            onChange={(e) => setTarget(e.target.value)}
            placeholder="0x..."
            required
            className="w-full bg-gray-900 border border-gray-700 rounded-lg px-4 py-2 text-sm font-mono focus:outline-none focus:border-blue-500"
          />
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-1">
            Value (ETH)
          </label>
          <input
            type="number"
            step="0.0001"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="0.0"
            className="w-full bg-gray-900 border border-gray-700 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-blue-500"
          />
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-1">
            Calldata (hex)
          </label>
          <textarea
            value={data}
            onChange={(e) => setData(e.target.value)}
            placeholder="0x"
            rows={3}
            className="w-full bg-gray-900 border border-gray-700 rounded-lg px-4 py-2 text-sm font-mono focus:outline-none focus:border-blue-500"
          />
        </div>

        <button
          type="submit"
          disabled={loading}
          className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 text-white font-medium rounded-lg px-4 py-2.5 transition"
        >
          {loading ? "Analyzing..." : "Preview & Assess Risk"}
        </button>
      </form>

      {error && (
        <div className="mt-4 p-4 bg-red-900/20 border border-red-800 rounded-lg text-red-400 text-sm">
          {error}
        </div>
      )}

      {decision && style && (
        <div className={`mt-6 border rounded-lg p-5 ${style.bg}`}>
          <div className="flex items-center justify-between mb-4">
            <h3 className={`text-lg font-bold ${style.text}`}>
              {style.label}
            </h3>
            <span
              className={`px-3 py-1 rounded-full text-xs font-bold ${style.text}`}
            >
              {decision.decision}
            </span>
          </div>

          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p className="text-gray-400">Transaction Type</p>
              <p className="font-mono">{decision.tx_type}</p>
            </div>
            <div>
              <p className="text-gray-400">Estimated USD Value</p>
              <p className="font-mono">${decision.usd_value.toFixed(2)}</p>
            </div>
            <div>
              <p className="text-gray-400">Risk Score</p>
              <div className="flex items-center gap-2 mt-1">
                <div className="w-32 h-2 bg-gray-800 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full ${
                      decision.risk_score < 0.3
                        ? "bg-green-500"
                        : decision.risk_score < 0.6
                          ? "bg-yellow-500"
                          : "bg-red-500"
                    }`}
                    style={{ width: `${decision.risk_score * 100}%` }}
                  />
                </div>
                <span>{(decision.risk_score * 100).toFixed(0)}%</span>
              </div>
            </div>
            <div>
              <p className="text-gray-400">Reason Codes</p>
              <div className="flex flex-wrap gap-1 mt-1">
                {decision.reason_codes.length > 0 ? (
                  decision.reason_codes.map((code) => (
                    <span
                      key={code}
                      className="px-2 py-0.5 bg-gray-800 rounded text-xs"
                    >
                      {code}
                    </span>
                  ))
                ) : (
                  <span className="text-gray-500">None</span>
                )}
              </div>
            </div>
          </div>

          {/* Simulation details */}
          {decision.simulation && (
            <div className="mt-4 pt-4 border-t border-gray-700/50">
              <h4 className="text-sm font-semibold text-gray-400 mb-2">
                Simulation Results
              </h4>
              <div className="text-sm space-y-1">
                {decision.simulation.eth_balance_delta !== "0" && (
                  <p>
                    ETH Balance Change:{" "}
                    <span className="font-mono">
                      {decision.simulation.eth_balance_delta}
                    </span>
                  </p>
                )}
                {decision.simulation.token_transfers.length > 0 && (
                  <p>
                    Token Transfers: {decision.simulation.token_transfers.length}
                  </p>
                )}
                {decision.simulation.has_unlimited_approval && (
                  <p className="text-red-400 font-semibold">
                    WARNING: Unlimited token approval detected
                  </p>
                )}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
