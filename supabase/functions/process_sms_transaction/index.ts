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

type AtomicSmsResult = {
  success?: boolean;
  status:
    | "created"
    | "processed"
    | "duplicate"
    | "skipped"
    | "error"
    | "failed_parse"
    | "failed_wallet"
    | "failed_transaction";
  transaction_id?: string | null;
  wallet_id?: string | null;
  wallet_name?: string | null;
  amount?: number | null;
  type?: "Income" | "Expense" | "Transfer" | null;
  description?: string | null;
  balance_after?: number | null;
  is_internal_transfer?: boolean;
  message?: string;
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

function stableSmsHash(senderId: string, smsBody: string) {
  const normalizedSender = senderId.trim().replace(/\s+/g, "").toLowerCase();
  const normalizedBody = smsBody.toLowerCase().replace(/\s+/g, " ").trim();
  return `${normalizedSender}_${localStableHash(normalizedBody)}`;
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
  if (/transferred by cliq from account/i.test(text)) return "Expense";
  if (/transferred by cliq to account/i.test(text)) return "Income";

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

    const cleaned = value.replace(/[.,]+$/g, "");
    return cleaned.length > 42
      ? `${cleaned.slice(0, 39).trim()}...`
      : cleaned;
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

function normalizeAtomicResult(value: unknown): AtomicSmsResult {
  if (value && typeof value === "object") {
    return value as AtomicSmsResult;
  }

  return {
    status: "failed_transaction",
    transaction_id: null,
    wallet_id: null,
    message: "Invalid RPC response.",
  };
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

    const payload = await req.json();
    const providedSmsHash = String(payload.sms_hash ?? "").trim();
    const senderId = String(payload.sender_id ?? "").trim();
    const smsBody = String(payload.sms_body ?? "");
    const walletId = payload.wallet_id ? String(payload.wallet_id) : null;
    const receivedAt = payload.received_at
      ? new Date(payload.received_at).toISOString()
      : new Date().toISOString();

    if (!senderId || !smsBody.trim()) {
      return jsonResponse({ error: "invalid_sms_input" }, 400);
    }

    const smsHash = providedSmsHash || stableSmsHash(senderId, smsBody);
    const parsed = parseSms(smsBody, receivedAt);

    const { data, error } = await supabase.rpc("process_sms_transaction_atomic", {
      p_sms_hash: smsHash,
      p_sender_id: senderId,
      p_sms_body: smsBody,
      p_received_at: receivedAt,
      p_wallet_id: walletId,
      p_amount: parsed?.amount ?? null,
      p_type: parsed?.type ?? null,
      p_available_balance: parsed?.balanceAfter ?? null,
      p_transaction_date: parsed?.transactionDate ?? receivedAt,
      p_sms_kind: parsed?.smsKind ?? null,
      p_merchant_name: parsed?.merchantName ?? null,
      p_counterparty: parsed?.counterparty ?? null,
      p_is_cliq: parsed?.isCliq ?? false,
    });

    if (error) {
      console.error("process_sms_transaction RPC failed", {
        message: error.message,
        code: error.code,
        details: error.details,
        hint: error.hint,
      });
      return jsonResponse(
        {
          success: false,
          status: "error",
          transaction_id: null,
          wallet_id: walletId,
          message: error.message ?? "Atomic SMS processing failed.",
          code: error.code ?? null,
          details: error.details ?? null,
          hint: error.hint ?? null,
        },
        500,
      );
    }

    return jsonResponse(normalizeAtomicResult(data));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("process_sms_transaction failed", message);
    return jsonResponse(
      {
        success: false,
        status: "error",
        transaction_id: null,
        wallet_id: null,
        message: "SMS processing failed.",
        details: message,
      },
      500,
    );
  }
});
