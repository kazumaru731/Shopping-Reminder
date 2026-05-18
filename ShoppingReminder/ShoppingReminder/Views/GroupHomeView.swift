import SwiftUI
import Supabase
import Combine
import Realtime
import Auth

struct GroupHomeView: View {
    let group: Group
    @StateObject private var viewModel = GroupHomeViewModel()
    @State private var showingAddList = false
    @State private var showingMembers = false
    @State private var showingGroupSettings = false
    @State private var newListName = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // メンバーセクション
                VStack(alignment: .leading, spacing: 12) {
                    Text("メンバー")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.members) { member in
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.1))
                                            .frame(width: 60, height: 60)
                                        
                                        Text(String(member.displayName?.prefix(1) ?? "?"))
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Text(member.displayName ?? "不明")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // リストセクション
                VStack(alignment: .leading, spacing: 12) {
                    Text("買い物リスト")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if viewModel.lists.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "list.bullet.clipboard")
                                .font(.largeTitle)
                                .foregroundColor(.gray.opacity(0.3))
                            Text("リストがありません。")
                                .foregroundColor(.secondary)
                            Button("新しいリストを作成") {
                                showingAddList = true
                            }
                            .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(viewModel.lists) { list in
                            NavigationLink(destination: ItemListView(list: list)) {
                                ListCardView(list: list)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.loadLists(groupId: group.id)
            await viewModel.loadMembers(groupId: group.id)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { showingGroupSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    Button(action: { showingMembers = true }) {
                        Image(systemName: "person.2")
                    }
                    Button(action: { showingAddList = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingMembers) {
            GroupMemberListView(groupId: group.id, ownerId: group.ownerId)
        }
        .sheet(isPresented: $showingAddList) {
            AddListView(groupId: group.id, viewModel: viewModel)
        }
        .sheet(isPresented: $showingGroupSettings) {
            GroupSettingsView(group: group)
        }
        .task {
            await viewModel.loadLists(groupId: group.id)
            await viewModel.loadMembers(groupId: group.id)
            await viewModel.subscribeToChanges(groupId: group.id)
        }
    }
}

// リストカード
struct ListCardView: View {
    let list: ShoppingList
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "cart.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.blue)
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.headline)
                
                Text("作成: \(list.createdAt.japaneseFormatted())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}

class GroupHomeViewModel: ObservableObject {
    @Published var lists: [ShoppingList] = []
    @Published var members: [Profile] = []
    private var channel: RealtimeChannelV2?
    
    func loadMembers(groupId: UUID) async {
        do {
            self.members = try await SupabaseService.shared.fetchGroupMembers(groupId: groupId)
        } catch {
            print("Failed to load members: \(error)")
        }
    }
    
    func loadLists(groupId: UUID) async {
        do {
            let fetchedLists = try await SupabaseService.shared.fetchLists(groupId: groupId)
            self.lists = fetchedLists
            
            // 自分が通知対象になっているリストの通知を同期する
            if let userId = SupabaseService.shared.currentUser?.id {
                let targetedLists = fetchedLists.filter { list in
                    list.reminderInterval != nil && (list.reminderTargets?.contains(userId) ?? false)
                }
                NotificationManager.shared.syncNotifications(for: targetedLists)
            }
        } catch {
            print("Failed to load lists: \(error)")
        }
    }

    func subscribeToChanges(groupId: UUID) async {
        let client = SupabaseService.shared.client
        let channel = client.channel("group-home-\(groupId.uuidString)")
        
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "lists",
            filter: RealtimePostgresFilter.eq("group_id", value: groupId.uuidString)
        )
        
        self.channel = channel
        
        Task {
            do {
                try await channel.subscribeWithError()
                print("DEBUG: Subscribed to lists changes for group: \(groupId)")
            } catch {
                print("DEBUG: Subscription error: \(error)")
            }
        }
        
        Task {
            for await change in changes {
                print("DEBUG: List change received: \(change)")
                await loadLists(groupId: groupId)
            }
        }
    }
    
    func createList(groupId: UUID, name: String, interval: NotificationInterval, targets: [UUID]) async {
        guard !name.isEmpty else { return }
        do {
            if let newList = try await SupabaseService.shared.createList(
                groupId: groupId, 
                name: name, 
                interval: interval, 
                targets: targets
            ) {
                // ローカル通知の予約
                NotificationManager.shared.scheduleNotification(for: newList)
            }
            await loadLists(groupId: groupId)
        } catch {
            print("Error creating list: \(error)")
        }
    }
    
    func deleteList(list: ShoppingList) async {
        do {
            try await SupabaseService.shared.deleteList(id: list.id)
            await loadLists(groupId: list.groupId)
            // ローカル通知のキャンセル
            NotificationManager.shared.cancelNotification(for: list)
        } catch {
            print("Error deleting list: \(error)")
        }
    }
}
