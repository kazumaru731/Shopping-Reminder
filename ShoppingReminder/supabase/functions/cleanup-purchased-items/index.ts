import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// 購入済みアイテムの自動クリーンアップ
// Supabaseダッシュボード > Edge Functions > Schedule から毎日実行するよう設定する
// 推奨スケジュール: 0 3 * * * (毎日 UTC 3時 = JST 正午)
Deno.serve(async (req) => {
  // cronトリガー以外からの呼び出しは許可しない
  // （Authorization ヘッダーによる保護をSupabase側が担保する）
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      getSupabaseAdminKey()
    )

    const retentionDays = 3
    const cutoffDate = new Date(
      Date.now() - retentionDays * 24 * 60 * 60 * 1000
    ).toISOString()

    // 削除前に対象アイテムの画像URLを取得（Storage連動削除のため）
    const { data: targetItems, error: fetchError } = await supabase
      .from("items")
      .select("id, image_url")
      .eq("is_purchased", true)
      .lt("updated_at", cutoffDate)

    if (fetchError) {
      throw new Error("Failed to fetch target items")
    }

    const itemCount = targetItems?.length ?? 0
    console.log(`[Cleanup] 削除対象: ${itemCount}件 (${retentionDays}日以上前に購入済み)`)

    if (itemCount === 0) {
      return new Response(JSON.stringify({ deleted: 0, images_removed: 0 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      })
    }

    // Storage上の画像を先に削除（アイテム削除後はimage_urlが取れなくなるため）
    const imagePaths = (targetItems ?? [])
      .map((item) => extractStoragePath(item.image_url))
      .filter((path): path is string => path !== null)

    let removedImageCount = 0
    if (imagePaths.length > 0) {
      const { error: storageError } = await supabase.storage
        .from("item-images")
        .remove(imagePaths)

      if (storageError) {
        // 画像削除の失敗はアイテム削除をブロックしない（孤児ファイルは許容）
        console.warn("[Cleanup] Storage削除の一部失敗")
      } else {
        removedImageCount = imagePaths.length
        console.log(`[Cleanup] Storage画像を${removedImageCount}件削除`)
      }
    }

    // アイテムを一括削除
    const targetIds = (targetItems ?? []).map((item) => item.id)
    const { error: deleteError, count } = await supabase
      .from("items")
      .delete({ count: "exact" })
      .in("id", targetIds)

    if (deleteError) {
      throw new Error("Failed to delete items")
    }

    console.log(`[Cleanup] 完了: アイテム${count}件削除, 画像${removedImageCount}件削除`)

    return new Response(
      JSON.stringify({ deleted: count, images_removed: removedImageCount }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    )
  } catch {
    console.error("[Cleanup] 致命的エラー")
    return new Response(JSON.stringify({ error: "Internal Server Error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    })
  }
})

// Supabase Storage公開URLからバケット内パスを抽出する
// URL形式: .../storage/v1/object/public/item-images/{path}
function extractStoragePath(imageUrl: string | null): string | null {
  if (!imageUrl) return null
  try {
    const url = new URL(imageUrl)
    const marker = "/object/public/item-images/"
    const idx = url.pathname.indexOf(marker)
    if (idx === -1) return null
    return url.pathname.slice(idx + marker.length)
  } catch {
    return null
  }
}

function getSupabaseAdminKey(): string {
  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS")
  if (secretKeys) {
    try {
      const parsed = JSON.parse(secretKeys) as Record<string, string>
      const defaultKey = parsed.default?.trim()
      if (defaultKey) return defaultKey
    } catch {
      console.warn("[Cleanup] Failed to parse SUPABASE_SECRET_KEYS")
    }
  }

  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? ""
}
