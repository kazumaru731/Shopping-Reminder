import Foundation
import Supabase
import Combine
import WidgetKit

class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    // TODO: 実際のSupabaseプロジェクトのURLとキーに置き換えてください
    let client = SupabaseClient(
        supabaseURL: URL(string: "https://xhzvkjokpvrdwbiebitb.supabase.co")!,
        supabaseKey: "sb_publishable_l0rvlv5CpmjAAdOmz36mVw_Dd8it9yQ"
    )
    
    @Published var currentUser: User?
    
    private init() {
        // 現在のユーザーセッションを確認
        Task {
            self.currentUser = try? await client.auth.session.user
            
            // Authの状態変化を監視
            for await (_, session) in client.auth.authStateChanges {
                self.currentUser = session?.user
            }
        }
    }
    
    // 認証: サインアップ
    func signUp(email: String, password: String, displayName: String) async throws {
        try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
    }
    
    // 認証: サインイン
    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }
    
    // ログアウト
    func signOut() async throws {
        try await client.auth.signOut()
    }
    
    // --- グループ関連 ---
    
    // 参加しているグループ一覧を取得
    func fetchGroups() async throws -> [Group] {
        guard let userId = currentUser?.id else { return [] }
        
        // group_members を通じて自分が所属しているグループのIDを取得
        struct GroupIdResponse: Codable {
            let group_id: UUID
        }
        
        let response: [GroupIdResponse] = try await client
            .from("group_members")
            .select("group_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
            
        let groupIds = response.map { $0.group_id }
            
        if groupIds.isEmpty { return [] }
        
        return try await client
            .from("groups")
            .select()
            .in("id", values: groupIds)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    
    // グループ作成
    func createGroup(name: String) async throws -> Group {
        guard let userId = currentUser?.id else { throw NSError(domain: "Auth", code: 401) }
        
        // 招待コード生成 (6桁英数字)
        let inviteCode = String((0..<6).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        
        struct CreateGroupPayload: Encodable {
            let name: String
            let invite_code: String
            let owner_id: UUID
        }
        
        let payload = CreateGroupPayload(name: name, invite_code: inviteCode, owner_id: userId)
        
        let newGroup: Group = try await client
            .from("groups")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
            
        struct AddMemberPayload: Encodable {
            let group_id: UUID
            let user_id: UUID
            let role: String
        }
        
        // 作成者をメンバーに追加
        try await client
            .from("group_members")
            .insert(AddMemberPayload(group_id: newGroup.id, user_id: userId, role: "owner"))
            .execute()
            
        return newGroup
    }
    
    // コーフォからグループ情報を取得
    func getGroupByCode(code: String) async throws -> Group? {
        return try await client
            .from("groups")
            .select()
            .eq("invite_code", value: code.uppercased())
            .single()
            .execute()
            .value
    }
    
    // グループに参加
    func joinGroup(groupId: UUID) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct JoinPayload: Encodable {
            let group_id: UUID
            let user_id: UUID
            let role: String
        }
        
        try await client
            .from("group_members")
            .insert(JoinPayload(group_id: groupId, user_id: userId, role: "member"))
            .execute()
    }
    
    // メンバー詳細を取得
    func fetchGroupMembers(groupId: UUID) async throws -> [Profile] {
        // group_members から user_id を取得し profiles を紐付け
        struct MemberResponse: Codable {
            let user_id: UUID
            let profiles: Profile
        }
        
        let response: [MemberResponse] = try await client
            .from("group_members")
            .select("user_id, profiles!user_id(*)")
            .eq("group_id", value: groupId.uuidString)
            .execute()
            .value
            
        return response.map { $0.profiles }
    }
    
    // メンバー削除
    func removeMember(groupId: UUID, userId: UUID) async throws {
        try await client
            .from("group_members")
            .delete()
            .eq("group_id", value: groupId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
    
    // --- リスト関連 ---
    
    // 全グループの全リスト取得（通知同期用）
    func fetchAllLists() async throws -> [ShoppingList] {
        guard let userId = currentUser?.id else { return [] }
        
        struct GroupIdResponse: Codable { let group_id: UUID }
        let groupResponse: [GroupIdResponse] = try await client
            .from("group_members")
            .select("group_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
            
        let groupIds = groupResponse.map { $0.group_id }
        if groupIds.isEmpty { return [] }
        
        return try await client
            .from("lists")
            .select()
            .in("group_id", values: groupIds)
            .execute()
            .value
    }
    
    // 特定グループのリスト取得
    func fetchLists(groupId: UUID) async throws -> [ShoppingList] {
        return try await client
            .from("lists")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    
    // リスト作成
    func createList(groupId: UUID, name: String, interval: NotificationInterval, targets: [UUID]) async throws -> ShoppingList? {
        guard let userId = currentUser?.id else { return nil }
        
        struct CreateListPayload: Encodable {
            let name: String
            let group_id: UUID
            let owner_id: UUID
            let reminder_interval: NotificationInterval
            let reminder_targets: [UUID]
        }
        
        let payload = CreateListPayload(
            name: name, 
            group_id: groupId, 
            owner_id: userId,
            reminder_interval: interval,
            reminder_targets: targets
        )
        
        return try await client
            .from("lists")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }
    
    // リストのリマインド設定更新
    func updateListReminder(listId: UUID, interval: NotificationInterval, targets: [UUID]) async throws {
        struct UpdateReminderPayload: Encodable {
            let reminder_interval: NotificationInterval
            let reminder_targets: [UUID]
        }
        
        let payload = UpdateReminderPayload(reminder_interval: interval, reminder_targets: targets)
        
        try await client
            .from("lists")
            .update(payload)
            .eq("id", value: listId.uuidString)
            .execute()
    }
    
    // --- アイテム関連 ---
    
    // 全リストの未購入アイテム取得（通知同期用）
    func fetchAllUnpurchasedItems() async throws -> [Item] {
        guard currentUser != nil else { return [] }
        
        let lists = try await fetchAllLists()
        let listIds = lists.map { $0.id }
        if listIds.isEmpty { return [] }
        
        let items: [Item] = try await client
            .from("items")
            .select("""
                *,
                purchaser:profiles!purchaser_id(id, display_name),
                creator:profiles!creator_id(id, display_name)
            """)
            .in("list_id", values: listIds)
            .eq("is_purchased", value: false)
            .execute()
            .value
            
        // ウィジェット用データを更新
        saveItemsForWidget(items: items, lists: lists)
        
        return items
    }
    
    // ウィジェット用データの保存
    private func saveItemsForWidget(items: [Item], lists: [ShoppingList]) {
        let listMap = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.name) })
        
        struct WidgetItem: Codable {
            let id: UUID
            let name: String
            let listName: String
            let dueDate: Date?
        }
        
        let widgetItems = items.prefix(10).map { item in
            WidgetItem(
                id: item.id,
                name: item.name,
                listName: listMap[item.listId] ?? "不明なリスト",
                dueDate: item.dueDate
            )
        }
        
        if let encoded = try? JSONEncoder().encode(widgetItems),
           let defaults = UserDefaults(suiteName: AppConstants.appGroupId) {
            defaults.set(encoded, forKey: AppConstants.widgetDataKey)
            // ウィジェットの再描画を促す
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    // 特定リストのアイテム取得
    func fetchItems(listId: UUID) async throws -> [Item] {
        return try await client
            .from("items")
            .select("""
                *,
                purchaser:profiles!purchaser_id(id, display_name),
                creator:profiles!creator_id(id, display_name)
            """)
            .eq("list_id", value: listId)
            .order("due_date", ascending: true, nullsFirst: false) // 期限なしは後に
            .execute()
            .value
    }
    
    // アイテム追加
    func addItem(listId: UUID, name: String, dueDate: Date?, interval: NotificationInterval?, targets: [UUID]?) async throws {
        struct InsertPayload: Encodable {
            let list_id: UUID
            let name: String
            let is_purchased: Bool
            let due_date: String?
            let creator_id: UUID?
            let reminder_interval: NotificationInterval?
            let reminder_targets: [UUID]?
        }
        
        let payload = InsertPayload(
            list_id: listId,
            name: name,
            is_purchased: false,
            due_date: dueDate?.iso8601String(),
            creator_id: currentUser?.id,
            reminder_interval: interval,
            reminder_targets: targets
        )
        
        try await client
            .from("items")
            .insert(payload)
            .execute()
    }
    
    // アイテム更新（リマインド設定含む）
    func updateItem(item: Item) async throws {
        struct UpdatePayload: Encodable {
            let name: String
            let due_date: String?
            let reminder_interval: NotificationInterval?
            let reminder_targets: [UUID]?
        }
        
        let payload = UpdatePayload(
            name: item.name,
            due_date: item.dueDate?.iso8601String(),
            reminder_interval: item.reminderInterval,
            reminder_targets: item.reminderTargets
        )
        
        try await client
            .from("items")
            .update(payload)
            .eq("id", value: item.id.uuidString)
            .execute()
    }
    
    // 購入ステータスの更新
    func updateItemStatus(item: Item, isPurchased: Bool) async throws {
        struct UpdatePayload: Encodable {
            let is_purchased: Bool
            let purchaser_id: UUID?
        }
        let payload = UpdatePayload(is_purchased: isPurchased, purchaser_id: isPurchased ? currentUser?.id : nil)
        
        try await client
            .from("items")
            .update(payload)
            .eq("id", value: item.id)
            .execute()
    }
    
    // 購入予定の切り替え
    func togglePlanning(item: Item) async throws {
        guard let userId = currentUser?.id else { return }
        let isPlanning = item.planningPurchaserId == userId
        
        try await client
            .from("items")
            .update(["planning_purchaser_id": isPlanning ? nil : userId.uuidString])
            .eq("id", value: item.id.uuidString)
            .execute()
    }
    
    // 削除
    func deleteItem(id: UUID) async throws {
        try await client
            .from("items")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    
    // プロフィール更新
    func updateProfile(displayName: String) async throws {
        guard let userId = currentUser?.id else { return }
        try await client
            .from("profiles")
            .update(["display_name": displayName])
            .eq("id", value: userId.uuidString)
            .execute()
    }
    
    // アカウント削除
    func deleteAccount() async throws {
        try await client.rpc("delete_own_account").execute()
        try await client.auth.signOut()
    }
}

// 便利な拡張
extension Date {
    func iso8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
