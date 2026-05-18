import SwiftUI
import Combine
import Supabase
import Realtime
import Auth

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
            ScrollView {
                LazyVStack(spacing: 20) {
                    if viewModel.isLoading {
                        ProgressView("グループを読み込み中...")
                            .padding(.top, 40)
                    } else if viewModel.groups.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "person.3.sequence")
                                .font(.system(size: 60))
                                .foregroundColor(.gray.opacity(0.4))
                            Text("所属しているグループがありません。")
                                .foregroundColor(.secondary)
                            Text("右上の「＋」から作成または参加しましょう")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 100)
                    } else {
                        ForEach(viewModel.groups) { group in
                            NavigationLink(destination: GroupHomeView(group: group)) {
                                GroupCardView(group: group)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding()
            }
            .refreshable {
                await viewModel.loadGroups()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("マイグループ")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
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
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
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
            // エラー表示
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "予期せぬエラーが発生しました。")
            }
            .task {
                await viewModel.loadGroups()
                await viewModel.subscribeToChanges()
            }
        }
    }
}

class GroupListViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var showingJoinConfirmation = false
    @Published var groupToJoin: Group?
    @Published var errorMessage: String?
    @Published var showingError = false
    @Published var isLoading = false
    private var isFirstLoad = true
    private var channel: RealtimeChannelV2?
    
    func loadGroups(showLoading: Bool = false) async {
        if isFirstLoad || showLoading {
            await MainActor.run { self.isLoading = true }
            isFirstLoad = false
        }
        defer { Task { @MainActor in self.isLoading = false } }
        
        do {
            self.groups = try await SupabaseService.shared.fetchGroups()
        } catch {
            #if DEBUG
            print("Failed to load groups: \(error)")
            #endif
        }
    }

    func subscribeToChanges() async {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }
        let client = SupabaseService.shared.client
        let channel = client.channel("groups-list-\(userId.uuidString)")
        
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "group_members",
            filter: RealtimePostgresFilter.eq("user_id", value: userId.uuidString)
        )
        
        self.channel = channel
        
        Task {
            do {
                try await channel.subscribeWithError()
                #if DEBUG
                print("DEBUG: Subscribed to group_members changes for user: \(userId)")
                #endif
            } catch {
                #if DEBUG
                print("DEBUG: Subscription error: \(error)")
                #endif
            }
        }
        
        Task {
            for await change in changes {
                #if DEBUG
                print("DEBUG: Group member change received: \(change)")
                #endif
                await loadGroups()
            }
        }
    }
    
    func createGroup(name: String) async {
        guard !name.isEmpty else { return }
        do {
            _ = try await SupabaseService.shared.createGroup(name: name)
            await loadGroups()
        } catch {
            #if DEBUG
            print("Error creating group: \(error)")
            #endif
        }
    }
    
    func checkJoinCode(code: String) async {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }
        
        do {
            if let group = try await SupabaseService.shared.getGroupByCode(code: trimmedCode) {
                // 既に参加していないかチェック
                if groups.contains(where: { $0.id == group.id }) {
                    await MainActor.run {
                        self.errorMessage = "既にこのグループに参加しています。"
                        self.showingError = true
                    }
                    return
                }
                
                await MainActor.run {
                    self.groupToJoin = group
                    self.showingJoinConfirmation = true
                }
            } else {
                await MainActor.run {
                    self.errorMessage = "該当するグループが見つかりませんでした。IDまたは招待コードを確認してください。"
                    self.showingError = true
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "グループが見つからないか、取得に失敗しました。正しいIDまたは招待コードを入力してください。"
                self.showingError = true
                #if DEBUG
                print("Error checking code: \(error)")
                #endif
            }
        }
    }
    
    func joinGroup(group: Group) async {
        do {
            try await SupabaseService.shared.joinGroup(groupId: group.id)
            await loadGroups()
        } catch {
            await MainActor.run {
                self.errorMessage = "グループへの参加に失敗しました。"
                self.showingError = true
            }
            #if DEBUG
            print("Error joining group: \(error)")
            #endif
        }
    }
    
    func leaveGroup(group: Group) async {
        do {
            try await SupabaseService.shared.leaveGroup(groupId: group.id)
            await loadGroups()
        } catch {
            #if DEBUG
            print("Error leaving group: \(error)")
            #endif
        }
    }
}

// モダンなグループカード
struct GroupCardView: View {
    let group: Group
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // アイコン代わりのイニシャル（グラデーション背景）
                ZStack {
                    Circle()
                        .fill(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 50, height: 50)
                    
                    Text(String(group.name.prefix(1)))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("招待コード: \(group.inviteCode)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("共有グループ")
                        .font(.caption2)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
                
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}
