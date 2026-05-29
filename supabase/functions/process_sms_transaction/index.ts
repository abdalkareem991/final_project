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
  categoryHint: string;
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

type PatternMatch = {
  amount: number;
  balance: number | null;
  merchant: string | null;
  counterparty: string | null;
};

const NUMBER_PATTERN = String.raw`[0-9][0-9,]*(?:\.[0-9]+)?`;

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
    .replace(/[ًٌٍَُِّْ]/g, "")
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

function amountRx(pattern: string, flags = "i") {
  return new RegExp(pattern.replaceAll("{{amount}}", NUMBER_PATTERN), flags);
}

function firstNumber(text: string, patterns: RegExp[], allowZero = false) {
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    const raw = match?.groups?.amount ?? match?.[1];
    if (!raw) continue;

    const parsed = Number.parseFloat(raw.replace(/,/g, ""));
    if (Number.isFinite(parsed) && (allowZero ? parsed >= 0 : parsed > 0)) {
      return parsed;
    }
  }

  return null;
}

function extractAmount(text: string) {
  const fils = firstNumber(text, [
    amountRx(String.raw`(?:amount|بمبلغ|بقيمة|بقيمه|مبلغ)\s*(?<amount>{{amount}})\s*(?:fils|فلس)`),
    amountRx(String.raw`(?<amount>{{amount}})\s*(?:fils|فلس)`),
  ]);
  if (fils != null) return fils / 1000;

  return firstNumber(text, [
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\s+has\s+been`),
    amountRx(String.raw`(?<amount>{{amount}})\s*jod\s+has\s+been`),
    amountRx(String.raw`(?:amount|of|for)\s+(?<amount>{{amount}})\s*jod`),
    amountRx(String.raw`(?:بمبلغ|بقيمة|بقيمه)\s*(?<amount>{{amount}})\s*(?:jod|دينار)`),
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\s*(?:credited|debited|withdrawn|transferred|payment|purchase|paid|deposit|deposited)`),
    amountRx(String.raw`(?<amount>{{amount}})\s*jod\b`),
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\b`),
    amountRx(String.raw`(?<amount>{{amount}})\s*دينار\b`),
  ]);
}

function extractBalance(text: string) {
  return firstNumber(
    text,
    [
      amountRx(String.raw`available\s+balance:?\s*(?:jod\s*)?(?<amount>{{amount}})\s*jod`),
      amountRx(String.raw`available\s+balance\s+jod\s*(?<amount>{{amount}})`),
      amountRx(String.raw`current\s+balance:?\s*(?:jod\s*)?(?<amount>{{amount}})\s*jod`),
      amountRx(String.raw`الرصيد\s+المتوفر\s*(?<amount>{{amount}})\s*jod`),
      amountRx(String.raw`رصيد\s+المحفظه?\s+المتاح\s+هو\s+(?<amount>{{amount}})\s*دينار(?:\s+اردني)?`),
      amountRx(String.raw`الرصيد\s*(?:الحالي|المتاح|المتوفر)?\s*(?<amount>{{amount}})\s*(?:jod|دينار)?`),
    ],
    true,
  );
}

function cleanParty(value: string | null | undefined) {
  const cleaned = value?.trim().replace(/\s+/g, " ").replace(/[.,]+$/g, "");
  return cleaned ? cleaned : null;
}

function prefixAtm(value: string | null | undefined) {
  const cleaned = cleanParty(value);
  if (!cleaned) return null;
  return cleaned.startsWith("atm ") ? cleaned : `atm ${cleaned}`;
}

function containsAny(text: string, needles: string[]) {
  return needles.some((needle) => text.includes(needle));
}

function categoryForBiller(biller: string | null) {
  const value = (biller ?? "").toLowerCase();
  if (containsAny(value, ["zain", "umniah", "orange mobile", "orange"])) {
    return "Bills - Telecom";
  }
  if (containsAny(value, ["jordan electricity", "electricity distribution co"])) {
    return "Bills - Electricity";
  }
  if (containsAny(value, ["water_miyahuna", "miyahuna"])) {
    return "Bills - Water";
  }
  if (value.includes("ministry of health")) return "Healthcare";
  if (value.includes("world islamic sciences and education university")) {
    return "Education";
  }
  if (value.includes("damamax")) return "Bills - Internet";
  if (value.includes("sadad logistics")) return "Services";
  if (containsAny(value, ["al tas heelat", "tasheelat"])) {
    return "Financing / Installments";
  }
  return "General Expense";
}

function categoryForMerchant(
  merchant: string | null,
  options: { isCardPayment?: boolean; isVoucher?: boolean } = {},
) {
  const value = (merchant ?? "").toLowerCase();
  if (options.isVoucher || value.includes("freefire")) {
    return "Gaming / Vouchers";
  }
  if (containsAny(value, ["zain", "umniah", "orange"])) {
    return "Bills - Telecom";
  }
  if (value.includes("talabat")) return "Food & Delivery";
  if (containsAny(value, ["paypal", "google"])) return "Online Services";
  return options.isCardPayment ? "Shopping" : "General Expense";
}

function shouldIgnore(text: string) {
  return (
    /(?:\botp\b|one time password|verification|verify|auth code|authorization code|please enter the following code|please do not share|do not share|do not share this otp)/i
      .test(text) ||
    /(?:رمز\s+التحقق|رمز\s+التاكيد\s+otp|رمز\s+التأكيد\s+otp|يرجى\s+عدم\s+مشاركته|لا\s+تشارك\s+هذا\s+الرمز|الرقم\s+السري\s+لعمليه?\s+التحويل|سوف\s+يتم\s+استخدام\s+هذا\s+الرمز|رمز\s+التحقق\s+لاستكمال\s+شراء\s+القسيمه)/
      .test(text) ||
    /(?:beware\s+of\s+sms|scam\s+messages|avoid\s+opening\s+any\s+links|sharing\s+your\s+banking\s+information)/i
      .test(text) ||
    /(?:digital\s+banking\s+services\s+will\s+be\s+suspended|system\s+updates)/i
      .test(text) ||
    /transaction\s+on\s+debit\s+card.*?has\s+been\s+declined/i.test(text)
  );
}

function patternMatch(text: string, pattern: RegExp): PatternMatch | null {
  const match = pattern.exec(text);
  const amountRaw = match?.groups?.amount;
  if (!amountRaw) return null;

  const amount = Number.parseFloat(amountRaw.replace(/,/g, ""));
  if (!Number.isFinite(amount) || amount <= 0) return null;

  const balanceRaw = match?.groups?.balance;
  const balance = balanceRaw
    ? Number.parseFloat(balanceRaw.replace(/,/g, ""))
    : null;

  return {
    amount,
    balance: balance != null && Number.isFinite(balance) ? balance : null,
    merchant: match?.groups?.merchant ?? null,
    counterparty: match?.groups?.counterparty ?? null,
  };
}

function parsedSms(params: {
  amount: number;
  type: "Income" | "Expense";
  receivedAt: string;
  balanceAfter?: number | null;
  smsKind: string;
  categoryHint: string;
  merchantName?: string | null;
  counterparty?: string | null;
  isCliq?: boolean;
}): ParsedSms {
  return {
    amount: params.amount,
    type: params.type,
    balanceAfter: params.balanceAfter ?? null,
    transactionDate: new Date(params.receivedAt).toISOString(),
    smsKind: params.smsKind,
    categoryHint: params.categoryHint,
    merchantName: params.merchantName ?? null,
    counterparty: params.counterparty ?? null,
    isCliq: params.isCliq ?? false,
  };
}

function isReflectMessage(text: string, sender: string) {
  return sender.includes("reflect") || text.includes("reflect") ||
    text.includes("ريفلكت");
}

function isOrangeMoneyMessage(text: string, sender: string) {
  return sender.includes("orange") || text.includes("orange money") ||
    text.includes("orange");
}

function matchReflect(text: string, receivedAt: string): ParsedSms | null {
  let match = patternMatch(
    text,
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+credited\s+to\s+your\s+reflect\s+account\b`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Income",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Bank Credit",
      categoryHint: "Bank Credit",
      merchantName: "reflect",
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`purchase\s+transaction\s+has\s+been\s+reversed\s+to\s+your\s+reflect\s+card\s+from\s+(?<merchant>.+?)\s+amount\s+(?<amount>{{amount}})\s*jod`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Income",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Refund/Reversal",
      categoryHint: "Refund",
      merchantName: cleanParty(match.merchant),
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\s+cliq\s+payment\s+from\s+your\s+reflect\s+account\b.*?as\s+a\s+reversal`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Income",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Refund/Reversal",
      categoryHint: "Refund",
      merchantName: "reflect",
      counterparty: "reflect account",
      isCliq: true,
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`تم\s+قيد\s+حواله?\s+بمبلغ\s+(?<amount>{{amount}})\s*jod\s+من\s+حسابك\s+عل[ىي]\s+ريفلكت`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "CliQ Transfer",
      categoryHint: "CliQ Transfer Out",
      counterparty: "Reflect Account",
      isCliq: true,
    });
  }

  return null;
}

function matchOrangeMoney(text: string, receivedAt: string): ParsedSms | null {
  let match = patternMatch(
    text,
    amountRx(String.raw`تم\s+استقبال\s+حواله?\s+ماليه?\s+من\s+(?<counterparty>\S+).*?(?:الى|الي)\s+محفظتك\s+بمبلغ\s+(?<amount>{{amount}})\s*دينار`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Income",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Mobile Wallet Transfer",
      categoryHint: "Wallet Transfer In",
      counterparty: cleanParty(match.counterparty),
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`تمت\s+عمليه?\s+التحويل\s+المالي\s+(?:الى|الي)\s+المحفظه?\s+(?<counterparty>\S+)\s+بمبلغ\s+(?<amount>{{amount}})\s*دينار`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Mobile Wallet Transfer",
      categoryHint: "Wallet Transfer Out",
      counterparty: cleanParty(match.counterparty),
    });
  }

  return null;
}

function matchHousingBank(text: string, receivedAt: string): ParsedSms | null {
  let match = patternMatch(
    text,
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+transferred\s+by\s+cliq\s+to\s+account\s+(?<account>\S+).*?\s+from\s+(?<counterparty>.+?)\.\s+available\s+balance`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Income",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "CliQ Transfer",
      categoryHint: "CliQ Transfer In",
      counterparty: cleanParty(match.counterparty),
      isCliq: true,
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+transferred\s+by\s+cliq\s+from\s+account\s+(?<account>\S+).*?\s+to\s+(?<counterparty>.+?)\.\s+available\s+balance`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "CliQ Transfer",
      categoryHint: "CliQ Transfer Out",
      counterparty: cleanParty(match.counterparty),
      isCliq: true,
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+deposited\s+to\s+account\s+(?<account>\S+).*?\s+from\s+atm\s+(?<merchant>.+?)\s+with\s+authorization\s+number`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Income",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "ATM Deposit",
      categoryHint: "ATM Deposit",
      merchantName: prefixAtm(match.merchant),
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+withdrawn\s+from\s+account\s+(?<account>\S+).*?\s+from\s+atm\s+(?<merchant>.+?)\s+with\s+authorization\s+number`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "ATM Withdrawal",
      categoryHint: "ATM Withdrawal",
      merchantName: prefixAtm(match.merchant),
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+debited\s+as\s+(?<merchant>.+?)\s+from\s+account\s+(?<account>\S+)\s+on\b`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Bank Fee",
      categoryHint: "Bank Fees",
      merchantName: cleanParty(match.merchant),
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`تم\s+دفع\s+فاتوره?\s+(?<merchant>.+?)\s+رقم\s+(?<billNo>\S+)\s+بقيمه?\s+(?<amount>{{amount}})\s*دينار`),
  );
  if (match) {
    const biller = cleanParty(match.merchant);
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Bill Payment",
      categoryHint: categoryForBiller(biller),
      merchantName: biller,
    });
  }

  return null;
}

