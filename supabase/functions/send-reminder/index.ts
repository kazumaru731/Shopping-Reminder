import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // 現在時刻を取得 (UTC)
  // ユーザーのタイムゾーンを考慮する場合、本来はオフセット調整が必要
  const now = new Date()
  const currentHour = now.getUTCHours() + 9 // JSTに合わせる (+9)
  const currentMinute = now.getUTCMinutes()
  const currentTimeStr = `${String(currentHour % 24).padStart(2, '0')}:${String(currentMinute).padStart(2, '0')}`
  const currentDay = now.getUTCDay() + 1 // 1:日, ..., 7:土

  console.log(`Checking reminders for: ${currentTimeStr}, Day: ${currentDay}`)

  // 1. リマインド設定があるリストを取得
  const { data: lists, error } = await supabase
    .from('lists')
    .select('id, name, reminder_interval, reminder_targets')
    .not('reminder_interval', 'is', null)

  if (error) {
    console.error("Error fetching lists:", error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  const notificationsToSend = []

  // 2. 判定ロジック
  for (const list of lists) {
    const interval = list.reminder_interval
    if (!interval || interval.type === 'none') continue

    let shouldNotify = false

    // 時間の比較 (HH:mm)
    if (interval.time === currentTimeStr) {
      if (interval.type === 'daily' || interval.type === 'once') {
        shouldNotify = true
      } else if (interval.type === 'weekly' && interval.weekday === currentDay) {
        shouldNotify = true
      }
    }

    if (shouldNotify) {
      notificationsToSend.push({
        listId: list.id,
        listName: list.name,
        targets: list.reminder_targets || []
      })
    }
  }

  // 3. 通知送信処理 (現在はログ出力のみ。APNs/FCM設定後にここを実装)
  console.log(`Found ${notificationsToSend.length} lists to notify.`)
  
  for (const notification of notificationsToSend) {
    console.log(`Sending notification for "${notification.listName}" to users: ${notification.targets.join(', ')}`)
    
    // 【ここにプッシュ通知送信ロジックを実装】
    // 例: FCMのAPIを叩く、または profiles テーブルからデバイストークンを取得して APNs に送る
  }

  return new Response(JSON.stringify({ 
    message: "Scan completed", 
    processed: notificationsToSend.length 
  }), { status: 200 })
})
