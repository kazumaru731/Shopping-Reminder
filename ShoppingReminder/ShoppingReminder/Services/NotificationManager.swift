import Foundation
import UserNotifications
import Supabase

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("通知許可取得成功")
            } else if let error = error {
                print("通知許可取得失敗: \(error.localizedDescription)")
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
            
            print("通知同期開始: リスト\(lists.count)件, アイテム\(items.count)件")
            
            // 2. 現在の予約を一旦クリア
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            
            // 3. タイミングごとにアイテムをグルーピング
            // Key: タイミング（type-time-date/weekday）, Value: アイテム名のセット
            var groupedReminders: [String: Set<String>] = [:]
            
            // 各アイテムごとに有効な設定を評価してグルーピング
            for item in items {
                // アイテム自身の設定を優先、なければリストの設定を使用
                let list = lists.first(where: { $0.id == item.listId })
                let effectiveInterval = item.reminderInterval ?? list?.reminderInterval
                let effectiveTargets = item.reminderTargets ?? list?.reminderTargets
                
                guard let interval = effectiveInterval, interval.type != "none" else { continue }
                
                // 自分がターゲットに含まれているか確認
                if let targets = effectiveTargets, let userId = currentUserId {
                    guard targets.contains(userId) else { continue }
                }
                
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
                    print("通知予約成功: \(key)")
                    scheduledCount += 1
                }
            }
            
            print("通知同期完了: \(scheduledCount)件の通知を予約しました。")
            
        } catch {
            print("通知同期エラー: \(error)")
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
}
