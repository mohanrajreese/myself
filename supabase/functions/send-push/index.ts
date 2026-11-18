// Sends a data-only FCM message to one user's devices (PRD §5.15I).
// Server-side only: callers must present the service-role key (a database
// webhook or a scheduled job). The payload is {type, id} - never health data.
//
// Body: {"user_id": "<uuid>", "type": "account_security" | "sync_problem" | "backup_status", "id"?: "<opaque>"}
// Secrets: FIREBASE_SERVICE_ACCOUNT (the JSON key of a service account with
// the Firebase Cloud Messaging API enabled).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { accessToken } from "../_shared/google_auth.ts";

const TYPES: Record<string, string> = {
  account_security: "account",
  sync_problem: "sync_problems",
  backup_status: "backup_status",
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response(null, { status: 405 });
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (req.headers.get("Authorization") !== `Bearer ${serviceKey}`) {
    return json({ error: "forbidden" }, 403);
  }
  const body = await req.json().catch(() => null);
  const userId = body?.user_id;
  const type = body?.type;
  const id = typeof body?.id === "string" ? body.id.slice(0, 64) : undefined;
  if (typeof userId !== "string" || !(type in TYPES)) return json({ error: "bad_request" }, 400);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);
  const { data: tokens, error } = await admin
    .from("device_notification_tokens")
    .select("id, fcm_token, preferences")
    .eq("user_id", userId)
    .is("revoked_at", null);
  if (error) return json({ error: "lookup_failed" }, 500);

  const wanted = (tokens ?? []).filter((t) => t.preferences?.[TYPES[type]] !== false);
  if (wanted.length === 0) return json({ sent: 0 }, 200);

  const account = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
  const bearer = await accessToken(account, "https://www.googleapis.com/auth/firebase.messaging");
  const endpoint = `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

  let sent = 0;
  for (const t of wanted) {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: t.fcm_token,
          data: id ? { type, id } : { type },
          android: { priority: "normal" },
        },
      }),
    });
    if (res.ok) {
      sent++;
    } else if (res.status === 404 || res.status === 400) {
      // UNREGISTERED or INVALID_ARGUMENT: the token is dead.
      await admin.from("device_notification_tokens").update({ revoked_at: new Date().toISOString() }).eq("id", t.id);
    }
  }
  return json({ sent }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
