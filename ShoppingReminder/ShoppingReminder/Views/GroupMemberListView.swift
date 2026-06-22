import SwiftUI
import Combine
import Supabase

struct GroupMemberListView: View {
    let groupId: UUID
    let ownerId: UUID
    @StateObject private var viewModel = GroupMemberListViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.members) { member in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(member.displayName ?? "名前なし")
                                .font(.body)
                            if member.id == ownerId {
                                Text("オーナー")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Color.orange, lineWidth: 0.5)
                                    )
                            }
                        }
                        
                        Spacer()
                        
                        // オーナーかつ自分以外なら削除ボタン表示
                        if isCurrentUserOwner && member.id != ownerId {
                            Button(action: {
                                Task {
                                    await viewModel.removeMember(groupId: groupId, userId: member.id)
                                }
                            }) {
                                Image(systemName: "person.badge.minus")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("メンバー一覧")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadMembers(groupId: groupId)
            }
        }
    }
    
    private var isCurrentUserOwner: Bool {
        SupabaseService.shared.currentUser?.id == ownerId
    }
}

class GroupMemberListViewModel: ObservableObject {
    @Published var members: [Profile] = []
    
    func loadMembers(groupId: UUID) async {
        do {
            self.members = try await SupabaseService.shared.fetchGroupMembers(groupId: groupId)
        } catch {
            SecureLog.debug("Failed to load members")
        }
    }
    
    func removeMember(groupId: UUID, userId: UUID) async {
        do {
            try await SupabaseService.shared.removeMember(groupId: groupId, userId: userId)
            await loadMembers(groupId: groupId)
        } catch {
            SecureLog.debug("Error removing member")
        }
    }
}
