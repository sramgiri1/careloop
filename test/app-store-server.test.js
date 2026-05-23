import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import {
  appStoreServerBaseURL,
  appStoreServerConfig,
  assertAppStoreServerConfig,
  decodeJWSPayload,
  summarizeAppleTransaction,
  verifyAppStoreTransaction,
} from "../src/lib/app-store-server.js";

function unsignedJWS(payload) {
  const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: "test" })).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return `${header}.${body}.signature`;
}

function testPrivateKey() {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  return privateKey.export({ type: "pkcs8", format: "pem" });
}

test("appStoreServerConfig defaults verification off and sandbox endpoint", () => {
  const config = appStoreServerConfig({});
  assert.equal(config.enabled, false);
  assert.equal(config.environment, "sandbox");
  assert.equal(appStoreServerBaseURL(config.environment), "https://api.storekit-sandbox.apple.com");
});

test("assertAppStoreServerConfig reports all missing required keys when enabled", () => {
  assert.throws(
    () => assertAppStoreServerConfig(appStoreServerConfig({ APP_STORE_SERVER_API_ENABLED: "true" })),
    /APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_PRIVATE_KEY, APP_STORE_BUNDLE_ID/,
  );
});

test("decodeJWSPayload and summarizeAppleTransaction handle active, expired, and refunded fixtures", () => {
  const now = new Date("2026-05-18T00:00:00.000Z");
  const activePayload = decodeJWSPayload(unsignedJWS({
    bundleId: "com.careloop.ios",
    productId: "com.careloop.ios.premium.monthly",
    transactionId: "tx-active",
    originalTransactionId: "otx-active",
    expiresDate: "1780000000000",
  }));
  assert.equal(summarizeAppleTransaction(activePayload, now).status, "ACTIVE");

  const expired = summarizeAppleTransaction({
    ...activePayload,
    expiresDate: "1760000000000",
  }, now);
  assert.equal(expired.status, "EXPIRED");

  const refunded = summarizeAppleTransaction({
    ...activePayload,
    revocationDate: "1770000000000",
  }, now);
  assert.equal(refunded.status, "REFUNDED");
});

test("verifyAppStoreTransaction calls Apple transaction endpoint and validates product identity", async () => {
  const config = appStoreServerConfig({
    APP_STORE_SERVER_API_ENABLED: "true",
    APP_STORE_SERVER_ENVIRONMENT: "sandbox",
    APP_STORE_CONNECT_ISSUER_ID: "issuer-123",
    APP_STORE_CONNECT_KEY_ID: "key-123",
    APP_STORE_CONNECT_PRIVATE_KEY: testPrivateKey(),
    APP_STORE_BUNDLE_ID: "com.careloop.ios",
  });
  const payload = {
    bundleId: "com.careloop.ios",
    productId: "com.careloop.ios.premium.monthly",
    transactionId: "tx-123",
    originalTransactionId: "otx-123",
    expiresDate: "1780000000000",
  };
  let requestedURL = "";
  let authorization = "";
  const result = await verifyAppStoreTransaction({
    transactionId: "otx-123",
    expectedProductId: "com.careloop.ios.premium.monthly",
    expectedOriginalTransactionId: "otx-123",
    config,
    now: new Date("2026-05-18T00:00:00.000Z"),
    fetchImpl: async (url, options) => {
      requestedURL = url;
      authorization = options.headers.authorization;
      return {
        ok: true,
        status: 200,
        json: async () => ({ signedTransactionInfo: unsignedJWS(payload) }),
      };
    },
  });

  assert.equal(requestedURL, "https://api.storekit-sandbox.apple.com/inApps/v1/transactions/otx-123");
  assert.match(authorization, /^Bearer /);
  assert.equal(result.verified, true);
  assert.equal(result.transaction.productId, "com.careloop.ios.premium.monthly");
});

test("verifyAppStoreTransaction rejects mismatched products", async () => {
  const config = appStoreServerConfig({
    APP_STORE_SERVER_API_ENABLED: "true",
    APP_STORE_CONNECT_ISSUER_ID: "issuer-123",
    APP_STORE_CONNECT_KEY_ID: "key-123",
    APP_STORE_CONNECT_PRIVATE_KEY: testPrivateKey(),
    APP_STORE_BUNDLE_ID: "com.careloop.ios",
  });

  await assert.rejects(
    verifyAppStoreTransaction({
      transactionId: "otx-123",
      expectedProductId: "com.careloop.ios.premium.yearly",
      expectedOriginalTransactionId: "otx-123",
      config,
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({
          signedTransactionInfo: unsignedJWS({
            bundleId: "com.careloop.ios",
            productId: "com.careloop.ios.premium.monthly",
            transactionId: "tx-123",
            originalTransactionId: "otx-123",
          }),
        }),
      }),
    }),
    /product does not match/,
  );
});
