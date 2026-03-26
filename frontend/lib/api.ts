const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";

export interface TransactionRequest {
  wallet: string;
  chain_id: number;
  target: string;
  value: string;
  data: string;
}

export interface SimulationResult {
  success: boolean;
  gas_used: number;
  eth_balance_delta: string;
  token_transfers: Array<{
    token: string;
    from: string;
    to: string;
    amount: string;
  }>;
  token_approvals: Array<{
    token: string;
    spender: string;
    allowance: string;
    unlimited: boolean;
  }>;
  has_unlimited_approval: boolean;
  assets_drained_pct: number;
  error: string | null;
}

export interface PolicyDecision {
  decision: "ALLOW" | "REQUIRE_SECOND_SIGNATURE" | "REQUIRE_DELAY" | "DENY";
  risk_score: number;
  reason_codes: string[];
  tx_type: string;
  usd_value: number;
  simulation: SimulationResult | null;
}

export interface AttestationResponse {
  op_hash: string;
  signature: string;
  decision: string;
  expiry: number;
  signer: string;
}

export interface AuditLog {
  id: number;
  timestamp: string;
  wallet: string;
  target: string;
  value: string;
  tx_type: string;
  risk_score: number;
  decision: string;
  reason_codes: string[];
}

export async function simulate(tx: TransactionRequest): Promise<SimulationResult> {
  const res = await fetch(`${API_URL}/simulate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(tx),
  });
  return res.json();
}

export async function decide(tx: TransactionRequest): Promise<PolicyDecision> {
  const res = await fetch(`${API_URL}/decide`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(tx),
  });
  return res.json();
}

export async function attest(params: {
  wallet: string;
  chain_id: number;
  target: string;
  value: string;
  data: string;
  nonce: number;
  decision: string;
  expiry: number;
}): Promise<AttestationResponse> {
  const res = await fetch(`${API_URL}/attest`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(params),
  });
  return res.json();
}

export async function getAuditLogs(limit = 50): Promise<AuditLog[]> {
  const res = await fetch(`${API_URL}/audit-logs?limit=${limit}`);
  return res.json();
}

export async function addKnownRecipient(address: string) {
  return fetch(`${API_URL}/admin/known-recipients?address=${address}`, {
    method: "POST",
  });
}

export async function getKnownRecipients(): Promise<{ recipients: string[] }> {
  const res = await fetch(`${API_URL}/admin/known-recipients`);
  return res.json();
}

export async function addToBlocklist(address: string) {
  return fetch(`${API_URL}/admin/blocklist?address=${address}`, {
    method: "POST",
  });
}

export async function getBlocklist(): Promise<{ contracts: string[] }> {
  const res = await fetch(`${API_URL}/admin/blocklist`);
  return res.json();
}

export async function addToAllowlist(address: string) {
  return fetch(`${API_URL}/admin/allowlist?address=${address}`, {
    method: "POST",
  });
}

export async function getAllowlist(): Promise<{ contracts: string[] }> {
  const res = await fetch(`${API_URL}/admin/allowlist`);
  return res.json();
}
