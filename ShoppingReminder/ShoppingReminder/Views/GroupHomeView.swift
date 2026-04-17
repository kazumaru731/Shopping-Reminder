import SwiftUI
import Supabase
import Combine

struct GroupHomeView: View {
    let group: Group
    @StateObject private var viewModel = GroupHomeViewModel()
    @State private var showingAddList = false
    @State private var showingMembers = false
    @State private var newListName = ""
    
    var body: some View {
        List {
            Section(header: Text("買い物リスト")) {
                if viewModel.lists.isEmpty {
                    Text("リストがありません。")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.lists) { list in
                        NavigationLink(destination: ItemListView(list: list)) {
                            VStack(alignment: .leading) {
                                Text(list.name)
                                    .font(.headline)
                                Text("作成日: \(list.createdAt, style: .date)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
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
        .task {
            await viewModel.loadLists(groupId: group.id)
        }
    }
}

class GroupHomeViewModel: ObservableObject {
    @Published var lists: [ShoppingList] = []
    
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
}
