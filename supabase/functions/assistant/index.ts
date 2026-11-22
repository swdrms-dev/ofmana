// ofmana — assistant IA (réservé aux admins).
// La clé OpenAI reste côté serveur : secret OPENAI_API_KEY (Edge Functions > Secrets)
// ou, à défaut, secret « openai_api_key » dans Supabase Vault (lu via public.app_openai_key, réservé au serveur).
// Secrets facultatifs : OPENAI_MODEL (défaut gpt-4.1-mini), AI_DAILY_LIMIT (défaut 40 demandes / jour).
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const SYSTEM = `Tu es l'assistant d'une agence qui accompagne des créatrices de contenu sur OnlyFans.
Réponds en français, de façon concrète, structurée (titres courts, listes) et concise.
Règles impératives :
1. N'écris jamais de contenu sexuellement explicite : décris les idées de façon professionnelle (thème, format, mise en scène, angle marketing, prix).
2. Ne propose jamais de se faire passer pour la créatrice auprès des fans, ni de tromper ou manipuler les abonnés.
3. Les messages de prospection viennent de l'agence, la présentent clairement, sont respectueux, sans pression, sans promesse de gains chiffrée, et ne visent que des personnes majeures.
4. Appuie tes analyses uniquement sur les chiffres fournis ; si une donnée manque, dis-le simplement.`;

const TASKS: Record<string, string> = {
  ideas:
    "Propose 10 idées de contenus (posts, PPV, stories, lives, promos) adaptées à cette créatrice. Pour chacune : titre, format, pourquoi ça devrait marcher, prix conseillé si PPV. Évite de répéter ce qui a déjà été publié récemment. Termine par 3 conseils de planning.",
  analysis:
    "Analyse ces chiffres : tendance, points forts, points faibles, causes probables des hausses ou des baisses. Termine par 3 actions prioritaires et concrètes pour le mois prochain.",
  prospect:
    "Rédige un premier message privé Instagram de la part de l'agence pour proposer un accompagnement à cette personne, dans le ton demandé. Court, personnalisé à partir des infos fournies, honnête (l'agence se présente), respectueux, sans pression ni promesse chiffrée, et qui laisse la personne libre de ne pas répondre. Propose 2 variantes.",
  free: "Réponds à la question de l'agence.",
};

const pubKey = () => {
  try {
    const k = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
    if (k.default) return k.default as string;
  } catch (_) { /* ignore */ }
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
};

const secretKey = () => {
  try {
    const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    if (k.default) return k.default as string;
  } catch (_) { /* ignore */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
};

async function askOpenAI(key: string, model: string, user: string) {
  const reasoning = /^(gpt-5|o\d)/.test(model);
  const body: Record<string, unknown> = {
    model,
    messages: [{ role: "system", content: SYSTEM }, { role: "user", content: user }],
  };
  if (reasoning) { body.max_completion_tokens = 2500; body.reasoning_effort = "low"; }
  else { body.max_tokens = 1100; body.temperature = 0.8; }
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, j };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Non connecté" }, 401);

  // 1. Qui appelle ? On lit son rôle avec SA session (les règles RLS l'autorisent à lire son propre profil).
  const userDb = createClient(url, pubKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: u, error: ue } = await userDb.auth.getUser(token);
  if (ue || !u?.user) return json({ error: "Session expirée : reconnecte-toi" }, 401);
  const { data: prof, error: pe } = await userDb.from("profiles").select("role").eq("id", u.user.id).maybeSingle();
  if (pe) { console.error("profil", pe); return json({ error: "Lecture du profil impossible : " + pe.message }, 500); }
  if (prof?.role !== "admin") return json({ error: "Réservé aux admins" }, 403);

  // Client serveur (clé secrète) pour le quota et la clé OpenAI.
  const admin = createClient(url, secretKey(), { auth: { persistSession: false, autoRefreshToken: false } });

  // 2. Clé et quota journalier (protège le crédit OpenAI).
  let key = Deno.env.get("OPENAI_API_KEY") ?? "";
  let vaultErr = "";
  if (!key) {
    const { data: vk, error: ve } = await admin.rpc("app_openai_key");
    if (ve) { console.error("vault", ve); vaultErr = ve.message; }
    key = typeof vk === "string" ? vk.trim() : "";
  }
  if (!key) {
    return json({ error: vaultErr
      ? "Lecture de la clé OpenAI impossible : " + vaultErr
      : "Clé OpenAI manquante : enregistre-la dans Supabase (SQL Editor, voir SETUP.md) ou dans Edge Functions > Secrets (OPENAI_API_KEY)." }, 500);
  }
  const limit = Number(Deno.env.get("AI_DAILY_LIMIT") ?? 40);
  const since = new Date(); since.setUTCHours(0, 0, 0, 0);
  const { count, error: ce } = await admin.from("ai_usage").select("id", { count: "exact", head: true }).gte("created_at", since.toISOString());
  if (ce) console.error("quota", ce);
  const used = count ?? 0;
  if (used >= limit) {
    return json({ error: `Limite de ${limit} demandes par jour atteinte (protection de ton crédit OpenAI). Réessaie demain.` }, 429);
  }

  // 3. Demande.
  let body: { kind?: string; context?: unknown; prompt?: string };
  try { body = await req.json(); } catch (_) { return json({ error: "Requête invalide" }, 400); }
  const kind = TASKS[String(body.kind)] ? String(body.kind) : "free";
  const ctx = JSON.stringify(body.context ?? {}).slice(0, 12000);
  const extra = String(body.prompt ?? "").slice(0, 2000);
  const user = `${TASKS[kind]}\n\nDonnées (JSON) :\n${ctx}${extra ? `\n\nPrécisions de l'agence : ${extra}` : ""}`;

  let model = Deno.env.get("OPENAI_MODEL") || "gpt-4.1-mini";
  let res = await askOpenAI(key, model, user);
  if (!res.ok && res.status === 404 && model !== "gpt-5-mini") { model = "gpt-5-mini"; res = await askOpenAI(key, model, user); }
  if (!res.ok) {
    const msg = res.status === 401 ? "Clé OpenAI invalide : vérifie le secret OPENAI_API_KEY."
      : res.status === 429 ? "Crédit OpenAI épuisé ou trop de demandes : vérifie ton solde sur platform.openai.com."
      : (res.j?.error?.message ?? `Erreur OpenAI ${res.status}`);
    return json({ error: msg }, 502);
  }

  const text: string = res.j.choices?.[0]?.message?.content ?? "";
  const tokens: number = res.j.usage?.total_tokens ?? 0;
  const { error: ie } = await admin.from("ai_usage").insert({ user_id: u.user.id, kind, tokens });
  if (ie) console.error("usage", ie);
  return json({ text, tokens, model, remaining: Math.max(0, limit - used - 1), limit });
});
