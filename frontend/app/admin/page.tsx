"use client";

import { useEffect, useState } from "react";
import {
  addKnownRecipient,
  addToAllowlist,
  addToBlocklist,
  getAllowlist,
  getBlocklist,
  getKnownRecipients,
} from "@/lib/api";

function AddressList({
  title,
  description,
  addresses,
  onAdd,
  loading,
}: {
  title: string;
  description: string;
  addresses: string[];
  onAdd: (addr: string) => void;
  loading: boolean;
}) {
  const [input, setInput] = useState("");

  const handleAdd = () => {
    if (input.trim()) {
      onAdd(input.trim());
      setInput("");
    }
  };

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-5">
      <h3 className="font-semibold mb-1">{title}</h3>
      <p className="text-sm text-gray-400 mb-4">{description}</p>

      <div className="flex gap-2 mb-4">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="0x..."
          className="flex-1 bg-gray-800 border border-gray-700 rounded px-3 py-1.5 text-sm font-mono focus:outline-none focus:border-blue-500"
          onKeyDown={(e) => e.key === "Enter" && handleAdd()}
        />
        <button
          onClick={handleAdd}
          disabled={loading}
          className="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 text-white px-4 py-1.5 rounded text-sm transition"
        >
          Add
        </button>
      </div>

      {addresses.length === 0 ? (
        <p className="text-sm text-gray-500">No addresses configured</p>
      ) : (
        <ul className="space-y-1">
          {addresses.map((addr) => (
            <li
              key={addr}
              className="flex items-center justify-between bg-gray-800/50 rounded px-3 py-1.5"
            >
              <span className="font-mono text-sm">{addr}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export default function AdminPage() {
  const [recipients, setRecipients] = useState<string[]>([]);
  const [allowlist, setAllowlist] = useState<string[]>([]);
  const [blocklist, setBlocklist] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);

  const refresh = async () => {
    try {
      const [r, a, b] = await Promise.all([
        getKnownRecipients(),
        getAllowlist(),
        getBlocklist(),
      ]);
      setRecipients(r.recipients);
      setAllowlist(a.contracts);
      setBlocklist(b.contracts);
    } catch {
      // API might not be running
    }
    setLoading(false);
  };

  useEffect(() => {
    refresh();
  }, []);

  const handleAddRecipient = async (addr: string) => {
    await addKnownRecipient(addr);
    refresh();
  };

  const handleAddAllowlist = async (addr: string) => {
    await addToAllowlist(addr);
    refresh();
  };

  const handleAddBlocklist = async (addr: string) => {
    await addToBlocklist(addr);
    refresh();
  };

  return (
    <div>
      <h2 className="text-2xl font-bold mb-2">Policy Admin</h2>
      <p className="text-gray-400 mb-6">
        Configure risk engine parameters and manage address lists
      </p>

      {/* Policy thresholds card */}
      <div className="bg-gray-900 border border-gray-800 rounded-lg p-5 mb-6">
        <h3 className="font-semibold mb-4">Policy Thresholds</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
          <div className="bg-green-900/10 border border-green-900/30 rounded p-3">
            <p className="text-green-400 font-medium">ALLOW</p>
            <p className="text-gray-400 mt-1">
              Transactions under <span className="text-white">$100</span>
            </p>
          </div>
          <div className="bg-yellow-900/10 border border-yellow-900/30 rounded p-3">
            <p className="text-yellow-400 font-medium">REQUIRE GUARDIAN</p>
            <p className="text-gray-400 mt-1">
              Transactions <span className="text-white">$100 - $1,000</span>
            </p>
          </div>
          <div className="bg-orange-900/10 border border-orange-900/30 rounded p-3">
            <p className="text-orange-400 font-medium">REQUIRE DELAY</p>
            <p className="text-gray-400 mt-1">
              Transactions over <span className="text-white">$1,000</span>
            </p>
          </div>
        </div>
        <div className="mt-3">
          <div className="bg-red-900/10 border border-red-900/30 rounded p-3 text-sm">
            <p className="text-red-400 font-medium">DENY</p>
            <p className="text-gray-400 mt-1">
              Blocked contracts, unlimited approvals to unknown contracts,
              asset-draining transactions
            </p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <AddressList
          title="Known Recipients"
          description="Trusted addresses that reduce risk scoring"
          addresses={recipients}
          onAdd={handleAddRecipient}
          loading={loading}
        />
        <AddressList
          title="Allowlisted Contracts"
          description="Verified contracts that bypass unknown-contract risk"
          addresses={allowlist}
          onAdd={handleAddAllowlist}
          loading={loading}
        />
        <AddressList
          title="Blocked Contracts"
          description="Contracts that always result in DENY"
          addresses={blocklist}
          onAdd={handleAddBlocklist}
          loading={loading}
        />
      </div>
    </div>
  );
}
