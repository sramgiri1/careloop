const REQUIRED_PRODUCTION_ENV = Object.freeze([
  "DATABASE_URL",
  "AUTH_TOKEN_SECRET",
  "PUBLIC_API_BASE_URL",
]);

const APP_STORE_SERVER_ENV = Object.freeze([
  "APP_STORE_CONNECT_ISSUER_ID",
  "APP_STORE_CONNECT_KEY_ID",
  "APP_STORE_CONNECT_PRIVATE_KEY",
  "APP_STORE_BUNDLE_ID",
]);

function value(env, key) {
  return `${env[key] ?? ""}`.trim();
}

function isTruthy(value) {
  return ["1", "true", "yes", "on"].includes(`${value ?? ""}`.trim().toLowerCase());
}

function parseUrl(raw) {
  try {
    return new URL(raw);
  } catch {
    return null;
  }
}

function addPartialConfigIssue(env, keys, errors, label) {
  const present = keys.filter((key) => value(env, key));
  if (present.length > 0 && present.length < keys.length) {
    const missing = keys.filter((key) => !value(env, key));
    errors.push(`${label} config is partial; missing ${missing.join(", ")}`);
  }
}

export function validateProductionEnvironment(env = process.env) {
  const errors = [];
  const warnings = [];

  for (const key of REQUIRED_PRODUCTION_ENV) {
    if (!value(env, key)) errors.push(`${key} is required`);
  }

  if (value(env, "NODE_ENV") !== "production") {
    warnings.push("NODE_ENV should be set to production for Railway production deploys");
  }

  const databaseUrl = value(env, "DATABASE_URL");
  if (databaseUrl) {
    const parsed = parseUrl(databaseUrl);
    if (!parsed || !["postgres:", "postgresql:"].includes(parsed.protocol)) {
      errors.push("DATABASE_URL must be a valid postgres/postgresql connection string");
    } else {
      const host = parsed.hostname.toLowerCase();
      const sslMode = parsed.searchParams.get("sslmode");
      const isLocal = host === "localhost" || host === "127.0.0.1" || host === "::1";
      const isSupabase = host.endsWith(".supabase.co") || host.includes("supabase");
      if (isSupabase && sslMode !== "require") {
        errors.push("DATABASE_URL for Supabase must include sslmode=require");
      } else if (!isLocal && !sslMode) {
        warnings.push("DATABASE_URL points to remote Postgres without an explicit sslmode");
      }
    }
  }

  const authSecret = value(env, "AUTH_TOKEN_SECRET");
  if (authSecret && authSecret.length < 32) {
    errors.push("AUTH_TOKEN_SECRET must be at least 32 characters");
  }

  const publicApiBaseUrl = value(env, "PUBLIC_API_BASE_URL");
  if (publicApiBaseUrl) {
    const parsed = parseUrl(publicApiBaseUrl);
    if (!parsed || parsed.protocol !== "https:") {
      errors.push("PUBLIC_API_BASE_URL must be a valid https URL in production");
    } else if (["localhost", "127.0.0.1", "::1"].includes(parsed.hostname.toLowerCase())) {
      errors.push("PUBLIC_API_BASE_URL must not point to localhost in production");
    } else if (parsed.pathname !== "/" || parsed.search || parsed.hash) {
      warnings.push("PUBLIC_API_BASE_URL should be only the API origin, without path, query, or hash");
    }
  }

  const dailyDigestHour = value(env, "DAILY_DIGEST_HOUR");
  if (dailyDigestHour) {
    const parsedHour = Number(dailyDigestHour);
    if (!Number.isInteger(parsedHour) || parsedHour < 0 || parsedHour > 23) {
      errors.push("DAILY_DIGEST_HOUR must be an integer between 0 and 23");
    }
  }

  const escalationMinutes = value(env, "REMINDER_ESCALATION_MINUTES");
  if (escalationMinutes) {
    const parsedMinutes = Number(escalationMinutes);
    if (!Number.isInteger(parsedMinutes) || parsedMinutes <= 0) {
      errors.push("REMINDER_ESCALATION_MINUTES must be a positive integer");
    }
  }

  if (isTruthy(value(env, "DISABLE_SCHEDULER"))) {
    errors.push("DISABLE_SCHEDULER must not be enabled in production");
  }

  if (!value(env, "RESEND_API_KEY")) {
    warnings.push("RESEND_API_KEY is missing; invite/reminder email delivery will be simulated");
  }

  const resendFrom = value(env, "RESEND_FROM");
  if (!resendFrom) {
    warnings.push("RESEND_FROM is missing; email will use the local fallback sender");
  } else if (resendFrom.includes("careloop.local")) {
    warnings.push("RESEND_FROM must use a verified production sender domain");
  }

  addPartialConfigIssue(env, ["APNS_KEY_ID", "APNS_TEAM_ID", "APNS_KEY"], errors, "APNs");
  if (value(env, "APNS_KEY_ID") && value(env, "APNS_TEAM_ID") && value(env, "APNS_KEY")) {
    const apnsHost = value(env, "APNS_HOST") || "api.sandbox.push.apple.com";
    if (apnsHost !== "api.push.apple.com") {
      warnings.push("APNS_HOST is not api.push.apple.com; production push will use sandbox or custom APNs host");
    }
    if (!value(env, "APNS_TOPIC")) {
      warnings.push("APNS_TOPIC is missing; backend will use the default bundle topic");
    }
  } else {
    warnings.push("APNs is not configured; push delivery will be simulated or fall back to email");
  }

  addPartialConfigIssue(env, ["GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET"], errors, "Google OAuth");
  addPartialConfigIssue(env, ["FACEBOOK_APP_ID", "FACEBOOK_APP_SECRET"], errors, "Facebook OAuth");
  const appleOAuthKeys = ["APPLE_SERVICE_ID", "APPLE_CLIENT_ID", "APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY"];
  const hasAnyAppleOAuth = appleOAuthKeys.some((key) => value(env, key));
  if (hasAnyAppleOAuth) {
    const missing = [];
    if (!value(env, "APPLE_SERVICE_ID") && !value(env, "APPLE_CLIENT_ID")) {
      missing.push("APPLE_SERVICE_ID or APPLE_CLIENT_ID");
    }
    for (const key of ["APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY"]) {
      if (!value(env, key)) missing.push(key);
    }
    if (missing.length > 0) {
      errors.push(`Apple OAuth config is partial; missing ${missing.join(", ")}`);
    }
  }

  if (isTruthy(value(env, "APP_STORE_SERVER_API_ENABLED"))) {
    for (const key of APP_STORE_SERVER_ENV) {
      if (!value(env, key)) errors.push(`${key} is required when APP_STORE_SERVER_API_ENABLED=true`);
    }
    const environment = value(env, "APP_STORE_SERVER_ENVIRONMENT");
    if (environment && !["sandbox", "production"].includes(environment)) {
      errors.push("APP_STORE_SERVER_ENVIRONMENT must be sandbox or production");
    }
  } else {
    warnings.push("APP_STORE_SERVER_API_ENABLED is not true; App Store transaction verification is disabled");
  }

  return { errors, warnings };
}

export function assertProductionEnvironment(env = process.env) {
  const report = validateProductionEnvironment(env);
  if (value(env, "NODE_ENV") === "production" && report.errors.length > 0) {
    throw new Error([
      "CareLoop production environment is invalid.",
      ...report.errors.map((error) => `- ${error}`),
    ].join("\n"));
  }
  return report;
}
