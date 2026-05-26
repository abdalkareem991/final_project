import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ParsedSms = {
  amount: number;
  type: "Income" | "Expense";
  balanceAfter: number | null;
  transactionDate: string;
  smsKind: string;
  merchantName: string | null;
  counterparty: string | null;
  isCliq: boolean;
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizeText(value: string) {
  return value
    .toLowerCase()
    .replace(/\s+/g, " ")
    .replace(/[إأآ]/g, "ا")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .trim();
}

function localStableHash(body: string) {
  let hash = 0;
  for (let i = 0; i < body.length; i++) {
    hash = 0x1fffffff & (hash + body.charCodeAt(i));
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash = hash ^ (hash >> 6);
  }

  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash = hash ^ (hash >> 11);
  hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  return hash;
}

function stableSmsHash(
  senderId: string,
  smsBody: string,
  receivedAt: string,
) {
  const smsDate = Number.isFinite(Date.parse(receivedAt))
    ? Date.parse(receivedAt)
    : 0;
  const normalizedBody = smsBody.toLowerCase().replace(/\s+/g, " ").trim();
  return `${senderId.trim().toLowerCase()}_${smsDate}_${localStableHash(normalizedBody)}`;
}

function firstNumber(text: string, patterns: RegExp[]) {
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    if (!match?.[1]) continue;

    const parsed = Number.parseFloat(match[1].replace(/,/g, ""));
    if (Number.isFinite(parsed) && parsed > 0) return parsed;
  }

  return null;
}

function extractAmount(text: string) {
  const fils = firstNumber(text, [
    /(?:amount|مبلغ|بقيمة|بقيمه|بمبلغ)\s*([0-9,]+(?:\.[0-9]+)?)\s*(?:fils|فلس)/i,
    /([0-9,]+(?:\.[0-9]+)?)\s*(?:fils|فلس)/i,
  ]);
  if (fils != null) return fils / 1000;

  return firstNumber(text, [
    /jod\s*([0-9,]+(?:\.[0-9]+)?)/i,
    /([0-9,]+(?:\.[0-9]+)?)\s*jod/i,
    /(?:amount|مبلغ|بقيمة|بقيمه|بمبلغ)\s*([0-9,]+(?:\.[0-9]+)?)\s*(?:jd|jod|دينار)/i,
    /(?:credited|debited|withdrawn|transferred|payment|purchase|paid|deposit|deposited).*?([0-9,]+(?:\.[0-9]+)?)/i,
  ]);
}

function extractBalance(text: string) {
  return firstNumber(text, [
    /available balance\s*(?:jod)?\s*([0-9,]+(?:\.[0-9]+)?)/i,
    /balance\s*(?:is|:)?\s*(?:jod)?\s*([0-9,]+(?:\.[0-9]+)?)/i,
    /الرصيد\s*(?:الحالي|المتاح|المتوفر)?\s*([0-9,]+(?:\.[0-9]+)?)/i,
  ]);
}

function detectType(text: string): "Income" | "Expense" | null {
  if (
    /(credited|credit|deposit|deposited|received|salary|refund|cashback|reversal|reversed|ايداع|وارد|استلام|استقبال)/i
      .test(text)
  ) {
    return "Income";
  }

  if (
    /(debited|debit|withdrawn|withdrawal|paid|payment|purchase|pos|visa|card|bill|biller|efawateercom|atm|fee|fees|خصم|سحب|شراء|دفع|فاتوره|فاتورة|رسوم|عموله|عمولة)/i
      .test(text)
  ) {
    return "Expense";
  }

  return null;
}

function shouldIgnore(text: string) {
  return /(otp|one time password|verification|auth code|do not share|رمز|تحقق|توثيق|تفعيل|مشاركته)/i
    .test(text);
}

function detectSmsKind(text: string) {
  if (/cliq|كليك/i.test(text)) return "CliQ Transfer";
  if (/atm/i.test(text) && /deposit|deposited|ايداع/i.test(text)) {
    return "ATM Deposit";
  }
  if (/atm/i.test(text) && /withdraw|withdrawn|سحب/i.test(text)) {
    return "ATM Withdrawal";
  }
  if (/bill|biller|efawateercom|فاتوره|فاتورة/i.test(text)) {
    return "Bill Payment";
  }
  if (/fee|fees|رسوم|عموله|عمولة/i.test(text)) return "Bank Fee";
  if (/purchase|pos|card|visa|شراء/i.test(text)) return "Card Payment";
  return "Bank Transaction";
}

function extractParty(text: string) {
  const patterns = [
    /\sfrom\s+([a-z0-9._-]+)(?:\.| available| balance|$)/i,
    /\sto\s+([a-z0-9._-]+)(?:\.| available| balance|$)/i,
    /at\s+([a-z0-9\u0600-\u06ff\s._-]+?)(?:\.|,| on | available| balance|$)/i,
    /لدى\s+([a-z0-9\u0600-\u06ff\s._-]+?)(?:\.|،| بتاريخ| الرصيد|$)/i,
  ];

  for (const pattern of patterns) {
    const match = pattern.exec(text);
    const value = match?.[1]?.trim();
    if (!value) continue;

    const lower = value.toLowerCase();
    if (
      lower.includes("account") ||
      lower.includes("balance") ||
      lower.includes("authorization")
    ) {
      continue;
    }

    return value.length > 42 ? `${value.slice(0, 39).trim()}...` : value;
  }

  return null;
}

