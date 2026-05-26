import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

function formatCategoryRows(rows: Array<Record<string, unknown>>, total: number) {
  if (!rows.length) return "- No category data.";

  return rows.slice(0, 8).map((row) => {
    const categoryTotal = amount(row.total_amount);
    const percentage = total > 0 ? (categoryTotal / total) * 100 : 0;
    return `- ${row.category_name ?? "Uncategorized"}: ${categoryTotal.toFixed(2)} JOD (${percentage.toFixed(1)}%)`;
  }).join("\n");
}

async function buildFinancialContext(
  supabase: ReturnType<typeof createClient>,
  userId: string,
) {
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);

  const [profile, wallets, transactions, debts] = await Promise.all([
    supabase.from("users").select("full_name, total_net_worth").eq("id", userId).maybeSingle(),
    supabase.from("wallets").select("name, balance, currency, type").eq("user_id", userId),
    supabase
      .from("transactions")
      .select("amount, type, description, date, is_internal_transfer, wallets(name), categories(name)")
      .eq("user_id", userId)
      .eq("is_hidden", false)
      .order("date", { ascending: false })
      .limit(20),
    supabase.from("debts").select("person_name, amount, type, due_date, note").eq("user_id", userId).eq("status", "active"),
  ]);

  const txRows = transactions.data ?? [];
  const monthlyRows = txRows.filter((tx) => {
    const date = new Date(String(tx.date ?? ""));
    return date >= monthStart && date <= monthEnd && tx.is_internal_transfer !== true;
  });

  const totalIncome = monthlyRows
    .filter((tx) => tx.type === "Income")
    .reduce((sum, tx) => sum + Math.abs(amount(tx.amount)), 0);
  const totalExpenses = monthlyRows
    .filter((tx) => tx.type === "Expense")
    .reduce((sum, tx) => sum + Math.abs(amount(tx.amount)), 0);

  const categoryBuckets = new Map<string, Record<string, unknown>>();
  for (const tx of monthlyRows) {
    if (tx.type !== "Income" && tx.type !== "Expense") continue;

    const nestedCategory = tx.categories as Record<string, unknown> | null;
    const key = `${tx.type}:${nestedCategory?.name ?? "Uncategorized"}`;
    const current = categoryBuckets.get(key) ?? {
      type: tx.type,
      category_name: nestedCategory?.name ?? "Uncategorized",
      total_amount: 0,
    };
    current.total_amount = amount(current.total_amount) + Math.abs(amount(tx.amount));
    categoryBuckets.set(key, current);
  }

  const incomeCategories = Array.from(categoryBuckets.values())
    .filter((row) => row.type === "Income")
    .sort((a, b) => amount(b.total_amount) - amount(a.total_amount));
  const expenseCategories = Array.from(categoryBuckets.values())
    .filter((row) => row.type === "Expense")
    .sort((a, b) => amount(b.total_amount) - amount(a.total_amount));

  const walletText = (wallets.data ?? []).length
    ? (wallets.data ?? []).map((wallet) =>
      `- ${wallet.name}: ${amount(wallet.balance).toFixed(2)} ${wallet.currency ?? "JOD"}, type: ${wallet.type ?? "Account"}`
    ).join("\n")
    : "- No wallets/accounts found.";

  const debtRows = debts.data ?? [];
  const debtorTotal = debtRows
    .filter((debt) => debt.type === "debtor")
    .reduce((sum, debt) => sum + amount(debt.amount), 0);
  const creditorTotal = debtRows
    .filter((debt) => debt.type === "creditor")
    .reduce((sum, debt) => sum + amount(debt.amount), 0);
  const debtList = debtRows.length
    ? debtRows.slice(0, 10).map((debt) =>
      `- ${debt.person_name}: ${debt.type === "debtor" ? "owes the user" : "user owes this person"}, ${amount(debt.amount).toFixed(2)} JOD, due: ${debt.due_date ?? "no due date"}`
    ).join("\n")
    : "- No active debts.";

  const recentTransactions = txRows.length
    ? txRows.slice(0, 10).map((tx) => {
      const wallet = tx.wallets as Record<string, unknown> | null;
      const category = tx.categories as Record<string, unknown> | null;
      const type = tx.is_internal_transfer === true
        ? `Internal Transfer (${tx.type})`
        : tx.type;
      return `- ${type} ${amount(tx.amount).toFixed(2)} JOD, wallet: ${wallet?.name ?? "Unknown"}, category: ${category?.name ?? "Uncategorized"}, date: ${tx.date}, description: ${tx.description ?? ""}`;
    }).join("\n")
    : "- No recent visible transactions found.";

  return `
User name: ${profile.data?.full_name ?? "Financial Mind User"}
Current wallet/account net worth: ${amount(profile.data?.total_net_worth).toFixed(2)} JOD
Current month period: ${monthStart.toISOString().slice(0, 10)} to ${monthEnd.toISOString().slice(0, 10)}
Monthly income, excluding internal transfers: ${totalIncome.toFixed(2)} JOD
Monthly expenses, excluding internal transfers: ${totalExpenses.toFixed(2)} JOD

Wallets:
${walletText}

Income by category this month:
${formatCategoryRows(incomeCategories, totalIncome)}

Expenses by category this month:
${formatCategoryRows(expenseCategories, totalExpenses)}

Debt tracking:
- Money owed to user: ${debtorTotal.toFixed(2)} JOD
- Money user owes: ${creditorTotal.toFixed(2)} JOD
- Net debt position: ${(debtorTotal - creditorTotal).toFixed(2)} JOD
- Debts are separate from wallet/account balances and are not transactions.

Active debt list:
${debtList}

Recent transactions:
${recentTransactions}
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
    const text = await response.text();
    throw new Error(`AI provider failed: ${response.status} ${text}`);
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
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";

    const authedClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: authData, error: authError } = await authedClient.auth.getUser();
    if (authError || !authData.user) {
      return jsonResponse({ error: "not_authenticated" }, 401);
    }

    const payload = await req.json();
    const message = String(payload.message ?? "").trim();
    if (!message) return jsonResponse({ error: "empty_message" }, 400);

    const financialContext = await buildFinancialContext(adminClient, authData.user.id);
    const prompt = `
You are FinMind AI, a personal finance assistant inside a finance tracking app.

Respond in the same language as the user. If the user writes Arabic, answer in clear Arabic.

Use only the user's real financial data below:
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
    console.error("financial_ai_assistant failed", error);
    return jsonResponse(
      {
        error: "ai_failed",
        response: "AI connection is temporarily unstable. Please try again shortly.",
      },
      500,
    );
  }
});
