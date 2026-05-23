import crypto from "node:crypto";
import { SignJWT, createRemoteJWKSet, importPKCS8, jwtVerify } from "jose";

const SALT_BYTES = 16;
const KEY_LENGTH = 64;
const SCRYPT_COST = 16384;
const APPLE_JWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
const PASSWORD_RESET_MINUTES = 10;
const OAUTH_STATE_TTL_MS = 10 * 60 * 1000;
const GOOGLE_SCOPES = ["openid", "email", "profile"];
const FACEBOOK_SCOPES = ["email", "public_profile"];
const ACCESS_TOKEN_TTL = "30d";
const ACCESS_TOKEN_ISSUER = "careloop";
const ACCESS_TOKEN_AUDIENCE = "careloop-client";
const textEncoder = new TextEncoder();

function base64UrlEncode(value) {
  return Buffer.from(value).toString("base64url");
}

function base64UrlDecode(value) {
  return Buffer.from(value, "base64url").toString("utf8");
}

export function normalizeEmail(value) {
  return value?.trim().toLowerCase() ?? "";
}

export function hashValue(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function authSecretRaw() {
  const configured = process.env.AUTH_TOKEN_SECRET?.trim();
  if (configured) return configured;
  throw new Error("AUTH_TOKEN_SECRET must be configured");
}

function authSecretKey() {
  return textEncoder.encode(authSecretRaw());
}

export async function issueAccessToken(user) {
  return new SignJWT({
    email: normalizeEmail(user.email),
    name: user.name ?? undefined,
    ver: Number.isInteger(user.authVersion) ? user.authVersion : 0,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer(ACCESS_TOKEN_ISSUER)
    .setAudience(ACCESS_TOKEN_AUDIENCE)
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime(ACCESS_TOKEN_TTL)
    .sign(authSecretKey());
}

export async function verifyAccessToken(token) {
  const { payload } = await jwtVerify(token, authSecretKey(), {
    issuer: ACCESS_TOKEN_ISSUER,
    audience: ACCESS_TOKEN_AUDIENCE,
  });

  return {
    userId: payload.sub,
    email: typeof payload.email === "string" ? normalizeEmail(payload.email) : null,
    name: typeof payload.name === "string" ? payload.name : null,
    tokenVersion: Number.isInteger(payload.ver) ? payload.ver : 0,
  };
}

export function hashPassword(password) {
  const salt = crypto.randomBytes(SALT_BYTES).toString("hex");
  const derived = crypto.scryptSync(password, salt, KEY_LENGTH, { N: SCRYPT_COST }).toString("hex");
  return `scrypt$${salt}$${derived}`;
}

export function verifyPassword(password, passwordHash) {
  if (!passwordHash) return false;
  const [algorithm, salt, stored] = passwordHash.split("$");
  if (algorithm !== "scrypt" || !salt || !stored) return false;
  const derived = crypto.scryptSync(password, salt, KEY_LENGTH, { N: SCRYPT_COST });
  const storedBuffer = Buffer.from(stored, "hex");
  if (storedBuffer.length !== derived.length) return false;
  return crypto.timingSafeEqual(storedBuffer, derived);
}

export function sanitizeUser(user) {
  if (!user) return user;
  const { passwordHash, ...safe } = user;
  return safe;
}

export function generateNumericCode(length = 6) {
  let output = "";
  while (output.length < length) {
    output += crypto.randomInt(0, 10).toString();
  }
  return output.slice(0, length);
}

export function passwordResetExpiry() {
  return new Date(Date.now() + PASSWORD_RESET_MINUTES * 60 * 1000);
}

export function passwordResetMinutes() {
  return PASSWORD_RESET_MINUTES;
}

function localFallbackAllowed() {
  return process.env.NODE_ENV !== "production";
}

function signStatePayload(serialized) {
  return crypto
    .createHmac("sha256", authSecretRaw())
    .update(serialized)
    .digest("base64url");
}

function publicBaseUrlFor(request) {
  const configured = process.env.PUBLIC_API_BASE_URL?.trim();
  if (configured) return configured.replace(/\/+$/, "");
  const protocol = request.protocol || request.headers["x-forwarded-proto"] || "http";
  const host = request.headers["x-forwarded-host"] || request.headers.host;
  return `${protocol}://${host}`;
}

function buildAppRedirect(callbackScheme, params) {
  const url = new URL(`${callbackScheme}://auth`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && `${value}`.length > 0) {
      url.searchParams.set(key, `${value}`);
    }
  }
  return url.toString();
}

function oauthProviderConfig(provider) {
  switch (provider) {
    case "GOOGLE":
      return {
        clientId: process.env.GOOGLE_CLIENT_ID?.trim(),
        clientSecret: process.env.GOOGLE_CLIENT_SECRET?.trim(),
      };
    case "FACEBOOK":
      return {
        clientId: process.env.FACEBOOK_APP_ID?.trim(),
        clientSecret: process.env.FACEBOOK_APP_SECRET?.trim(),
      };
    case "APPLE":
      return {
        clientId: (process.env.APPLE_SERVICE_ID || process.env.APPLE_CLIENT_ID || "").trim(),
        teamId: process.env.APPLE_TEAM_ID?.trim(),
        keyId: process.env.APPLE_KEY_ID?.trim(),
        privateKey: process.env.APPLE_PRIVATE_KEY?.trim(),
      };
    default:
      return null;
  }
}

export function isOAuthConfigured(provider) {
  const config = oauthProviderConfig(provider);
  if (!config) return false;
  switch (provider) {
    case "GOOGLE":
    case "FACEBOOK":
      return Boolean(config.clientId && config.clientSecret);
    case "APPLE":
      return Boolean(config.clientId && config.teamId && config.keyId && config.privateKey);
    default:
      return false;
  }
}

export function createOAuthState({ provider, callbackScheme }) {
  const payload = {
    provider,
    callbackScheme,
    nonce: crypto.randomBytes(12).toString("hex"),
    issuedAt: Date.now(),
  };
  const encoded = base64UrlEncode(JSON.stringify(payload));
  return `${encoded}.${signStatePayload(encoded)}`;
}

export function verifyOAuthState(state) {
  if (!state || !state.includes(".")) {
    throw new Error("Missing OAuth state");
  }
  const [encoded, signature] = state.split(".");
  const expected = signStatePayload(encoded);
  const signatureBuffer = Buffer.from(signature);
  const expectedBuffer = Buffer.from(expected);
  if (signatureBuffer.length !== expectedBuffer.length || !crypto.timingSafeEqual(signatureBuffer, expectedBuffer)) {
    throw new Error("Invalid OAuth state");
  }
  const payload = JSON.parse(base64UrlDecode(encoded));
  if (!payload.issuedAt || Date.now() - payload.issuedAt > OAUTH_STATE_TTL_MS) {
    throw new Error("OAuth state expired");
  }
  return payload;
}

export function providerFromSlug(slug) {
  switch ((slug || "").toLowerCase()) {
    case "google":
      return "GOOGLE";
    case "facebook":
      return "FACEBOOK";
    case "apple":
      return "APPLE";
    default:
      throw new Error("Unsupported provider");
  }
}

export function normalizeAuthProvider(provider) {
  if (!provider || typeof provider !== "string") return null;
  const normalized = provider.trim().toUpperCase();
  return ["GOOGLE", "FACEBOOK", "APPLE"].includes(normalized) ? normalized : null;
}

export function buildOAuthStartUrl(provider, request, callbackScheme) {
  if (!isOAuthConfigured(provider)) {
    throw new Error(`${provider} sign-in is not configured yet.`);
  }

  const state = createOAuthState({ provider, callbackScheme });
  const redirectUri = `${publicBaseUrlFor(request)}/auth/oauth/${provider.toLowerCase()}/callback`;

  switch (provider) {
    case "GOOGLE": {
      const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
      url.searchParams.set("client_id", process.env.GOOGLE_CLIENT_ID);
      url.searchParams.set("redirect_uri", redirectUri);
      url.searchParams.set("response_type", "code");
      url.searchParams.set("scope", GOOGLE_SCOPES.join(" "));
      url.searchParams.set("state", state);
      url.searchParams.set("access_type", "offline");
      url.searchParams.set("prompt", "select_account");
      return url;
    }
    case "FACEBOOK": {
      const url = new URL("https://www.facebook.com/v19.0/dialog/oauth");
      url.searchParams.set("client_id", process.env.FACEBOOK_APP_ID);
      url.searchParams.set("redirect_uri", redirectUri);
      url.searchParams.set("state", state);
      url.searchParams.set("response_type", "code");
      url.searchParams.set("scope", FACEBOOK_SCOPES.join(","));
      return url;
    }
    case "APPLE": {
      const clientId = process.env.APPLE_SERVICE_ID || process.env.APPLE_CLIENT_ID;
      const url = new URL("https://appleid.apple.com/auth/authorize");
      url.searchParams.set("client_id", clientId);
      url.searchParams.set("redirect_uri", redirectUri);
      url.searchParams.set("response_type", "code");
      url.searchParams.set("response_mode", "form_post");
      url.searchParams.set("scope", "name email");
      url.searchParams.set("state", state);
      return url;
    }
    default:
      throw new Error("Unsupported provider");
  }
}

async function googleExchangeCode({ code, redirectUri }) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: process.env.GOOGLE_CLIENT_ID,
      client_secret: process.env.GOOGLE_CLIENT_SECRET,
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
    }),
  });
  if (!response.ok) throw new Error("Google code exchange failed");
  const payload = await response.json();
  const profile = payload.id_token
    ? await googleProfileFromIdToken(payload.id_token)
    : await googleProfileFromAccessToken(payload.access_token);
  return {
    ...profile,
    idToken: payload.id_token ?? null,
    accessToken: payload.access_token ?? null,
  };
}