function parseSms(smsBody: string, receivedAt: string): ParsedSms | null {
  const text = normalizeText(smsBody);
  if (!text || shouldIgnore(text)) return null;

  const type = detectType(text);
  if (!type) return null;

  const amount = extractAmount(text);
  if (amount == null || amount <= 0) return null;

  const party = extractParty(text);

  return {
    amount,
    type,
    balanceAfter: extractBalance(text),
    transactionDate: new Date(receivedAt).toISOString(),
    smsKind: detectSmsKind(text),
    merchantName: party,
    counterparty: party,
    isCliq: /cliq|كليك/i.test(text),
  };
}

function buildDescription(
  parsed: ParsedSms,
  senderId: string,
) {
  if (parsed.isCliq) {
    const party = parsed.counterparty ?? parsed.merchantName;
    if (party) return parsed.type === "Income" ? `CliQ from ${party}` : `CliQ to ${party}`;
    return parsed.type === "Income" ? "CliQ Transfer In" : "CliQ Transfer Out";
  }

  if (parsed.merchantName) return `${parsed.smsKind} - ${parsed.merchantName}`;
  return `${parsed.smsKind} - ${senderId}`;
}

async function getOrCreateCategory(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  smsKind: string,
  merchantName: string | null,
  type: "Income" | "Expense",
) {
  const text = `${smsKind} ${merchantName ?? ""}`.toLowerCase();
  const category =
    type === "Income"
      ? { name: "Income", type: "Income", icon: "trending_up", color: "#22C55E" }
      : text.includes("cliq") || text.includes("transfer")
      ? { name: "Transfer", type: "Transfer", icon: "swap_horiz", color: "#3B82F6" }
      : text.includes("bill") || text.includes("orange") || text.includes("zain")
      ? { name: "Bills", type: "Expense", icon: "receipt", color: "#F59E0B" }
      : text.includes("card") || text.includes("visa") || text.includes("pos")
      ? { name: "Card Payment", type: "Expense", icon: "credit_card", color: "#8B5CF6" }
      : { name: "General", type: "Expense", icon: "category", color: "#94A3B8" };

  const existing = await supabase
    .from("categories")
    .select("id")
    .eq("user_id", userId)
    .eq("name", category.name)
    .maybeSingle();

  if (existing.data?.id) return existing.data.id;

  const inserted = await supabase
    .from("categories")
    .insert({ user_id: userId, ...category })
    .select("id")
    .single();

  if (inserted.error) throw inserted.error;
  return inserted.data.id;
}

