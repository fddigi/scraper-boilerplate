// Auth middleware: verifies the signed session token on every route it's
// applied to, otherwise responds 401. Applied to every route except POST /login.
//
// Uses `Authorization: Bearer <token>`, NOT a cookie. This was a deliberate
// correction, not the original design: a cookie-based session was tried
// first and failed in real browsers. GitHub Pages (the frontend) and this
// Worker (the API) live on two entirely different top-level domains, which
// makes the session cookie a THIRD-PARTY cookie from the browser's point of
// view. Chrome accepted it with `SameSite=None; Secure`, which masked the
// problem - but Safari's Intelligent Tracking Prevention blocks ALL
// third-party cookies by default regardless of SameSite, so login appeared
// to succeed for one instant (the response arrived) and then bounced straight
// back to the login page (the follow-up request had no cookie at all). A
// bearer token stored in localStorage and sent as a header has no such
// restriction in any browser. See SCRAPING_LESSONS.md - always test login in
// Safari specifically (or with cookies explicitly blocked), not just
// Chrome/curl, before considering auth verified.

import type { Context, Next } from "hono";
import { verifySessionToken } from "./auth";
import type { Env, Variables } from "./types";

export function parseBearerToken(header: string | null | undefined): string | null {
  if (!header || !header.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  return token || null;
}

export async function requireAuth(
  c: Context<{ Bindings: Env; Variables: Variables }>,
  next: Next,
) {
  const token = parseBearerToken(c.req.header("Authorization"));
  if (!token) {
    return c.json({ error: "unauthorized" }, 401);
  }

  const payload = await verifySessionToken(token, c.env.SESSION_HMAC_SECRET);
  if (!payload) {
    return c.json({ error: "unauthorized" }, 401);
  }

  c.set("session", payload);
  await next();
}
