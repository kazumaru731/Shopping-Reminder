import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

type JoinRequest = {
  code?: unknown
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 })
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
    const serviceRoleKey = getSupabaseAdminKey()

    if (!supabaseUrl || !serviceRoleKey) {
      console.error("[FindGroupForJoin] Missing Supabase environment")
      return new Response("Service unavailable", { status: 503 })
    }

    const token = getBearerToken(req)
    if (!token) {
      return new Response("Unauthorized", { status: 401 })
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    })

    const { data: userData, error: userError } = await supabase.auth.getUser(token)
    if (userError || !userData.user?.id) {
      return new Response("Unauthorized", { status: 401 })
    }

    const body = await req.json() as JoinRequest
    const code = typeof body.code === "string"
      ? body.code.trim()
      : ""

    if (!code) {
      return json({ group: null }, 200)
    }

    const group = await findGroup(supabase, code)

    return json({ group }, 200)
  } catch {
    console.error("[FindGroupForJoin] Request failed")
    return new Response("Internal Server Error", { status: 500 })
  }
})

async function findGroup(
  supabase: ReturnType<typeof createClient>,
  code: string,
) {
  const selectColumns = "id,name,invite_code,owner_id,created_at,allow_member_edit"

  if (isUuid(code)) {
    const { data, error } = await supabase
      .from("groups")
      .select(selectColumns)
      .eq("id", code)
      .limit(1)
      .maybeSingle()

    if (error) {
      throw new Error("group lookup failed")
    }

    if (data) {
      return data
    }
  }

  const { data, error } = await supabase
    .from("groups")
    .select(selectColumns)
    .eq("invite_code", code.toUpperCase())
    .limit(1)
    .maybeSingle()

  if (error) {
    throw new Error("group lookup failed")
  }

  return data ?? null
}

function getBearerToken(req: Request): string | null {
  const authorization = req.headers.get("Authorization") ?? ""
  const match = authorization.match(/^Bearer\s+(.+)$/i)
  const token = match?.[1]?.trim()

  if (!token || token.startsWith("sb_")) {
    return null
  }

  return token
}

function getSupabaseAdminKey(): string {
  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS")
  if (secretKeys) {
    try {
      const parsed = JSON.parse(secretKeys) as Record<string, string>
      const defaultKey = parsed.default?.trim()
      if (defaultKey) return defaultKey
    } catch {
      console.warn("[FindGroupForJoin] Failed to parse SUPABASE_SECRET_KEYS")
    }
  }

  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? ""
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
