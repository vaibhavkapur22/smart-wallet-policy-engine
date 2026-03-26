"use client";

import { useEffect, useState } from "react";
import { getAuditLogs, type AuditLog } from "@/lib/api";

const DECISION_COLORS: Record<string, string> = {
  ALLOW: "text-green-400 bg-green-400/10",
  REQUIRE_SECOND_SIGNATURE: "text-yellow-400 bg-yellow-400/10",
  REQUIRE_DELAY: "text-orange-400 bg-orange-400/10",
  DENY: "text-red-400 bg-red-400/10",
};

function RiskBar({ score }: { score: number }) {
  const pct = Math.round(score * 100);
  const color =
    score < 0.3
      ? "bg-green-500"
      : score < 0.6
        ? "bg-yellow-500"
        : "bg-red-500";
  return (
    <div className="flex items-center gap-2">
      <div className="w-24 h-2 bg-gray-800 rounded-full overflow-hidden">
        <div className={`h-full ${color} rounded-full`} style={{ width: `${pct}%` }} />
      </div>
      <span className="text-xs text-gray-400">{pct}%</span>
    </div>
  );
}

export default function Dashboard() {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getAuditLogs(20)
      .then(setLogs)
      .catch(() => setLogs([]))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div>
      <div className="mb-8">
        <h2 className="text-2xl font-bold mb-2">Dashboard</h2>
        <p className="text-gray-400">
          Recent policy decisions and risk assessments
        </p>
      </div>

      {/* Stats cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        {[
          {
            label: "Total Decisions",
            value: logs.length,
            color: "text-blue-400",
          },
          {
            label: "Allowed",
            value: logs.filter((l) => l.decision === "ALLOW").length,
            color: "text-green-400",
          },
          {
            label: "Challenged",
            value: logs.filter(
              (l) =>
                l.decision === "REQUIRE_SECOND_SIGNATURE" ||
                l.decision === "REQUIRE_DELAY"
            ).length,
            color: "text-yellow-400",
          },
          {
            label: "Denied",
            value: logs.filter((l) => l.decision === "DENY").length,
            color: "text-red-400",
          },
        ].map((stat) => (
          <div
            key={stat.label}
            className="bg-gray-900 border border-gray-800 rounded-lg p-4"
          >
            <p className="text-sm text-gray-400">{stat.label}</p>
            <p className={`text-3xl font-bold ${stat.color}`}>{stat.value}</p>
          </div>
        ))}
      </div>

      {/* Audit log table */}
      <div className="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-800">
          <h3 className="font-semibold">Recent Audit Logs</h3>
        </div>
        {loading ? (
          <div className="p-8 text-center text-gray-500">Loading...</div>
        ) : logs.length === 0 ? (
          <div className="p-8 text-center text-gray-500">
            No audit logs yet. Send a transaction to see decisions here.
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-400 text-left border-b border-gray-800">
                <th className="px-4 py-2">Time</th>
                <th className="px-4 py-2">Type</th>
                <th className="px-4 py-2">Target</th>
                <th className="px-4 py-2">Value</th>
                <th className="px-4 py-2">Risk</th>
                <th className="px-4 py-2">Decision</th>
                <th className="px-4 py-2">Reasons</th>
              </tr>
            </thead>
            <tbody>
              {logs.map((log) => (
                <tr
                  key={log.id}
                  className="border-b border-gray-800/50 hover:bg-gray-800/30"
                >
                  <td className="px-4 py-2 text-gray-400">
                    {log.timestamp
                      ? new Date(log.timestamp).toLocaleString()
                      : "—"}
                  </td>
                  <td className="px-4 py-2 font-mono text-xs">{log.tx_type}</td>
                  <td className="px-4 py-2 font-mono text-xs">
                    {log.target.slice(0, 6)}...{log.target.slice(-4)}
                  </td>
                  <td className="px-4 py-2">{log.value}</td>
                  <td className="px-4 py-2">
                    <RiskBar score={log.risk_score} />
                  </td>
                  <td className="px-4 py-2">
                    <span
                      className={`px-2 py-0.5 rounded text-xs font-medium ${DECISION_COLORS[log.decision] || ""}`}
                    >
                      {log.decision}
                    </span>
                  </td>
                  <td className="px-4 py-2">
                    <div className="flex flex-wrap gap-1">
                      {log.reason_codes.map((code) => (
                        <span
                          key={code}
                          className="px-1.5 py-0.5 bg-gray-800 text-gray-400 rounded text-xs"
                        >
                          {code}
                        </span>
                      ))}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