async function facebookExchangeCode({ code, redirectUri }) {
  const tokenUrl = new URL("https://graph.facebook.com/v19.0/oauth/access_token");
  tokenUrl.searchParams.set("client_id", process.env.FACEBOOK_APP_ID);
  tokenUrl.searchParams.set("client_secret", process.env.FACEBOOK_APP_SECRET);
  tokenUrl.searchParams.set("redirect_uri", redirectUri);
  tokenUrl.searchParams.set("code", code);
  const response = await fetch(tokenUrl);
  if (!response.ok) throw new Error("Facebook code exchange failed");
  const payload = await response.json();
  const profile = await facebookProfileFromAccessToken(payload.access_token);
  return {
    ...profile,
    accessToken: payload.access_token ?? null,
    idToken: null,
  };
}

function normalizeApplePrivateKey() {
  return (process.env.APPLE_PRIVATE_KEY || "").replace(/\\n/g, "\n");
}

async function createAppleClientSecret() {
  const clientId = process.env.APPLE_SERVICE_ID || process.env.APPLE_CLIENT_ID;
  const teamId = process.env.APPLE_TEAM_ID;
  const keyId = process.env.APPLE_KEY_ID;
  const privateKey = normalizeApplePrivateKey();
  if (!clientId || !teamId || !keyId || !privateKey) {
    throw new Error("Apple sign-in is not fully configured");
  }
  const signingKey = await importPKCS8(privateKey, "ES256");
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setSubject(clientId)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("180d")
    .sign(signingKey);
}

