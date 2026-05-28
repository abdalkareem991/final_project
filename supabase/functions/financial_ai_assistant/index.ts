import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const rateLimitWindowMs = 60_000;
const rateLimitMaxRequests = 10;
// Best-effort per-instance throttle. For multi-instance production deployments,
// back this with a database table or Redis-compatible store so limits survive
// cold starts and parallel Edge Function instances.
const requestLogByUser = new Map<string, number[]>();

type JsonMap = Record<string, unknown>;

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function amount(value: unknown) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function asMap(value: unknown): JsonMap {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonMap
    : {};
}

function asArray(value: unknown): JsonMap[] {
  return Array.isArray(value)
    ? value.filter((item): item is JsonMap => item && typeof item === "object")
    : [];
}

function checkRateLimit(userId: string) {
  const now = Date.now();
  const active = (requestLogByUser.get(userId) ?? []).filter(
    (timestamp) => now - timestamp < rateLimitWindowMs,
  );

  if (active.length >= rateLimitMaxRequests) {
    requestLogByUser.set(userId, active);
    return false;
  }

  active.push(now);
  requestLogByUser.set(userId, active);
  return true;
}

function formatCategoryRows(rows: JsonMap[]) {
  if (!rows.length) return "- No category data.";

  return rows.slice(0, 8).map((row) => {
    const total = amount(row.total_amount);
    const percentage = amount(row.percentage);
    return `- ${row.category_name ?? "Uncategorized"}: ${total.toFixed(2)} JOD (${percentage.toFixed(1)}%)`;
  }).join("\n");
}

function formatRecentTransactions(rows: JsonMap[]) {
  if (!rows.length) return "- No recent visible transactions found.";

  return rows.slice(0, 8).map((tx) => {
    const type = tx.is_internal_transfer === true
      ? `Internal Transfer (${tx.type ?? "Transaction"})`
      : tx.type ?? "Transaction";
    return `- ${type} ${amount(tx.amount).toFixed(2)} JOD, wallet: ${tx.wallet_name ?? "Unknown"}, category: ${tx.category_name ?? "Uncategorized"}, date: ${tx.date ?? "unknown"}, description: ${tx.description ?? ""}`;
  }).join("\n");
}

async function buildFinancialContext(
  supabase: ReturnType<typeof createClient>,
  userId: string,
) {
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);

  const [dashboard, analytics, profile, wallets] = await Promise.all([
    supabase.rpc("get_dashboard_summary", {
      p_recent_limit: 8,
      p_include_hidden: false,
    }),
    supabase.rpc("get_monthly_analytics", {
      p_start_date: monthStart.toISOString(),
      p_end_date: monthEnd.toISOString(),
      p_wallet_id: null,
    }),
    supabase.from("users")
      .select("full_name, total_net_worth")
      .eq("id", userId)
      .maybeSingle(),
    supabase.from("wallets").select("name, balance, currency, type").limit(20),
  ]);

  if (dashboard.error) {
    console.error("dashboard summary RPC failed", {
      message: dashboard.error.message,
      code: dashboard.error.code,
      details: dashboard.error.details,
      hint: dashboard.error.hint,
    });
    throw dashboard.error;
  }
  if (analytics.error) {
    console.error("monthly analytics RPC failed", {
      message: analytics.error.message,
      code: analytics.error.code,
      details: analytics.error.details,
      hint: analytics.error.hint,
    });
    throw analytics.error;
  }

  const dashboardData = asMap(dashboard.data);
  const analyticsData = asMap(analytics.data);
  const summary = asMap(analyticsData.summary);
  const debts = asMap(dashboardData.debts_summary);

  const walletRows = Array.isArray(wallets.data) ? wallets.data : [];
  const walletText = walletRows.length
    ? walletRows.map((wallet) =>
      `- ${wallet.name}: ${amount(wallet.balance).toFixed(2)} ${wallet.currency ?? "JOD"}, type: ${wallet.type ?? "Account"}`
    ).join("\n")
    : "- No wallets/accounts found.";

  return `
User name: ${profile.data?.full_name ?? "FinMind User"}
Current wallet/account net worth: ${amount(dashboardData.total_balance).toFixed(2)} JOD
Profile net worth field: ${amount(profile.data?.total_net_worth).toFixed(2)} JOD
Current month period: ${monthStart.toISOString().slice(0, 10)} to ${monthEnd.toISOString().slice(0, 10)}
Monthly income, excluding internal transfers: ${amount(summary.total_income).toFixed(2)} JOD
Monthly expenses, excluding internal transfers: ${amount(summary.total_expenses).toFixed(2)} JOD

Wallets:
${walletText}

Income by category this month:
${formatCategoryRows(asArray(analyticsData.income_categories))}

Expenses by category this month:
${formatCategoryRows(asArray(analyticsData.expense_categories))}

Debt summary:
- Money owed to user: ${amount(debts.total_debtor_amount).toFixed(2)} JOD
- Money user owes: ${amount(debts.total_creditor_amount).toFixed(2)} JOD
- Net debt position: ${amount(debts.net_debt).toFixed(2)} JOD
- Debts are separate from wallet/account balances and are not transactions.

Recent visible transactions:
${formatRecentTransactions(asArray(dashboardData.recent_transactions))}
`;
}

