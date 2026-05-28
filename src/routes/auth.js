import { Prisma } from "@prisma/client";
import { Resend } from "resend";
import {
  buildOAuthStartUrl,
  exchangeOAuthCode,
  generateNumericCode,
  hashPassword,
  hashValue,
  issueAccessToken,
  normalizeAuthProvider,
  normalizeEmail,
  oauthCallbackRedirect,
  passwordResetExpiry,
  passwordResetMinutes,
  providerFromSlug,
  resolveSocialProfile,
  sanitizeUser,
  verifyOAuthState,
  verifyPassword,
} from "../lib/auth.js";
import { termsAcceptanceFromPayload } from "../lib/legal.js";

async function fetchUserWithMemberships(db, id) {
  const user = await db.user.findUnique({
    where: { id },
    include: {
      memberships: { include: { circle: true } },
      identities: true,
    },
  });
  if (!user) return sanitizeUser(user);
  const pendingInvites = await db.invitation.findMany({
    where: {
      email: user.email,
      status: "PENDING",
    },
    include: {
      circle: { select: { id: true, name: true, recipientName: true, archiveAfterDays: true } },
      invitedBy: { select: { id: true, name: true, email: true } },
    },
    orderBy: { createdAt: "desc" },
  });
  return sanitizeUser({ ...user, pendingInvites });
}

async function authResponse(db, method, userId) {
  const user = await fetchUserWithMemberships(db, userId);
  return {
    method,
    accessToken: await issueAccessToken(user),
    user,
  };
}

