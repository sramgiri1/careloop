export const ACTIVE_TERMS_VERSION = "careloop-terms-2026-05-28";

export function termsAcceptanceFromPayload(payload = {}) {
  if (payload.acceptedTerms !== true) return null;
  const version = typeof payload.termsVersion === "string" ? payload.termsVersion.trim() : "";
  if (version && version !== ACTIVE_TERMS_VERSION) return null;
  return {
    termsAcceptedAt: new Date(),
    termsAcceptedVersion: version || ACTIVE_TERMS_VERSION,
  };
}
