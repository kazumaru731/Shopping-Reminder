import SwiftUI
import Combine

struct GroupListView: View {
    @StateObject private var viewModel = GroupListViewModel()
    @State private var showingCreateGroup = false
    @State private var showingJoinGroup = false
    @State private var showingSettings = false
    @State private var newGroupName = ""
    @State private var joinCode = ""
    
    @State private var showingJoinConfirmation = false
    @State private var groupToJoin: Group?
    
    var body: some View {
        NavigationView {
            List {
                if viewModel.groups.isEmpty {
                    Section {
                        Text("所属しているグループがありません。")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(viewModel.groups) { group in
                        NavigationLink(destination: GroupHomeView(group: group)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.headline)
                                Text("招待コード: \(group.inviteCode)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("グループ一覧")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "person.crop.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingCreateGroup = true }) {
                            Label("グループを作る", systemImage: "plus")
                        }
                        Button(action: { showingJoinGroup = true }) {
                            Label("グループに参加する", systemImage: "person.2.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            // グループ作成ダイアログ
            .alert("グループ作成", isPresented: $showingCreateGroup) {
                TextField("グループ名", text: $newGroupName)
                Button("キャンセル", role: .cancel) { newGroupName = "" }
                Button("作成") {
                    Task {
                        await viewModel.createGroup(name: newGroupName)
                        newGroupName = ""
                    }
                }
            }
            // グループ参加（コード入力）ダイアログ
            .alert("グループに参加", isPresented: $showingJoinGroup) {
                TextField("招待コード", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                Button("キャンセル", role: .cancel) { joinCode = "" }
                Button("確認") {
                    Task {
                        await viewModel.checkJoinCode(code: joinCode)
                        joinCode = ""
                    }
                }
            }
            // 参加確認ポップアップ
            .alert("グループ確認", isPresented: $viewModel.showingJoinConfirmation, presenting: viewModel.groupToJoin) { group in
                Button("参加する") {
                    Task {
                        await viewModel.joinGroup(group: group)
                    }
                }
                Button("キャンセル", role: .cancel) { }
            } message: { group in
                Text("「\(group.name)」に参加しますか？")
            }
            .task {
                await viewModel.loadGroups()
            }
        }
    }
}

class GroupListViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var showingJoinConfirmation = false
    @Published var groupToJoin: Group?
    
    func loadGroups() async {
        do {
            self.groups = try await SupabaseService.shared.fetchGroups()
        } catch {
            print("Failed to load groups: \(error)")
        }
    }
    
    func createGroup(name: String) async {
        guard !name.isEmpty else { return }
        do {
            _ = try await SupabaseService.shared.createGroup(name: name)
            await loadGroups()
        } catch {
            print("Error creating group: \(error)")
        }
    }
    
    func checkJoinCode(code: String) async {
        guard !code.isEmpty else { return }
        do {
            if let group = try await SupabaseService.shared.getGroupByCode(code: code) {
                // 既に参加していないかチェック（簡易的）
                if groups.contains(where: { $0.id == group.id }) {
                    print("Already in group")
                    return
                }
                
                await MainActor.run {
                    self.groupToJoin = group
                    self.showingJoinConfirmation = true
                }
            } else {
                print("Group not found")
            }
        } catch {
            print("Error checking code: \(error)")
        }
    }
    
    func joinGroup(group: Group) async {
        do {
            try await SupabaseService.shared.joinGroup(groupId: group.id)
            await loadGroups()
        } catch {
            print("Error joining group: \(error)")
        }
    }
}