export default async function authRoutes(app) {
  const db = app.db;
  const resend = process.env.RESEND_API_KEY ? new Resend(process.env.RESEND_API_KEY) : null;

  async function handleOAuthCallback(req, reply) {
    let provider;
    let state;
    let code;
    let upstreamError;
    let user;

    try {
      provider = providerFromSlug(req.params.provider);
      state = req.body?.state ?? req.query?.state;
      code = req.body?.code ?? req.query?.code;
      upstreamError = req.body?.error ?? req.query?.error;
      user = req.body?.user ?? req.query?.user;

      const verifiedState = verifyOAuthState(state);
      const callbackScheme = verifiedState.callbackScheme;

      if (verifiedState.provider !== provider) {
        throw new Error("OAuth provider mismatch");
      }

      if (upstreamError) {
        return reply.redirect(
          oauthCallbackRedirect({
            callbackScheme,
            provider,
            error: `${provider} sign-in was cancelled or denied.`,
          })
        );
      }

      if (!code) {
        return reply.redirect(
          oauthCallbackRedirect({
            callbackScheme,
            provider,
            error: `${provider} did not return an authorization code.`,
          })
        );
      }

      const redirectUri = `${process.env.PUBLIC_API_BASE_URL?.replace(/\/+$/, "") || `${req.protocol || req.headers["x-forwarded-proto"] || "http"}://${req.headers["x-forwarded-host"] || req.headers.host}`}/auth/oauth/${provider.toLowerCase()}/callback`;
      const payload = await exchangeOAuthCode(provider, { code, redirectUri, user });
      return reply.redirect(oauthCallbackRedirect({ callbackScheme, provider, payload }));
    } catch (error) {
      const callbackScheme = (() => {
        try {
          return state ? verifyOAuthState(state).callbackScheme : "careloop";
        } catch {
          return "careloop";
        }
      })();
      return reply.redirect(
        oauthCallbackRedirect({
          callbackScheme,
          provider: provider || "OAUTH",
          error: error.message || "Authentication failed",
        })
      );
    }
  }

  app.get("/auth/oauth/:provider/start", { config: { public: true } }, async (req, reply) => {
    try {
      const provider = providerFromSlug(req.params.provider);
      const callbackScheme = req.query?.callback_scheme?.trim() || "careloop";
      const url = buildOAuthStartUrl(provider, req, callbackScheme);
      return reply.redirect(url.toString());
    } catch (error) {
      const callbackScheme = req.query?.callback_scheme?.trim() || "careloop";
      return reply.redirect(
        oauthCallbackRedirect({
          callbackScheme,
          provider: req.params.provider?.toUpperCase() || "OAUTH",
          error: error.message || "Authentication is not available",
        })
      );
    }
  });

  app.get("/auth/oauth/:provider/callback", { config: { public: true } }, handleOAuthCallback);
  app.post("/auth/oauth/:provider/callback", { config: { public: true } }, handleOAuthCallback);

  app.post("/auth/signup", { config: { public: true } }, async (req, reply) => {
    const { email, name, password, phone } = req.body ?? {};
    const normalizedEmail = normalizeEmail(email);
    if (!normalizedEmail || !name?.trim() || !password || password.trim().length < 8) {
      return reply.code(400).send({ error: "name, email, and password (min 8 chars) are required" });
    }
    const termsAcceptance = termsAcceptanceFromPayload(req.body);
    if (!termsAcceptance) {
      return reply.code(400).send({ error: "Terms and conditions must be accepted before creating an account" });
    }

    try {
      const user = await db.user.create({
        data: {
          email: normalizedEmail,
          name: name.trim(),
          phone: phone?.trim() || null,
          passwordHash: hashPassword(password),
          ...termsAcceptance,
        },
      });
      return reply.code(201).send(await authResponse(db, "PASSWORD", user.id));
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002") {
        return reply.code(409).send({ error: "Email already exists" });
      }
      throw err;
    }
  });

  app.post("/auth/login", { config: { public: true } }, async (req, reply) => {
    const { email, password } = req.body ?? {};
    const normalizedEmail = normalizeEmail(email);
    if (!normalizedEmail || !password) {
      return reply.code(400).send({ error: "email and password are required" });
    }

    const user = await db.user.findUnique({ where: { email: normalizedEmail } });
    if (!user?.passwordHash || !verifyPassword(password, user.passwordHash)) {
      return reply.code(401).send({ error: "Invalid email or password" });
    }

    return reply.send(await authResponse(db, "PASSWORD", user.id));
  });

  app.post("/auth/social", { config: { public: true } }, async (req, reply) => {
    const { provider, idToken, accessToken, email, name, providerUserId } = req.body ?? {};
    const normalizedProvider = normalizeAuthProvider(provider);
    if (!normalizedProvider) {
      return reply.code(400).send({ error: "provider must be GOOGLE, FACEBOOK, or APPLE" });
    }

    let resolved;
    try {
      resolved = await resolveSocialProfile(normalizedProvider, {
        idToken,
        accessToken,
        email,
        name,
        providerUserId,
      });
    } catch (error) {
      return reply.code(401).send({ error: error.message });
    }

    if (!resolved.email) {
      const existingIdentity = await db.authIdentity.findUnique({
        where: {
          provider_providerUserId: {
            provider: normalizedProvider,
            providerUserId: resolved.providerUserId,
          },
        },
      });
      if (!existingIdentity) {
        return reply.code(400).send({ error: "Provider did not return an email for first-time account creation" });
      }
      return reply.send(await authResponse(db, normalizedProvider, existingIdentity.userId));
    }

    const identity = await db.authIdentity.findUnique({
      where: {
        provider_providerUserId: {
          provider: normalizedProvider,
          providerUserId: resolved.providerUserId,
        },
      },
    });

    let userId = identity?.userId;

    if (!userId) {
      const existingUser = await db.user.findUnique({ where: { email: resolved.email } });
      if (existingUser) {
        userId = existingUser.id;
      } else {
        const termsAcceptance = termsAcceptanceFromPayload(req.body);
        if (!termsAcceptance) {
          return reply.code(400).send({ error: "Terms and conditions must be accepted before creating an account" });
        }
        const created = await db.user.create({
          data: {
            email: resolved.email,
            name: resolved.name || resolved.email.split("@")[0],
            ...termsAcceptance,
          },
        });
        userId = created.id;
      }
    }

    await db.authIdentity.upsert({
      where: {
        provider_providerUserId: {
          provider: normalizedProvider,
          providerUserId: resolved.providerUserId,
        },
      },
      update: {
        providerEmail: resolved.email || null,
        providerName: resolved.name || null,
        userId,
      },
      create: {
        provider: normalizedProvider,
        providerUserId: resolved.providerUserId,
        providerEmail: resolved.email || null,
        providerName: resolved.name || null,
        userId,
      },
    });

    return reply.send(await authResponse(db, normalizedProvider, userId));
  });

  app.post("/auth/logout", async (req, reply) => {
    await db.user.update({
      where: { id: req.userId },
      data: { authVersion: { increment: 1 } },
    });
    return reply.send({ loggedOut: true });
  });

  app.post("/auth/forgot-password/request", { config: { public: true } }, async (req, reply) => {
    const { email } = req.body ?? {};
    const normalizedEmail = normalizeEmail(email);
    if (!normalizedEmail) return reply.code(400).send({ error: "email is required" });

    const user = await db.user.findUnique({ where: { email: normalizedEmail } });
    if (!user) {
      return reply.send({ sent: true, expiresInMinutes: passwordResetMinutes() });
    }

    await db.passwordResetCode.updateMany({
      where: { userId: user.id, consumedAt: null },
      data: { consumedAt: new Date() },
    });

    const code = generateNumericCode(6);
    await db.passwordResetCode.create({
      data: {
        userId: user.id,
        codeHash: hashValue(code),
        expiresAt: passwordResetExpiry(),
      },
    });

    if (resend && user.email) {
      await resend.emails.send({
        from: "CareLoop <care@updates.careloop.app>",
        to: user.email,
        subject: "Your CareLoop password reset code",
        html: `<p>Your CareLoop reset code is <strong>${code}</strong>.</p><p>It expires in ${passwordResetMinutes()} minutes.</p>`,
      });
    }

    return reply.send({
      sent: true,
      expiresInMinutes: passwordResetMinutes(),
      debugCode: resend || process.env.NODE_ENV === "production" ? undefined : code,
    });
  });

  app.post("/auth/forgot-password/verify", { config: { public: true } }, async (req, reply) => {
    const { email, code } = req.body ?? {};
    const normalizedEmail = normalizeEmail(email);
    if (!normalizedEmail || !code) {
      return reply.code(400).send({ error: "email and code are required" });
    }

    const user = await db.user.findUnique({ where: { email: normalizedEmail } });
    if (!user) return reply.code(404).send({ error: "Account not found" });

    const reset = await db.passwordResetCode.findFirst({
      where: {
        userId: user.id,
        consumedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: "desc" },
    });

    if (!reset || reset.codeHash !== hashValue(code)) {
      return reply.code(401).send({ error: "Invalid or expired code" });
    }

    return reply.send({ verified: true });
  });

  app.post("/auth/forgot-password/reset", { config: { public: true } }, async (req, reply) => {
    const { email, code, password } = req.body ?? {};
    const normalizedEmail = normalizeEmail(email);
    if (!normalizedEmail || !code || !password || password.trim().length < 8) {
      return reply.code(400).send({ error: "email, code, and password (min 8 chars) are required" });
    }

    const user = await db.user.findUnique({ where: { email: normalizedEmail } });
    if (!user) return reply.code(404).send({ error: "Account not found" });

    const reset = await db.passwordResetCode.findFirst({
      where: {
        userId: user.id,
        consumedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: "desc" },
    });

    if (!reset || reset.codeHash !== hashValue(code)) {
      return reply.code(401).send({ error: "Invalid or expired code" });
    }

    await db.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: user.id },
        data: {
          passwordHash: hashPassword(password),
          authVersion: { increment: 1 },
        },
      });
      await tx.passwordResetCode.updateMany({
        where: { userId: user.id, consumedAt: null },
        data: { consumedAt: new Date() },
      });
    });

    return reply.send({ reset: true });
  });
}