function matchGeneric(text: string, receivedAt: string): ParsedSms | null {
  let match = patternMatch(
    text,
    amountRx(String.raw`(?<amount>{{amount}})\s*jod\s+cliq\s+transfer\s+from\s+(?<counterparty>.+?)\.\s+available\s+balance`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Income",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "CliQ Transfer",
      categoryHint: "CliQ Transfer In",
      counterparty: cleanParty(match.counterparty),
      isCliq: true,
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`(?<amount>{{amount}})\s*jod\s+cliq\s+transfer\s+to\s+(?<counterparty>.+?)\.\s+available\s+balance`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "CliQ Transfer",
      categoryHint: "CliQ Transfer Out",
      counterparty: cleanParty(match.counterparty),
      isCliq: true,
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`(?<amount>{{amount}})\s*jod\s+at\s+(?<merchant>.+?)\.\s+card\s+(?<card>\d+)\.\s+available\s+balance`),
  );
  if (match) {
    const merchant = cleanParty(match.merchant);
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Card Payment",
      categoryHint: categoryForMerchant(merchant, { isCardPayment: true }),
      merchantName: merchant,
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`bill\s+no\.\s+(?<billNo>\S+)\s+of\s+(?<amount>{{amount}})\s*jod\s+has\s+been\s+paid\s+to\s+(?<merchant>.+?)\.\s+ref\s+no\.`),
  );
  if (match) {
    const biller = cleanParty(match.merchant);
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Bill Payment",
      categoryHint: categoryForBiller(biller),
      merchantName: biller,
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`refund\s+of\s+(?<amount>{{amount}})\s*jod\s+at\s+(?<merchant>.+?)\.\s+available\s+balance`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Income",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Refund/Reversal",
      categoryHint: "Refund",
      merchantName: cleanParty(match.merchant),
    });
  }

  match = patternMatch(
    text,
    amountRx(String.raw`successfully\s+purchased\s+a\s+voucher\s+from\s+(?<merchant>.+?)\s+for\s+(?<amount>{{amount}})\s*jod\b`),
  );
  if (match) {
    return parsedSms({
      amount: match.amount,
      type: "Expense",
      receivedAt,
      balanceAfter: match.balance ?? extractBalance(text),
      smsKind: "Voucher Purchase",
      categoryHint: categoryForMerchant(match.merchant, { isVoucher: true }),
      merchantName: cleanParty(match.merchant),
    });
  }

  return null;
}