async function appleExchangeCode({ code, redirectUri, user }) {
  const clientId = process.env.APPLE_SERVICE_ID || process.env.APPLE_CLIENT_ID;
  const response = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: await createAppleClientSecret(),
      code,
      grant_type: "authorization_code",
      redirect_uri: redirectUri,
    }),
  });
  if (!response.ok) throw new Error("Apple code exchange failed");
  const payload = await response.json();
  const profile = await appleProfileFromIdToken(payload.id_token);
  const parsedUser = typeof user === "string" && user ? JSON.parse(user) : null;
  const name = parsedUser
    ? [parsedUser.name?.firstName, parsedUser.name?.lastName].filter(Boolean).join(" ") || null
    : null;
  return {
    ...profile,
    email: profile.email || normalizeEmail(parsedUser?.email),
    name,
    idToken: payload.id_token ?? null,
    accessToken: payload.access_token ?? null,
  };
}

export async function exchangeOAuthCode(provider, { code, redirectUri, user }) {
  switch (provider) {
    case "GOOGLE":
      return googleExchangeCode({ code, redirectUri });
    case "FACEBOOK":
      return facebookExchangeCode({ code, redirectUri });
    case "APPLE":
      return appleExchangeCode({ code, redirectUri, user });
    default:
      throw new Error("Unsupported provider");
  }
}

