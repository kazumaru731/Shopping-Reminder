import SwiftUI
import Combine
import Supabase
import Realtime

struct ItemListView: View {
    @State var list: ShoppingList
    @StateObject private var viewModel = ItemListViewModel()
    
    init(list: ShoppingList) {
        self._list = State(initialValue: list)
    }
    @State private var showingAddItemSheet = false
    @State private var showingReminderSettings = false
    
    var body: some View {
        List {
            if let listNotes = list.notes, !listNotes.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text(listNotes)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("アイテムを読み込み中...")
                        Spacer()
                    }
                }
            }
            
            Section(header: Text("未購入")) {
                ForEach(viewModel.items.filter { !$0.isPurchased }) { item in
                    NavigationLink(destination: ItemDetailView(item: item, groupId: list.groupId)) {
                        ItemRow(item: item, onToggle: {
                            Task { await viewModel.togglePurchased(item: item) }
                        }, onPlan: {
                            Task { await viewModel.togglePlanning(item: item) }
                        })
                    }
                    .deleteDisabled(!(item.creatorId == SupabaseService.shared.currentUser?.id || (item.allowCollaboratorEdit ?? false)))
                }
                .onDelete { indexSet in
                    let unpurchasedItems = viewModel.items.filter { !$0.isPurchased }
                    indexSet.forEach { index in
                        let item = unpurchasedItems[index]
                        if item.creatorId == SupabaseService.shared.currentUser?.id || (item.allowCollaboratorEdit ?? false) {
                            Task { await viewModel.deleteItem(item: item) }
                        }
                    }
                }
            }
            
            Section(header: Text("購入済み")) {
                ForEach(viewModel.items.filter { $0.isPurchased }) { item in
                    HStack {
                        Text(item.name)
                            .strikethrough()
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if let purchaserName = item.purchaser?.displayName {
                            Text(purchaserName)
                                .font(.caption2)
                                .padding(4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        // 自分が購入した場合は取り消し可能
                        if item.purchaserId == SupabaseService.shared.currentUser?.id {
                            Button("取り消し") {
                                Task { await viewModel.togglePurchased(item: item) }
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .deleteDisabled(!(item.creatorId == SupabaseService.shared.currentUser?.id || (item.allowCollaboratorEdit ?? false)))
                }
                .onDelete { indexSet in
                    let purchasedItems = viewModel.items.filter { $0.isPurchased }
                    indexSet.forEach { index in
                        let item = purchasedItems[index]
                        // 自分が作成者か、編集が許可されている場合のみ削除可能
                        if item.creatorId == SupabaseService.shared.currentUser?.id || (item.allowCollaboratorEdit ?? false) {
                            Task { await viewModel.deleteItem(item: item) }
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.loadItems(listId: list.id)
        }
        .navigationTitle(list.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { showingReminderSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    Button(action: { showingAddItemSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddItemSheet) {
            AddItemView(list: list, viewModel: viewModel)
        }
        .sheet(isPresented: $showingReminderSettings) {
            ListReminderSettingsView(list: $list)
        }
        .task {
            await viewModel.loadItems(listId: list.id)
            await viewModel.subscribeToChanges(listId: list.id)
        }
    }
}

struct ItemRow: View {
    let item: Item
    var onToggle: () -> Void
    var onPlan: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isPurchased ? .green : .gray)
            }
            .buttonStyle(BorderlessButtonStyle()) // タップ範囲をボタンのみに限定
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    if let creatorName = item.creator?.displayName {
                        Text("追加: \(creatorName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let due = item.dueDate {
                        Text("• 期限: \(due.japaneseFormatted())")
                            .font(.caption2)
                            .foregroundColor(dueDateColor(due: due))
                    } else {
                        Text("• 期限: 期限なし")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        if item.linkUrl != nil {
                            Image(systemName: "link")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        if item.imageUrl != nil {
                            Image(systemName: "photo")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                    }
                }
            }
            
            Spacer()
            
            // 購入予定ボタン
            Button(action: onPlan) {
                Label(item.planningPurchaserId != nil ? "予約済" : "買う！", 
                      systemImage: item.planningPurchaserId != nil ? "person.fill.checkmark" : "person.badge.plus")
                    .font(.caption)
                    .padding(6)
                    .background(item.planningPurchaserId != nil ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                    .foregroundColor(item.planningPurchaserId != nil ? .blue : .primary)
            }
            .buttonStyle(BorderlessButtonStyle()) // タップ範囲をボタンのみに限定
        }
    }
    
    private func dueDateColor(due: Date) -> Color {
        let now = Date()
        let timeInterval = due.timeIntervalSince(now)
        let hoursRemaining = timeInterval / 3600
        
        // UserDefaults から設定を取得 (デフォルト値: 注意24時間、緊急5時間)
        let warningHours = Double(UserDefaults.standard.object(forKey: "deadline_warning_hours") as? Int ?? 24)
        let criticalHours = Double(UserDefaults.standard.object(forKey: "deadline_critical_hours") as? Int ?? 5)
        
        if hoursRemaining < 0 {
            return .red // 期限切れ
        } else if hoursRemaining <= criticalHours {
            return .red // 緊急
        } else if hoursRemaining <= warningHours {
            return .yellow // 注意
        } else {
            return .secondary // 余裕あり
        }
    }
}

@MainActor
class ItemListViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    private var isFirstLoad = true
    private var channel: RealtimeChannelV2?
    
    func loadItems(listId: UUID, showLoading: Bool = false) async {
        // 初回ロード時のみ、または明示的に要求された場合のみインジケーターを表示
        if isFirstLoad || showLoading {
            self.isLoading = true
            isFirstLoad = false
        }
        defer { self.isLoading = false }
        
        do {
            let fetchedItems = try await SupabaseService.shared.fetchItems(listId: listId)
            self.items = fetchedItems
            #if DEBUG
            SecureLog.debug("DEBUG: Items loaded: \(fetchedItems.count) items")
            #endif
            await NotificationManager.shared.syncAllNotifications()
        } catch {
            #if DEBUG
            SecureLog.debug("DEBUG: Error loading items")
            #endif
        }
    }
    
    // ... addItem, deleteItem, togglePurchased, togglePlanning は変更なし ...
    func addItem(listId: UUID, name: String, dueDate: Date?, interval: NotificationInterval?, targets: [UUID]?, linkUrl: String? = nil, imageUrl: String? = nil, notes: String? = nil) async {
        do {
            try await SupabaseService.shared.addItem(listId: listId, name: name, dueDate: dueDate, interval: interval, targets: targets, linkUrl: linkUrl, imageUrl: imageUrl, notes: notes)
            await loadItems(listId: listId)
        } catch {
            #if DEBUG
            SecureLog.debug("Error adding item")
            #endif
        }
    }
    
    func deleteItem(item: Item) async {
        do {
            try await SupabaseService.shared.deleteItem(id: item.id)
            await loadItems(listId: item.listId)
        } catch {
            #if DEBUG
            SecureLog.debug("Error deleting item")
            #endif
        }
    }
    
    func togglePurchased(item: Item) async {
        do {
            try await SupabaseService.shared.updateItemStatus(item: item, isPurchased: !item.isPurchased)
            await loadItems(listId: item.listId)
        } catch {
            #if DEBUG
            SecureLog.debug("Error toggling status")
            #endif
        }
    }
    
    func togglePlanning(item: Item) async {
        do {
            try await SupabaseService.shared.togglePlanning(item: item)
            await loadItems(listId: item.listId)
        } catch {
            #if DEBUG
            SecureLog.debug("Error toggling planning")
            #endif
        }
    }

    // リアルタイム購読の強化
    func subscribeToChanges(listId: UUID) async {
        let client = SupabaseService.shared.client
        let channel = client.channel("list-\(listId.uuidString)")
        
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "items",
            filter: RealtimePostgresFilter.eq("list_id", value: listId.uuidString)
        )
        
        self.channel = channel
        
        Task {
            do {
                try await channel.subscribeWithError()
                #if DEBUG
                SecureLog.debug("DEBUG: Subscribed to realtime changes")
                #endif
            } catch {
                #if DEBUG
                SecureLog.debug("DEBUG: Subscription error")
                #endif
            }
        }
        
        Task {
            for await _ in changes {
                #if DEBUG
                SecureLog.debug("DEBUG: Realtime change received")
                #endif
                await loadItems(listId: listId)
            }
        }
    }
}