function fallbackType(text: string): "Income" | "Expense" | null {
  if (/(?:credited|credit|deposit|deposited|received|salary|refund|cashback|reversal|reversed|ايداع|وارد|استلام|استقبال)/i.test(text)) {
    return "Income";
  }
  if (/(?:debited|debit|withdrawn|withdrawal|paid|payment|purchase|pos|visa|card|bill|biller|efawateercom|atm|fee|fees|خصم|سحب|شراء|دفع|فاتوره|فواتير|عموله|رسوم)/i.test(text)) {
    return "Expense";
  }
  return null;
}

function hasStrongTransactionKeyword(text: string) {
  return /(?:credited|debited|deposited|withdrawn|transferred|refund|reversal|paid|payment|purchase|bill\s+no\.|available\s+balance|current\s+balance|تم\s+قيد|تمت\s+عمليه\s+التحويل|تم\s+استقبال|تم\s+دفع|الرصيد\s+المتوفر|رصيد\s+المحفظه\s+المتاح)/i
    .test(text);
}

function fallbackSmsKind(text: string) {
  if (/cliq|كليك/i.test(text)) return "CliQ Transfer";
  if (/voucher/i.test(text)) return "Voucher Purchase";
  if (/refund|reversal|reversed/i.test(text)) return "Refund/Reversal";
  if (/atm/i.test(text) && /deposit|deposited/i.test(text)) {
    return "ATM Deposit";
  }
  if (/atm/i.test(text) && /withdraw|withdrawn/i.test(text)) {
    return "ATM Withdrawal";
  }
  if (/bill|biller|efawateercom|فاتوره/i.test(text)) return "Bill Payment";
  if (/fee|fees|عموله|رسوم/i.test(text)) return "Bank Fee";
  if (/purchase|pos|card|visa|شراء/i.test(text)) return "Card Payment";
  if (/credited|credit/i.test(text)) return "Bank Credit";
  return "Bank Transaction";
}