export function oauthCallbackRedirect({ callbackScheme, provider, payload, error }) {
  if (error) {
    return buildAppRedirect(callbackScheme, { provider, error });
  }
  return buildAppRedirect(callbackScheme, {
    provider,
    email: payload.email,
    name: payload.name,
    provider_user_id: payload.providerUserId,
    id_token: payload.idToken,
    access_token: payload.accessToken,
  });
}

async function googleProfileFromIdToken(idToken) {
  const url = new URL("https://oauth2.googleapis.com/tokeninfo");
  url.searchParams.set("id_token", idToken);
  const res = await fetch(url);
  if (!res.ok) throw new Error("Google token validation failed");
  const payload = await res.json();
  if (payload.email_verified !== "true") throw new Error("Google account email is not verified");
  return {
    providerUserId: payload.sub,
    email: normalizeEmail(payload.email),
    name: payload.name ?? payload.given_name ?? null,
  };
}

async function googleProfileFromAccessToken(accessToken) {
  const res = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error("Google access token validation failed");
  const payload = await res.json();
  if (payload.email_verified !== true) throw new Error("Google account email is not verified");
  return {
    providerUserId: payload.sub,
    email: normalizeEmail(payload.email),
    name: payload.name ?? payload.given_name ?? null,
  };
}

async function facebookProfileFromAccessToken(accessToken) {
  const url = new URL("https://graph.facebook.com/me");
  url.searchParams.set("fields", "id,name,email");
  url.searchParams.set("access_token", accessToken);
  const res = await fetch(url);
  if (!res.ok) throw new Error("Facebook access token validation failed");
  const payload = await res.json();
  return {
    providerUserId: payload.id,
    email: normalizeEmail(payload.email),
    name: payload.name ?? null,
  };
}

async function appleProfileFromIdToken(idToken) {
  const audience = process.env.APPLE_SERVICE_ID || process.env.APPLE_CLIENT_ID;
  if (!audience) {
    throw new Error("APPLE_SERVICE_ID or APPLE_CLIENT_ID must be configured");
  }
  const { payload } = await jwtVerify(idToken, APPLE_JWKS, {
    issuer: "https://appleid.apple.com",
    audience,
  });
  return {
    providerUserId: payload.sub,
    email: normalizeEmail(typeof payload.email === "string" ? payload.email : ""),
    name: null,
  };
}

function fallbackProfile(provider, payload) {
  if (!localFallbackAllowed()) {
    throw new Error(`${provider} authentication payload is incomplete`);
  }
  const providerUserId = payload.providerUserId?.trim();
  if (!providerUserId) throw new Error(`${provider} providerUserId is required`);
  return {
    providerUserId,
    email: normalizeEmail(payload.email),
    name: payload.name?.trim() || null,
  };
}

export async function resolveSocialProfile(provider, payload) {
  switch (provider) {
    case "GOOGLE":
      if (payload.idToken) return googleProfileFromIdToken(payload.idToken);
      if (payload.accessToken) return googleProfileFromAccessToken(payload.accessToken);
      return fallbackProfile("Google", payload);
    case "FACEBOOK":
      if (payload.accessToken) return facebookProfileFromAccessToken(payload.accessToken);
      return fallbackProfile("Facebook", payload);
    case "APPLE":
      if (payload.idToken) {
        const profile = await appleProfileFromIdToken(payload.idToken);
        return {
          ...profile,
          email: profile.email || normalizeEmail(payload.email),
          name: payload.name?.trim() || null,
        };
      }
      return fallbackProfile("Apple", payload);
    default:
      throw new Error("Unsupported provider");
  }
}