async function callGemini(prompt: string) {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY is not configured");

  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.4,
          maxOutputTokens: 900,
        },
      }),
    },
  );

  if (!response.ok) {
    throw new Error(`AI provider failed: ${response.status}`);
  }

  const data = await response.json();
  return data?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part.text ?? "")
    .join("")
    .trim() || "I could not generate a response right now.";
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const authHeader = req.headers.get("Authorization") ?? "";

    if (!supabaseUrl || !anonKey) {
      return jsonResponse({ error: "server_not_configured" }, 500);
    }

    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return jsonResponse({ error: "missing_authorization" }, 401);
    }

    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) {
      return jsonResponse({ error: "not_authenticated" }, 401);
    }

    if (!checkRateLimit(authData.user.id)) {
      return jsonResponse(
        {
          error: "rate_limited",
          response: "Too many AI requests. Please wait a moment and try again.",
        },
        429,
      );
    }

    const payload = await req.json();
    const message = String(payload.message ?? "").trim();
    if (!message) return jsonResponse({ error: "empty_message" }, 400);

    const financialContext = await buildFinancialContext(
      supabase,
      authData.user.id,
    );
    const prompt = `
You are FinMind AI, a personal finance assistant inside a finance tracking app.

Respond in the same language as the user. If the user writes Arabic, answer in clear Arabic.

Use only the user's summarized financial data below:
${financialContext}

User question:
${message}

Core rules:
- Do not invent numbers, accounts, debts, categories, or transactions.
- If a required number is missing, say it is not available.
- Treat wallet/account balances, transactions, analytics, and debts as separate concepts.
- Debts are not wallet balances and are not transactions.
- Do not add debts to net worth unless the user explicitly asks for a separate debt-adjusted view.
- Internal transfers are not real income or real spending.
- Income category percentages and expense category percentages are calculated separately.

Answer style:
- Be practical, short, and clear.
- Mention whether your answer is based on balances, income, expenses, debts, or recent transactions.
- Use exact numbers only when they appear in the context.
- For advice, give 2 to 4 actionable steps.
- If there is risk or uncertainty, mention it gently.
- Do not provide legal, tax, or investment guarantees.
`;

    const answer = await callGemini(prompt);
    return jsonResponse({ response: answer });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("financial_ai_assistant failed", message);
    return jsonResponse(
      {
        error: "ai_failed",
        response: "AI connection is temporarily unstable. Please try again shortly.",
      },
      500,
    );
  }
});