function categoryForKind(
  smsKind: string,
  type: "Income" | "Expense",
  merchantName: string | null,
) {
  switch (smsKind) {
    case "Bank Credit":
      return "Bank Credit";
    case "CliQ Transfer":
      return type === "Income" ? "CliQ Transfer In" : "CliQ Transfer Out";
    case "Mobile Wallet Transfer":
      return type === "Income" ? "Wallet Transfer In" : "Wallet Transfer Out";
    case "ATM Deposit":
      return "ATM Deposit";
    case "ATM Withdrawal":
      return "ATM Withdrawal";
    case "Bank Fee":
      return "Bank Fees";
    case "Bill Payment":
      return categoryForBiller(merchantName);
    case "Card Payment":
      return categoryForMerchant(merchantName, { isCardPayment: true });
    case "Voucher Purchase":
      return categoryForMerchant(merchantName, { isVoucher: true });
    case "Refund/Reversal":
      return "Refund";
    default:
      return type === "Income" ? "Income" : "General Expense";
  }
}

function extractMerchantName(text: string) {
  const patterns = [
    /from\s+(?<merchant>atm\s+[a-z0-9\u0600-\u06ff\s\-_]+?)\s+with\s+authorization/i,
    /from\s+(?<merchant>[a-z0-9\u0600-\u06ff\s\-_]+?)\s+amount/i,
    /paid\s+to\s+(?<merchant>.+?)(?:\.|$)/i,
    /at\s+(?<merchant>.+?)(?:\.|,| on | available|$)/i,
    /لدى\s+(?<merchant>.+?)(?:\.|،| بتاريخ| الرصيد|$)/i,
    /لدي\s+(?<merchant>.+?)(?:\.|،| بتاريخ| الرصيد|$)/i,
  ];

  for (const pattern of patterns) {
    const match = pattern.exec(text);
    const value = cleanParty(match?.groups?.merchant);
    if (!value) continue;

    const lower = value.toLowerCase();
    if (
      lower.includes("account") ||
      lower.includes("balance") ||
      lower.includes("authorization") ||
      lower.includes("available")
    ) {
      continue;
    }

    return value;
  }

  return null;
}

