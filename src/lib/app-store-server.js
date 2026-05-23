import { SignJWT, importPKCS8 } from "jose";

const SANDBOX_BASE_URL = "https://api.storekit-sandbox.apple.com";
const PRODUCTION_BASE_URL = "https://api.storekit.apple.com";
const APP_STORE_AUDIENCE = "appstoreconnect-v1";

export class AppStoreVerificationError extends Error {
  constructor(message, code = "APP_STORE_VERIFICATION_FAILED", statusCode = 400) {
    super(message);
    this.name = "AppStoreVerificationError";
    this.code = code;
    this.statusCode = statusCode;
  }
}

export function appStoreServerConfig(env = process.env) {
  const enabled = env.APP_STORE_SERVER_API_ENABLED === "true";
  const environment = env.APP_STORE_SERVER_ENVIRONMENT === "production" ? "production" : "sandbox";
  const privateKey = (env.APP_STORE_CONNECT_PRIVATE_KEY || "").replace(/\\n/g, "\n").trim();

  return {
    enabled,
    environment,
    issuerId: env.APP_STORE_CONNECT_ISSUER_ID?.trim() || "",
    keyId: env.APP_STORE_CONNECT_KEY_ID?.trim() || "",
    privateKey,
    bundleId: env.APP_STORE_BUNDLE_ID?.trim() || "",
  };
}

export function appStoreServerBaseURL(environment) {
  return environment === "production" ? PRODUCTION_BASE_URL : SANDBOX_BASE_URL;
}

function missingConfigKeys(config) {
  return [
    ["APP_STORE_CONNECT_ISSUER_ID", config.issuerId],
    ["APP_STORE_CONNECT_KEY_ID", config.keyId],
    ["APP_STORE_CONNECT_PRIVATE_KEY", config.privateKey],
    ["APP_STORE_BUNDLE_ID", config.bundleId],
  ].filter(([, value]) => !value).map(([key]) => key);
}

export function assertAppStoreServerConfig(config = appStoreServerConfig()) {
  if (!config.enabled) return;
  const missing = missingConfigKeys(config);
  if (missing.length > 0) {
    throw new AppStoreVerificationError(
      `App Store Server API is enabled but missing ${missing.join(", ")}`,
      "APP_STORE_SERVER_CONFIG_MISSING",
      500,
    );
  }
}

export async function createAppStoreServerToken(config = appStoreServerConfig(), now = new Date()) {
  assertAppStoreServerConfig(config);
  const key = await importPKCS8(config.privateKey, "ES256");
  const issuedAt = Math.floor(now.getTime() / 1000);

  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyId, typ: "JWT" })
    .setIssuer(config.issuerId)
    .setAudience(APP_STORE_AUDIENCE)
    .setIssuedAt(issuedAt)
    .setExpirationTime(issuedAt + 20 * 60)
    .sign(key);
}

export function decodeJWSPayload(jws) {
  const payload = String(jws || "").split(".")[1];
  if (!payload) {
    throw new AppStoreVerificationError("App Store response is missing signed transaction payload");
  }
  try {
    return JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
  } catch {
    throw new AppStoreVerificationError("App Store signed transaction payload could not be decoded");
  }
}

function dateFromAppleMilliseconds(value) {
  if (value === null || value === undefined || value === "") return null;
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return null;
  return new Date(numeric);
}

export function summarizeAppleTransaction(payload, now = new Date()) {
  const expiresAt = dateFromAppleMilliseconds(payload.expiresDate);
  const refundedAt = dateFromAppleMilliseconds(payload.revocationDate);
  let status = "ACTIVE";
  if (refundedAt) {
    status = "REFUNDED";
  } else if (expiresAt && expiresAt <= now) {
    status = "EXPIRED";
  }

  return {
    status,
    productId: payload.productId,
    transactionId: payload.transactionId,
    originalTransactionId: payload.originalTransactionId,
    bundleId: payload.bundleId,
    expiresAt,
    refundedAt,
  };
}

export async function verifyAppStoreTransaction({
  transactionId,
  expectedProductId,
  expectedOriginalTransactionId,
  config = appStoreServerConfig(),
  fetchImpl = globalThis.fetch,
  now = new Date(),
} = {}) {
  if (!config.enabled) {
    return { verified: false, skipped: true, reason: "APP_STORE_SERVER_API_DISABLED" };
  }
  assertAppStoreServerConfig(config);
  if (!transactionId) {
    throw new AppStoreVerificationError("App Store transaction id is required");
  }
  if (typeof fetchImpl !== "function") {
    throw new AppStoreVerificationError("fetch is unavailable for App Store Server API verification", "APP_STORE_FETCH_UNAVAILABLE", 500);
  }

  const token = await createAppStoreServerToken(config, now);
  const url = `${appStoreServerBaseURL(config.environment)}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`;
  const response = await fetchImpl(url, {
    method: "GET",
    headers: { authorization: `Bearer ${token}` },
  });

  if (!response.ok) {
    throw new AppStoreVerificationError(
      `App Store transaction verification failed with ${response.status}`,
      "APP_STORE_TRANSACTION_LOOKUP_FAILED",
      response.status === 401 ? 502 : 400,
    );
  }

  const body = await response.json();
  const payload = decodeJWSPayload(body.signedTransactionInfo);
  const summary = summarizeAppleTransaction(payload, now);

  if (summary.bundleId !== config.bundleId) {
    throw new AppStoreVerificationError("App Store transaction does not belong to this app bundle");
  }
  if (expectedProductId && summary.productId !== expectedProductId) {
    throw new AppStoreVerificationError("App Store transaction product does not match requested entitlement");
  }
  if (expectedOriginalTransactionId && summary.originalTransactionId !== expectedOriginalTransactionId) {
    throw new AppStoreVerificationError("App Store transaction identity does not match requested entitlement");
  }

  return { verified: true, transaction: summary };
}
