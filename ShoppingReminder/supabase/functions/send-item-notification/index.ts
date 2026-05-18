import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import * as jose from 'https://deno.land/x/jose@v4.14.4/index.ts'

serve(async (req) => {
  try {
    const payload = await req.json()
    const { table, type, record, old_record } = payload

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    let title = ""
    let body = ""
    let groupId = ""
    
    // 操作を行ったユーザーIDを特定（通知対象から除外するため）
    let actorId = record?.planning_purchaser_id || record?.purchaser_id || record?.creator_id || record?.user_id || record?.owner_id || 
                  old_record?.planning_purchaser_id || old_record?.purchaser_id || old_record?.creator_id || old_record?.user_id || old_record?.owner_id

    // A. アイテムテーブルの処理
    if (table === 'items') {
      const item = type === 'DELETE' ? old_record : record
      const { data: listData } = await supabase.from('lists').select('group_id').eq('id', item.list_id).single()
      if (!listData) return new Response("List not found", { status: 200 })
      groupId = listData.group_id

      if (type === 'INSERT') {
        title = "アイテム追加"
        body = `「${item.name}」が追加されました。`
      } else if (type === 'DELETE') {
        title = "アイテム削除"
        body = `「${item.name}」が削除されました。`
      } else if (type === 'UPDATE') {
        if (!old_record.is_purchased && record.is_purchased) {
          title = "アイテム購入完了"
          body = `「${record.name}」が購入されました！`
          actorId = record.purchaser_id // 購入者を優先
        } else if (!old_record.planning_purchaser_id && record.planning_purchaser_id) {
          title = "アイテム予約中"
          body = `誰かが「${record.name}」を買おうとしています。`
          actorId = record.planning_purchaser_id // 予約者を優先
        } else if (old_record.planning_purchaser_id && !record.planning_purchaser_id) {
          title = "予約解除"
          body = `「${record.name}」の予約がキャンセルされました。`
          actorId = old_record.planning_purchaser_id // 予約解除した人を優先
        } else {
          return new Response("No target update", { status: 200 })
        }
      }
    } 
    // B. リストテーブルの処理
    else if (table === 'lists') {
      const list = type === 'DELETE' ? old_record : record
      groupId = list.group_id
      if (type === 'INSERT') {
        title = "新しいリスト"
        body = `リスト「${list.name}」が作成されました。`
      } else if (type === 'DELETE') {
        title = "リスト削除"
        body = `リスト「${list.name}」が削除されました。`
      }
    }
    // C. グループメンバーの処理（参加・退出）
    else if (table === 'group_members') {
      const member = type === 'DELETE' ? old_record : record
      groupId = member.group_id
      
      const { data: profile } = await supabase.from('profiles').select('display_name').eq('id', member.user_id).single()
      const userName = profile?.display_name || "新しいユーザー"

      if (type === 'INSERT') {
        title = "メンバー参加"
        body = `${userName}さんがグループに参加しました。`
      } else if (type === 'DELETE') {
        title = "メンバー退出"
        body = `${userName}さんがグループから退出しました。`
      }
    }

    if (!groupId || !title) {
      console.log(`[Skip] groupId: ${groupId}, title: ${title}`)
      return new Response("Skipped", { status: 200 })
    }

    // 1. 通知対象のメンバーを特定（操作者本人を除外）
    const { data: members, error: memberError } = await supabase.from('group_members').select('user_id').eq('group_id', groupId)
    if (memberError) throw new Error(`Failed to fetch members: ${memberError.message}`)
    
    const userIds = members?.map(m => m.user_id).filter(id => id !== actorId) ?? []
    console.log(`[Info] Target userIds: ${JSON.stringify(userIds)} (Actor: ${actorId})`)

    if (userIds.length === 0) return new Response("No recipients", { status: 200 })

    // 2. プッシュトークン取得
    const { data: tokens, error: tokenError } = await supabase.from('push_tokens').select('token, user_id').in('user_id', userIds)
    if (tokenError) throw new Error(`Failed to fetch tokens: ${tokenError.message}`)
    
    if (!tokens || tokens.length === 0) {
      console.log(`[Info] No tokens found for users: ${userIds.join(', ')}`)
      return new Response("No tokens", { status: 200 })
    }
    console.log(`[Info] Found ${tokens.length} tokens.`)

    // 3. APNs認証準備
    const keyID = Deno.env.get('APNS_KEY_ID')?.trim()
    const teamID = Deno.env.get('APNS_TEAM_ID')?.trim()
    const bundleID = Deno.env.get('APNS_BUNDLE_ID')?.trim()
    // \n（エスケープ文字列）と実際の改行コード、両方に対応して正規化する
    const rawKey = Deno.env.get('APNS_P8_PRIVATE_KEY') ?? ''
    const privateKeyString = rawKey
      .replace(/\\n/g, '\n')   // エスケープされた \n を実際の改行に変換
      .trim()

    if (!keyID || !teamID || !bundleID || !privateKeyString) {
      throw new Error(`Missing APNs environment variables: keyID=${!!keyID}, teamID=${!!teamID}, bundleID=${!!bundleID}, key=${!!privateKeyString}`)
    }

    console.log(`[Debug] APNs config: keyID=${keyID}, teamID=${teamID}, bundleID=${bundleID}, keyLength=${privateKeyString.length}`)

    const ecPrivateKey = await jose.importPKCS8(privateKeyString, 'ES256')
    const jwt = await new jose.SignJWT({ iss: teamID, iat: Math.floor(Date.now() / 1000) })
      .setProtectedHeader({ alg: 'ES256', kid: keyID })
      .sign(ecPrivateKey)

    // 4. 送信処理
    // APNS_ENVIRONMENT が "development" の場合のみ開発環境に送信。
    // 未設定またはその他の値は本番環境のみに送信する（リリース後のデフォルト動作）。
    const apnsEnvironment = Deno.env.get('APNS_ENVIRONMENT')?.trim() ?? 'production'
    const apnsBaseUrl = apnsEnvironment === 'development'
      ? 'https://api.development.push.apple.com'
      : 'https://api.push.apple.com'

    const results = await Promise.all(tokens.map(async (t) => {
      const deviceToken = t.token
      const url = `${apnsBaseUrl}/3/device/${deviceToken}`
      
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: { 
            'apns-topic': bundleID, 
            'authorization': `bearer ${jwt}`, 
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'apns-expiration': '0'
          },
          body: JSON.stringify({ 
            aps: { 
              alert: { title, body }, 
              sound: "default",
              "mutable-content": 1 
            } 
          })
        })
        
        if (res.ok) {
          console.log(`[APNs] 送信成功 (env: ${apnsEnvironment}, user: ${t.user_id}, token: ...${deviceToken.slice(-6)})`)
          return { success: true }
        } else {
          const errText = await res.text()
          console.log(`[APNs] 送信失敗 (status: ${res.status}): ${errText} (user: ${t.user_id}, token: ...${deviceToken.slice(-6)})`)
          return { success: false, error: errText, status: res.status }
        }
      } catch (e) {
        console.error(`[APNs] ネットワークエラー: ${e.message}`)
        return { success: false, error: e.message }
      }
    }))

    return new Response(JSON.stringify({ 
      message: "Processing completed", 
      recipients: userIds.length,
      tokens: tokens.length,
      details: results
    }), { status: 200 })
  } catch (error) {
    console.error("Critical Error:", error.message)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})