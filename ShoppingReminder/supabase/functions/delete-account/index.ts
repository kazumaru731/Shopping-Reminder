import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

type ItemImage = {
  image_url: string | null
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 })
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
    const serviceRoleKey = getSupabaseAdminKey()

    if (!supabaseUrl || !serviceRoleKey) {
      console.error("[DeleteAccount] Missing Supabase environment")
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
    const userId = userData.user?.id

    if (userError || !userId) {
      return new Response("Unauthorized", { status: 401 })
    }

    const imagePaths = await collectImagePathsForDeletion(supabase, userId)
    if (imagePaths.length > 0) {
      const { error: storageError } = await supabase.storage
        .from("item-images")
        .remove(imagePaths)

      if (storageError) {
        console.warn("[DeleteAccount] Storage cleanup partially failed")
      }
    }

    await throwOnError(
      supabase
        .from("items")
        .update({ purchaser_id: null })
        .eq("purchaser_id", userId),
      "clear purchaser references",
    )

    await throwOnError(
      supabase
        .from("items")
        .update({ planning_purchaser_id: null })
        .eq("planning_purchaser_id", userId),
      "clear planning purchaser references",
    )

    await throwOnError(
      supabase
        .from("items")
        .delete()
        .eq("creator_id", userId),
      "delete created items",
    )

    await throwOnError(
      supabase
        .from("push_tokens")
        .delete()
        .eq("user_id", userId),
      "delete push tokens",
    )

    await throwOnError(
      supabase
        .from("group_members")
        .delete()
        .eq("user_id", userId),
      "delete group memberships",
    )

    await throwOnError(
      supabase
        .from("profiles")
        .delete()
        .eq("id", userId),
      "delete profile",
    )

    const { error: deleteUserError } = await supabase.auth.admin.deleteUser(userId)
    if (deleteUserError) {
      throw new Error("delete auth user failed")
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    })
  } catch {
    console.error("[DeleteAccount] Request failed")
    return new Response("Internal Server Error", { status: 500 })
  }
})

async function collectImagePathsForDeletion(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<string[]> {
  const ownedGroupIds = await selectIds(
    supabase
      .from("groups")
      .select("id")
      .eq("owner_id", userId),
  )

  const ownedListIds = new Set<string>()

  const directlyOwnedListIds = await selectIds(
    supabase
      .from("lists")
      .select("id")
      .eq("owner_id", userId),
  )

  for (const listId of directlyOwnedListIds) {
    ownedListIds.add(listId)
  }

  if (ownedGroupIds.length > 0) {
    const groupOwnedListIds = await selectIds(
      supabase
        .from("lists")
        .select("id")
        .in("group_id", ownedGroupIds),
    )

    for (const listId of groupOwnedListIds) {
      ownedListIds.add(listId)
    }
  }

  const imageUrls: Array<string | null> = []

  const { data: createdItems, error: createdError } = await supabase
    .from("items")
    .select("image_url")
    .eq("creator_id", userId)

  if (createdError) {
    throw new Error("created item lookup failed")
  }

  imageUrls.push(...((createdItems as ItemImage[] | null)?.map((item) => item.image_url) ?? []))

  const listIds = Array.from(ownedListIds)
  if (listIds.length > 0) {
    const { data: listItems, error: listItemError } = await supabase
      .from("items")
      .select("image_url")
      .in("list_id", listIds)

    if (listItemError) {
      throw new Error("owned list item lookup failed")
    }

    imageUrls.push(...((listItems as ItemImage[] | null)?.map((item) => item.image_url) ?? []))
  }

  return Array.from(
    new Set(
      imageUrls
        .map(extractStoragePath)
        .filter((path): path is string => path !== null),
    ),
  )
}

async function selectIds(query: PromiseLike<{ data: unknown; error: unknown }>): Promise<string[]> {
  const { data, error } = await query
  if (error) {
    throw new Error("id lookup failed")
  }

  return ((data as Array<{ id: string }> | null) ?? []).map((row) => row.id)
}

async function throwOnError(
  query: PromiseLike<{ error: unknown }>,
  operation: string,
) {
  const { error } = await query
  if (error) {
    throw new Error(`${operation} failed`)
  }
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
      console.warn("[DeleteAccount] Failed to parse SUPABASE_SECRET_KEYS")
    }
  }

  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? ""
}

function extractStoragePath(imageUrl: string | null): string | null {
  if (!imageUrl) return null

  try {
    const url = new URL(imageUrl)
    const marker = "/storage/v1/object/public/item-images/"
    const idx = url.pathname.indexOf(marker)
    if (idx === -1) return null
    return url.pathname.slice(idx + marker.length)
  } catch {
    return null
  }
}
