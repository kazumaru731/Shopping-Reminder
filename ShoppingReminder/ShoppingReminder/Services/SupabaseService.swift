import Foundation
import Supabase
import Combine
import WidgetKit
import Realtime
import Storage
import UIKit

class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    // バケット名
    private let itemImagesBucket = "item-images"
    
    // TODO: 実際のSupabaseプロジェクトのURLとキーに置き換えてください
    let client = SupabaseClient(
        supabaseURL: URL(string: "https://xhzvkjokpvrdwbiebitb.supabase.co")!,
        supabaseKey: "sb_publishable_l0rvlv5CpmjAAdOmz36mVw_Dd8it9yQ"
    )
    
    @Published var currentUser: User?
    @Published var isInitializing = true
    @Published var isPasswordRecovery = false
    @Published var authError: String?
    
    private init() {
        // 現在のユーザーセッションを確認
        Task {
            do {
                self.currentUser = try await client.auth.session.user
            } catch {
                #if DEBUG
                print("DEBUG: Initial session check failed: \(error)")
                #endif
            }
            
            await MainActor.run {
                self.isInitializing = false
            }
            
            // Authの状態変化を監視
            for await (event, session) in client.auth.authStateChanges {
                await MainActor.run {
                    self.currentUser = session?.user
                    
                    if event == .passwordRecovery {
                        self.isPasswordRecovery = true
                    } else if event == .signedOut {
                        self.isPasswordRecovery = false
                    }
                }
            }
        }
    }
    
    func resetPasswordRecoveryStatus() {
        self.isPasswordRecovery = false
    }
    
    func handleOpenURL(_ url: URL) {
        Task { @MainActor in
            let urlString = url.absoluteString
            #if DEBUG
            print("[Auth] handleOpenURL: \(urlString)")
            #endif
            
            // エラーが含まれているかチェック（例: 有効期限切れのリンクなど）
            if urlString.contains("error_description=") {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems ?? components.fragment?.components(separatedBy: "&").compactMap({ 
                       let parts = $0.components(separatedBy: "=")
                       return parts.count == 2 ? URLQueryItem(name: parts[0], value: parts[1]) : nil
                   }),
                   let errorDesc = queryItems.first(where: { $0.name == "error_description" })?.value?.removingPercentEncoding {
                    self.authError = "リンクが無効です: \(errorDesc)"
                } else {
                    self.authError = "リンクが無効か、期限切れです。"
                }
            } else if urlString.contains("type=recovery") || urlString.contains("reset-password") {
                self.isPasswordRecovery = true
            }
        }
        
        Task {
            do {
                _ = try await client.auth.session(from: url)
            } catch {
                await MainActor.run {
                    self.authError = "認証エラー: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // 認証: サインアップ
    func signUp(email: String, password: String, displayName: String) async throws {
        try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": AnyJSON.string(displayName)],
            redirectTo: URL(string: "shoppingreminder://login-callback")!
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
    
    // パスワードリセットメール送信
    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: URL(string: "shoppingreminder://reset-password")!)
    }
    
    // パスワード更新（リセット後の更新など）
    func updatePassword(password: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password))
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
            let allow_member_edit: Bool
        }
        
        let payload = CreateGroupPayload(name: name, invite_code: inviteCode, owner_id: userId, allow_member_edit: false)
        
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
    
    // グループ更新
    func updateGroup(group: Group) async throws {
        struct UpdatePayload: Encodable {
            let name: String
            let allow_member_edit: Bool
        }
        let payload = UpdatePayload(name: group.name, allow_member_edit: group.allowMemberEdit ?? false)
        try await client.from("groups").update(payload).eq("id", value: group.id).execute()
    }
    
    // コードまたはIDからグループ情報を取得
    func getGroupByCode(code: String) async throws -> Group? {
        do {
            // UUID形式かチェック
            if let uuid = UUID(uuidString: code) {
                let groups: [Group] = try await client
                    .from("groups")
                    .select()
                    .eq("id", value: uuid.uuidString)
                    .limit(1)
                    .execute()
                    .value
                
                #if DEBUG
                print("[Group] ID検索結果: \(groups)")
                #endif
                return groups.first
            } else {
                // 招待コードで検索
                let groups: [Group] = try await client
                    .from("groups")
                    .select()
                    .eq("invite_code", value: code.uppercased())
                    .limit(1)
                    .execute()
                    .value
                
                #if DEBUG
                print("[Group] Code検索結果: \(groups)")
                #endif
                return groups.first
            }
        } catch {
            #if DEBUG
            print("[Group] getGroupByCode エラー: \(error)")
            #endif
            throw error
        }
    }
    
    // グループに参加
    func joinGroup(groupId: UUID) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "ユーザー認証が必要です。"])
        }
        
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
    
    // グループ退出
    func leaveGroup(groupId: UUID) async throws {
        guard let userId = currentUser?.id else { return }
        
        // 1. メンバーから削除
        try await removeMember(groupId: groupId, userId: userId)
        
        // 2. 残りのメンバーを確認
        let members = try await fetchGroupMembers(groupId: groupId)
        
        // 3. 0人ならグループを削除
        if members.isEmpty {
            try await client
                .from("groups")
                .delete()
                .eq("id", value: groupId.uuidString)
                .execute()
        }
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
    func createList(groupId: UUID, name: String, interval: NotificationInterval, targets: [UUID], notes: String? = nil) async throws -> ShoppingList? {
        guard let userId = currentUser?.id else { return nil }
        
        struct CreateListPayload: Encodable {
            let name: String
            let group_id: UUID
            let owner_id: UUID
            let reminder_interval: NotificationInterval
            let reminder_targets: [UUID]
            let allow_member_edit: Bool
            let notes: String?
        }
        
        let payload = CreateListPayload(
            name: name, 
            group_id: groupId, 
            owner_id: userId,
            reminder_interval: interval,
            reminder_targets: targets,
            allow_member_edit: false,
            notes: notes
        )
        
        let newList: ShoppingList = try await client
            .from("lists")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
            
        return newList
    }
    
    // リスト削除
    func deleteList(id: UUID) async throws {
        try await client
            .from("lists")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    // リスト更新（名前やフラグ）
    func updateList(list: ShoppingList) async throws {
        struct UpdatePayload: Encodable {
            let name: String
            let allow_member_edit: Bool
            let notes: String?
        }
        let payload = UpdatePayload(name: list.name, allow_member_edit: list.allowMemberEdit ?? false, notes: list.notes)
        try await client.from("lists").update(payload).eq("id", value: list.id).execute()
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
            
        // 期限が近い順にソート（期限なしは後に）
        let sortedItems = items.sorted { a, b in
            if let aDue = a.dueDate, let bDue = b.dueDate {
                return aDue < bDue
            }
            if a.dueDate != nil { return true }
            if b.dueDate != nil { return false }
            return false
        }
        
        // ウィジェット用データを更新
        saveItemsForWidget(items: sortedItems, lists: lists)
        
        return sortedItems
    }
    
    // ウィジェット用データの保存
    private func saveItemsForWidget(items: [Item], lists: [ShoppingList]) {
        let listMap = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.name) })
        
        struct WidgetItem: Codable {
            let id: UUID
            let name: String
            let listName: String
            let listId: UUID
            let dueDate: Date?
        }
        
        struct WidgetList: Codable {
            let id: UUID
            let name: String
        }
        
        let widgetItems = items.prefix(20).map { item in
            WidgetItem(
                id: item.id,
                name: item.name,
                listName: listMap[item.listId] ?? "不明なリスト",
                listId: item.listId,
                dueDate: item.dueDate
            )
        }
        
        let widgetLists = lists.map { WidgetList(id: $0.id, name: $0.name) }
        
        if let defaults = UserDefaults(suiteName: AppConstants.appGroupId) {
            if let encodedItems = try? JSONEncoder().encode(widgetItems) {
                defaults.set(encodedItems, forKey: AppConstants.widgetDataKey)
            }
            if let encodedLists = try? JSONEncoder().encode(widgetLists) {
                defaults.set(encodedLists, forKey: AppConstants.widgetListsKey)
            }
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
    func addItem(listId: UUID, name: String, dueDate: Date?, interval: NotificationInterval?, targets: [UUID]?, linkUrl: String? = nil, imageUrl: String? = nil, notes: String? = nil) async throws {
        struct InsertPayload: Encodable {
            let list_id: UUID
            let name: String
            let is_purchased: Bool
            let due_date: String?
            let creator_id: UUID?
            let reminder_interval: NotificationInterval?
            let reminder_targets: [UUID]?
            let link_url: String?
            let image_url: String?
            let allow_collaborator_edit: Bool
            let notes: String?
        }
        
        let payload = InsertPayload(
            list_id: listId,
            name: name,
            is_purchased: false,
            due_date: dueDate?.iso8601String(),
            creator_id: currentUser?.id,
            reminder_interval: interval,
            reminder_targets: targets,
            link_url: linkUrl,
            image_url: imageUrl,
            allow_collaborator_edit: false,
            notes: notes
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
            let link_url: String?
            let image_url: String?
            let allow_collaborator_edit: Bool
            let notes: String?
        }
        
        let payload = UpdatePayload(
            name: item.name,
            due_date: item.dueDate?.iso8601String(),
            reminder_interval: item.reminderInterval,
            reminder_targets: item.reminderTargets,
            link_url: item.linkUrl,
            image_url: item.imageUrl,
            allow_collaborator_edit: item.allowCollaboratorEdit ?? false,
            notes: item.notes
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
    
    // 削除（画像がある場合はStorageからも連動削除）
    func deleteItem(id: UUID, imageUrl: String? = nil) async throws {
        // アイテムとStorageを分離して削除すると、
        // アイテムは消えたのに画像ファイルが永遠に残る「孤児ファイル」問題を防ぐ
        if let imageUrl, !imageUrl.isEmpty,
           let storagePath = extractStoragePath(from: imageUrl) {
            // Storage削除の失敗はアイテム削除自体をブロックすべきでないためtry?扱いとする
            try? await client.storage.from(itemImagesBucket).remove(paths: [storagePath])
        }
        
        try await client
            .from("items")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    
    // Supabase Storage公開パスをURL文字列から抽出する
    // URL形式: .../storage/v1/object/public/{bucket}/{path}
    private func extractStoragePath(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let marker = "/object/public/\(itemImagesBucket)/"
        guard let range = url.path.range(of: marker) else { return nil }
        return String(url.path[range.upperBound...])
    }
    
    // 画像をアップロードしてURLを返す
    func uploadItemImage(data: Data, fileName: String) async throws -> String {
        // 画像をリサイズ・圧縮して軽量化
        guard let image = UIImage(data: data),
              let compressedData = resizeAndCompressImage(image: image) else {
            throw NSError(domain: "SupabaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "画像の圧縮に失敗しました"])
        }
        
        let path = "\(currentUser?.id.uuidString ?? "public")/\(Date().timeIntervalSince1970)_\(fileName)"
        
        try await client.storage
            .from(itemImagesBucket)
            .upload(
                path: path,
                file: compressedData,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg")
            )
        
        // 公開URLを取得
        let url = try client.storage
            .from(itemImagesBucket)
            .getPublicURL(path: path)
        
        return url.absoluteString
    }
    
    // プッシュ通知トークンの保存
    func savePushToken(token: String, deviceId: String) async {
        guard let userId = currentUser?.id else {
            #if DEBUG
            print("[PushToken] スキップ - ログイン未完了")
            #endif
            return
        }
        
        struct TokenPayload: Encodable {
            let user_id: UUID
            let token: String
            let device_id: String
        }
        
        let payload = TokenPayload(user_id: userId, token: token, device_id: deviceId)
        
        do {
            // user_id を一意キーとして upsert することで、
            // 再インストール後に device_id が変わっても、
            // 同一ユーザーのトークンが常に最新のものへ上書きされる
            try await client
                .from("push_tokens")
                .upsert(payload, onConflict: "user_id")
                .execute()
            #if DEBUG
            print("[PushToken] 保存成功 - userId: \(userId)")
            #endif
        } catch {
            #if DEBUG
            print("[PushToken] 保存失敗: \(error.localizedDescription)")
            #endif
        }
    }
    
    // 画像を最大1024pxにリサイズし、画質を落として圧縮する
    private func resizeAndCompressImage(image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        var newSize = image.size
        
        // 縦横の長い方を基準にリサイズ比率を計算
        if image.size.width > maxDimension || image.size.height > maxDimension {
            let aspectRatio = image.size.width / image.size.height
            if aspectRatio > 1 {
                newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
            } else {
                newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
            }
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // JPEG形式で圧縮（画質 0.7 程度が速度と見た目のバランスが良い）
        return resizedImage.jpegData(compressionQuality: 0.7)
    }
    
    // プロフィール取得
    func fetchCurrentProfile() async throws -> Profile? {
        guard let userId = currentUser?.id else { return nil }
        return try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
    }
    
    // プロフィール更新
    func updateProfile(displayName: String, notifyOnListDelete: Bool, notifyOnItemDelete: Bool, notifyOnGroupLeave: Bool) async throws {
        guard let userId = currentUser?.id else { return }
        let payload: [String: AnyJSON] = [
            "display_name": .string(displayName),
            "notify_on_list_delete": .bool(notifyOnListDelete),
            "notify_on_item_delete": .bool(notifyOnItemDelete),
            "notify_on_group_leave": .bool(notifyOnGroupLeave)
        ]
        try await client
            .from("profiles")
            .update(payload)
            .eq("id", value: userId.uuidString)
            .execute()
    }
    
    // アカウント削除
    func deleteAccount() async throws {
        // 1. 参加しているグループをすべて取得
        let groups = try await fetchGroups()
        
        // 2. 各グループから退出処理（空になった場合の削除ロジックを含む）
        for group in groups {
            try? await leaveGroup(groupId: group.id)
        }
        
        // 3. 自身のデータを完全に削除するRPCを実行
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
