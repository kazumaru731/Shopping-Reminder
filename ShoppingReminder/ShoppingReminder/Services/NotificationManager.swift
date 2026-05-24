import Foundation
import UserNotifications
import UIKit
import Supabase

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    // プッシュ通知の許可リクエスト
    func requestPushPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                #if DEBUG
                print("[Notification] Push permission granted")
                #endif
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else if let error = error {
                // 許可が拒否された場合、ユーザーは設定アプリから手動で変更する必要がある。
                // ここでUIアラートを出すと App Review ガイドラインに触れる可能性があるため、
                // ログに記録するに留め、UI側でバッジなどで誘導する設計とする。
                #if DEBUG
                print("[Notification] Permission denied: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    // デバイストークンの登録
    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        // ログイン完了のタイムラグ対策として、一度端末内に保存しておく
        UserDefaults.standard.set(token, forKey: "apns_device_token")
        
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        Task {
            // すでにログイン済みなら即座に保存
            if SupabaseService.shared.currentUser != nil {
                await SupabaseService.shared.savePushToken(token: token, deviceId: deviceId)
            }
        }
    }
    
    // 全リマインドの同期と統合
    func syncAllNotifications() async {
        do {
            // 1. 全リストと全未購入アイテムを取得
            let lists = try await SupabaseService.shared.fetchAllLists()
            let items = try await SupabaseService.shared.fetchAllUnpurchasedItems()
            let currentUserId = SupabaseService.shared.currentUser?.id
            
            #if DEBUG
            print("[Notification] 同期開始: リスト\(lists.count)件, アイテム\(items.count)件")
            #endif
            
            // 2. 現在の予約（remind-で始まるもの）を一旦クリア
            let center = UNUserNotificationCenter.current()
            let pendingRequests = await center.pendingNotificationRequests()
            let remindIds = pendingRequests.map { $0.identifier }.filter { $0.hasPrefix("remind-") }
            
            if !remindIds.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: remindIds)
                // 削除処理が非同期でシステムに反映されるのを確実に待つための極小ウェイト（iOSのレースコンディション対策）
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            }
            
            // 3. タイミングごとにアイテムをグルーピング
            // Key: タイミング（type-time-date/weekday）, Value: アイテム名のセット
            var groupedReminders: [String: Set<String>] = [:]
            
            // 各アイテムごとに有効な設定を評価してグルーピング
            for item in items {
                var effectiveInterval: NotificationInterval?
                var isTargeted = false
                
                // 1. 自分専用のカスタム設定があるか確認 (最優先)
                let personalKey = "personal_reminder_\(item.id.uuidString)"
                if let data = UserDefaults.standard.data(forKey: personalKey),
                   let personalInterval = try? JSONDecoder().decode(NotificationInterval.self, from: data) {
                    effectiveInterval = personalInterval
                    isTargeted = personalInterval.type != "none"
                } else {
                    // 2. カスタム設定がない場合は共通設定を使用
                    let list = lists.first(where: { $0.id == item.listId })
                    effectiveInterval = item.reminderInterval ?? list?.reminderInterval
                    let effectiveTargets = item.reminderTargets ?? list?.reminderTargets
                    
                    if let interval = effectiveInterval, interval.type != "none",
                       let targets = effectiveTargets, let userId = currentUserId {
                        isTargeted = targets.contains(userId)
                    }
                }
                
                guard isTargeted, let interval = effectiveInterval else { continue }
                
                let key = generateTriggerKey(from: interval)
                var names = groupedReminders[key] ?? []
                names.insert(item.name)
                groupedReminders[key] = names
            }
            
            // 4. 各グループごとに通知を登録
            var scheduledCount = 0
            for (key, itemNames) in groupedReminders {
                let interval = decodeTriggerKey(key)
                let trigger = createTrigger(from: interval)
                
                if let trigger = trigger {
                    let content = UNMutableNotificationContent()
                    content.title = "お買い物リマインダー"
                    
                    let sortedNames = Array(itemNames).sorted()
                    let displayLimit = 5
                    var body = "買うもの: " + sortedNames.prefix(displayLimit).joined(separator: ", ")
                    if sortedNames.count > displayLimit {
                        body += " ほか\(sortedNames.count - displayLimit)件"
                    }
                    content.body = body
                    content.sound = .default
                    
                    let request = UNNotificationRequest(identifier: "remind-\(key)", content: content, trigger: trigger)
                    try await UNUserNotificationCenter.current().add(request)
                    scheduledCount += 1
                }
            }
            
            #if DEBUG
            print("[Notification] 同期完了: \(scheduledCount)件の通知を予約")
            #endif
            
        } catch {
            // 通知同期の失敗はユーザー体験には直結しないが、
            // 原因追跡のためリリースビルドでもエラーは記録する
            #if DEBUG
            print("[Notification] 同期エラー: \(error.localizedDescription)")
            #endif
        }
    }
    
    // --- ユーティリティ ---
    
    private func generateTriggerKey(from interval: NotificationInterval) -> String {
        let type = interval.type
        let time = interval.time ?? "00:00"
        let extra = interval.date ?? (interval.weekday != nil ? String(interval.weekday!) : "")
        return "\(type)-\(time)-\(extra)"
    }
    
    private func decodeTriggerKey(_ key: String) -> NotificationInterval {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        let type = String(parts[0])
        let time = String(parts[1])
        
        // 3つ目以降のパーツをすべて結合してextraを復元（日付にハイフンが含まれるため）
        let extra = parts.count > 2 ? parts.dropFirst(2).joined(separator: "-") : nil
        
        var interval = NotificationInterval(type: type, time: time)
        if type == "once" {
            interval.date = extra
        } else if type == "weekly" {
            interval.weekday = Int(extra ?? "")
        }
        return interval
    }
    
    private func createTrigger(from interval: NotificationInterval) -> UNNotificationTrigger? {
        guard let timeString = interval.time else { return nil }
        let parts = timeString.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        
        if interval.type == "once", let dateStr = interval.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateStr) {
                let dateParts = Calendar.current.dateComponents([.year, .month, .day], from: date)
                components.year = dateParts.year
                components.month = dateParts.month
                components.day = dateParts.day
                return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
        } else if interval.type == "daily" {
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        } else if interval.type == "weekly", let weekday = interval.weekday {
            components.weekday = weekday
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }
        
        return nil
    }
    
    // 既存メソッドの互換性維持（または削除して差し替え）
    func syncNotifications(for lists: [ShoppingList]) {
        Task { await syncAllNotifications() }
    }
    
    func scheduleNotification(for list: ShoppingList) {
        Task { await syncAllNotifications() }
    }
    
    func cancelNotification(for list: ShoppingList) {
        Task { await syncAllNotifications() }
    }
    
    // 通知イベントの定義
    enum NotificationEvent: String {
        case groupCreate = "group_create"
        case groupLeave = "group_leave"
        case listAdd = "list_add"
        case listDelete = "list_delete"
        case itemAdd = "item_add"
        case itemDelete = "item_delete"
        case itemReserved = "item_reserved"
        case itemPurchased = "item_purchased"
        
        var storageKey: String {
            return "notify_\(self.rawValue)_enabled"
        }
    }
    
    // イベントごとの通知有効状態を確認
    func isEnabled(for event: NotificationEvent) -> Bool {
        // デフォルトはONにするため、値がない場合はtrueを返す
        if UserDefaults.standard.object(forKey: event.storageKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: event.storageKey)
    }
    
    // 即時通知を送信（リスト追加、アイテム追加、購入、予約などのイベント用）
    func sendImmediateNotification(title: String, body: String, event: NotificationEvent) {
        guard isEnabled(for: event) else {
            #if DEBUG
            print("[Notification] スキップ: イベント \(event.rawValue) は無効")
            #endif
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // 識別子をランダムにして通知が上書きされないようにする
        let request = UNNotificationRequest(
            identifier: "immediate-\(UUID().uuidString)",
            content: content,
            trigger: nil // nilを指定すると即時送信される
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                #if DEBUG
                print("[Notification] 即時通知送信失敗: \(error.localizedDescription)")
                #endif
            }
        }
    }
}