async function markInternalTransferIfMatched(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  newTransactionId: string,
  walletId: string,
  amount: number,
  type: "Income" | "Expense",
  transactionDate: string,
) {
  const oppositeType = type === "Income" ? "Expense" : "Income";
  const date = new Date(transactionDate);
  const windowStart = new Date(date.getTime() - 10 * 60 * 1000).toISOString();
  const windowEnd = new Date(date.getTime() + 10 * 60 * 1000).toISOString();

  const match = await supabase
    .from("transactions")
    .select("id, wallet_id")
    .eq("user_id", userId)
    .eq("type", oppositeType)
    .eq("amount", amount)
    .eq("is_internal_transfer", false)
    .neq("wallet_id", walletId)
    .gte("date", windowStart)
    .lte("date", windowEnd)
    .order("date", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!match.data?.id) return false;

  const categoryId = await getOrCreateCategory(
    supabase,
    userId,
    "Transfer",
    null,
    "Expense",
  );
  const groupId = `transfer_${Date.now()}`;

  const currentWallet = await supabase
    .from("wallets")
    .select("name")
    .eq("id", walletId)
    .maybeSingle();
  const matchedWallet = await supabase
    .from("wallets")
    .select("name")
    .eq("id", match.data.wallet_id)
    .maybeSingle();

  const currentName = currentWallet.data?.name ?? "Current Account";
  const matchedName = matchedWallet.data?.name ?? "Matched Account";
  const description = type === "Income"
    ? `Transfer from ${matchedName} to ${currentName}`
    : `Transfer from ${currentName} to ${matchedName}`;

  const update = await supabase
    .from("transactions")
    .update({
      is_internal_transfer: true,
      transfer_group_id: groupId,
      category_id: categoryId,
      description,
    })
    .in("id", [newTransactionId, match.data.id]);

  if (update.error) throw update.error;
  return true;
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
    const userId = String(payload.user_id ?? "");
    const senderId = String(payload.sender_id ?? "").trim();
    const smsBody = String(payload.sms_body ?? "");
    const receivedAt = payload.received_at
      ? new Date(payload.received_at).toISOString()
      : new Date().toISOString();

    if (userId !== authData.user.id) return jsonResponse({ error: "forbidden" }, 403);
    if (!senderId || !smsBody.trim()) {
      return jsonResponse({ error: "invalid_sms_input" }, 400);
    }

    const smsHash = stableSmsHash(senderId, smsBody, receivedAt);

    const existingLog = await adminClient
      .from("sms_processing_logs")
      .select("status")
      .eq("user_id", userId)
      .eq("sms_hash", smsHash)
      .maybeSingle();

    if (existingLog.data?.status === "processed") {
      return jsonResponse({ status: "duplicate", sms_hash: smsHash, processed: false });
    }

    await adminClient.from("sms_processing_logs").upsert({
      user_id: userId,
      sms_hash: smsHash,
      sender_id: senderId,
      status: "pending",
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id,sms_hash" });

    const parsed = parseSms(smsBody, receivedAt);
    if (!parsed) {
      await adminClient.from("sms_processing_logs").upsert({
        user_id: userId,
        sms_hash: smsHash,
        sender_id: senderId,
        status: "parse_failed",
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id,sms_hash" });

      return jsonResponse({ status: "parse_failed", sms_hash: smsHash, processed: false });
    }

    const wallet = await adminClient
      .from("wallets")
      .select("id, name, balance")
      .eq("user_id", userId)
      .eq("sms_sender_id", senderId)
      .eq("account_mode", "AUTOMATED")
      .eq("is_active_monitoring", true)
      .maybeSingle();

    if (!wallet.data?.id) {
      await adminClient.from("sms_processing_logs").upsert({
        user_id: userId,
        sms_hash: smsHash,
        sender_id: senderId,
        status: "no_linked_wallet",
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id,sms_hash" });

      return jsonResponse({ status: "no_linked_wallet", sms_hash: smsHash, processed: false });
    }

    const existingTx = await adminClient
      .from("transactions")
      .select("id")
      .eq("user_id", userId)
      .eq("sms_hash", smsHash)
      .maybeSingle();

    if (existingTx.data?.id) {
      await adminClient.from("sms_processing_logs").upsert({
        user_id: userId,
        sms_hash: smsHash,
        sender_id: senderId,
        status: "processed",
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id,sms_hash" });

      return jsonResponse({ status: "duplicate", sms_hash: smsHash, processed: false });
    }

    const categoryId = await getOrCreateCategory(
      adminClient,
      userId,
      parsed.smsKind,
      parsed.merchantName,
      parsed.type,
    );
    const description = buildDescription(parsed, senderId);

    const inserted = await adminClient
      .from("transactions")
      .insert({
        user_id: userId,
        wallet_id: wallet.data.id,
        amount: parsed.amount,
        type: parsed.type,
        description,
        category_id: categoryId,
        sms_hash: smsHash,
        merchant_name: parsed.merchantName,
        sms_kind: parsed.smsKind,
        date: parsed.transactionDate,
      })
      .select("id")
      .single();

    if (inserted.error) throw inserted.error;

    const currentBalance = Number(wallet.data.balance ?? 0);
    let nextBalance = parsed.type === "Income"
      ? currentBalance + parsed.amount
      : currentBalance - parsed.amount;

    if (parsed.balanceAfter != null) {
      const newer = await adminClient
        .from("transactions")
        .select("id")
        .eq("wallet_id", wallet.data.id)
        .gt("date", parsed.transactionDate)
        .limit(1);

      if (!newer.data?.length) nextBalance = parsed.balanceAfter;
    }

    const walletUpdate = await adminClient
      .from("wallets")
      .update({ balance: nextBalance })
      .eq("id", wallet.data.id)
      .eq("user_id", userId);
    if (walletUpdate.error) throw walletUpdate.error;

    const isInternalTransfer = await markInternalTransferIfMatched(
      adminClient,
      userId,
      inserted.data.id,
      wallet.data.id,
      parsed.amount,
      parsed.type,
      parsed.transactionDate,
    );

    await adminClient.from("sms_processing_logs").upsert({
      user_id: userId,
      sms_hash: smsHash,
      sender_id: senderId,
      status: "processed",
      details: {
        transaction_id: inserted.data.id,
        wallet_id: wallet.data.id,
        type: parsed.type,
        amount: parsed.amount,
        is_internal_transfer: isInternalTransfer,
      },
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id,sms_hash" });

    return jsonResponse({
      status: "processed",
      processed: true,
      sms_hash: smsHash,
      transaction_id: inserted.data.id,
      wallet_name: wallet.data.name,
      type: parsed.type,
      amount: parsed.amount,
      description,
      balance_after: nextBalance,
      is_internal_transfer: isInternalTransfer,
    });
  } catch (error) {
    console.error("process_sms_transaction failed", error);
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse(
      { error: "processing_failed", message },
      500,
    );
  }
});
