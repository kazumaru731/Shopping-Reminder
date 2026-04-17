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
            Section(header: Text("未購入")) {
                ForEach(viewModel.items.filter { !$0.isPurchased }) { item in
                    NavigationLink(destination: ItemDetailView(item: item, groupId: list.groupId)) {
                        ItemRow(item: item, onToggle: {
                            Task { await viewModel.togglePurchased(item: item) }
                        }, onPlan: {
                            Task { await viewModel.togglePlanning(item: item) }
                        })
                    }
                }
                .onDelete { indexSet in
                    let unpurchasedItems = viewModel.items.filter { !$0.isPurchased }
                    indexSet.forEach { index in
                        let item = unpurchasedItems[index]
                        Task { await viewModel.deleteItem(item: item) }
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
                }
                .onDelete { indexSet in
                    let purchasedItems = viewModel.items.filter { $0.isPurchased }
                    indexSet.forEach { index in
                        let item = purchasedItems[index]
                        Task { await viewModel.deleteItem(item: item) }
                    }
                }
            }
        }
        .navigationTitle(list.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { showingReminderSettings = true }) {
                        Image(systemName: "bell")
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
                
                HStack(spacing: 4) {
                    if let creatorName = item.creator?.displayName {
                        Text("追加: \(creatorName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let due = item.dueDate {
                        Text("• 期限: \(due, style: .date)")
                            .font(.caption2)
                            .foregroundColor(.red)
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
}

class ItemListViewModel: ObservableObject {
    @Published var items: [Item] = []
    private var channel: RealtimeChannelV2?
    
    func loadItems(listId: UUID) async {
        do {
            self.items = try await SupabaseService.shared.fetchItems(listId: listId)
            await NotificationManager.shared.syncAllNotifications()
        } catch {
            print("Error: \(error)")
        }
    }
    
    func addItem(listId: UUID, name: String, dueDate: Date?, interval: NotificationInterval?, targets: [UUID]?) async {
        do {
            try await SupabaseService.shared.addItem(
                listId: listId, 
                name: name, 
                dueDate: dueDate,
                interval: interval,
                targets: targets
            )
            await loadItems(listId: listId)
        } catch {
            print("Error adding item: \(error)")
        }
    }
    
    func deleteItem(item: Item) async {
        do {
            try await SupabaseService.shared.deleteItem(id: item.id)
            await loadItems(listId: item.listId)
        } catch {
            print("Error deleting item: \(error)")
        }
    }
    
    func togglePurchased(item: Item) async {
        do {
            try await SupabaseService.shared.updateItemStatus(item: item, isPurchased: !item.isPurchased)
            await loadItems(listId: item.listId)
        } catch {
            print("Error toggling status: \(error)")
        }
    }
    
    func togglePlanning(item: Item) async {
        do {
            try await SupabaseService.shared.togglePlanning(item: item)
            await loadItems(listId: item.listId)
        } catch {
            print("Error toggling planning: \(error)")
        }
    }
    
    // リアルタイム購読
    func subscribeToChanges(listId: UUID) async {
        let client = SupabaseService.shared.client
        let channel = client.channel("list-\(listId.uuidString)")
        
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "items",
            filter: .eq("list_id", value: listId.uuidString)
        )
        
        self.channel = channel
        
        Task {
            try? await channel.subscribeWithError()
        }
        
        Task {
            for await _ in changes {
                // 変更があったら再読み込み
                await loadItems(listId: listId)
            }
        }
    }
}
