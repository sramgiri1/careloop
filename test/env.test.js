import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { validateProductionEnvironment } from "../src/lib/env.js";

function baseEnv(overrides = {}) {
  return {
    NODE_ENV: "production",
    DATABASE_URL: "postgresql://postgres:password@db.example.supabase.co:5432/postgres?sslmode=require",
    AUTH_TOKEN_SECRET: "0123456789abcdef0123456789abcdef",
    PUBLIC_API_BASE_URL: "https://api.careloop.example",
    DAILY_DIGEST_HOUR: "8",
    REMINDER_ESCALATION_MINUTES: "30",
    RESEND_API_KEY: "resend-key",
    RESEND_FROM: "CareLoop <noreply@example.com>",
    ...overrides,
  };
}

describe("production environment validation", () => {
  test("accepts the minimal production API environment", () => {
    const report = validateProductionEnvironment(baseEnv());
    assert.deepEqual(report.errors, []);
  });

  test("requires core production secrets without exposing values", () => {
    const report = validateProductionEnvironment(baseEnv({
      DATABASE_URL: "",
      AUTH_TOKEN_SECRET: "short",
      PUBLIC_API_BASE_URL: "http://localhost:3000",
    }));

    assert(report.errors.includes("DATABASE_URL is required"));
    assert(report.errors.includes("AUTH_TOKEN_SECRET must be at least 32 characters"));
    assert(report.errors.includes("PUBLIC_API_BASE_URL must be a valid https URL in production"));
    assert(!report.errors.join("\n").includes("short"));
  });

  test("requires sslmode for Supabase database connections", () => {
    const report = validateProductionEnvironment(baseEnv({
      DATABASE_URL: "postgresql://postgres:password@db.example.supabase.co:5432/postgres",
    }));

    assert(report.errors.includes("DATABASE_URL for Supabase must include sslmode=require"));
  });

  test("fails partial provider configs but keeps absent external providers as warnings", () => {
    const report = validateProductionEnvironment(baseEnv({
      APNS_KEY_ID: "key-id",
      GOOGLE_CLIENT_ID: "google-client",
      APP_STORE_SERVER_API_ENABLED: "true",
    }));

    assert(report.errors.includes("APNs config is partial; missing APNS_TEAM_ID, APNS_KEY"));
    assert(report.errors.includes("Google OAuth config is partial; missing GOOGLE_CLIENT_SECRET"));
    assert(report.errors.includes("APP_STORE_CONNECT_ISSUER_ID is required when APP_STORE_SERVER_API_ENABLED=true"));
  });
});