function matchFallback(text: string, receivedAt: string): ParsedSms | null {
  const type = fallbackType(text);
  if (!type || !hasStrongTransactionKeyword(text)) return null;

  const amount = extractAmount(text);
  if (amount == null || amount <= 0) return null;

  const merchantName = extractMerchantName(text);
  const smsKind = fallbackSmsKind(text);
  return parsedSms({
    amount,
    type,
    receivedAt,
    balanceAfter: extractBalance(text),
    smsKind,
    categoryHint: categoryForKind(smsKind, type, merchantName),
    merchantName,
    isCliq: /cliq|كليك/i.test(text),
  });
}

function parseSms(
  smsBody: string,
  receivedAt: string,
  senderId: string,
): ParsedSms | null {
  const text = normalizeText(smsBody);
  const sender = normalizeText(senderId);
  if (!text || shouldIgnore(text)) return null;

  if (isReflectMessage(text, sender)) {
    const parsed = matchReflect(text, receivedAt);
    if (parsed) return parsed;
  }

  if (isOrangeMoneyMessage(text, sender)) {
    const parsed = matchOrangeMoney(text, receivedAt);
    if (parsed) return parsed;
  }

  return matchHousingBank(text, receivedAt) ??
    matchGeneric(text, receivedAt) ??
    matchFallback(text, receivedAt);
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
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

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
    const parsed = parseSms(smsBody, receivedAt, senderId);

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
      p_category_hint: parsed?.categoryHint ?? null,
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
