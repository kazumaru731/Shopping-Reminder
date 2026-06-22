import SwiftUI
import Combine
import Auth

struct GroupSettingsView: View {
    @State var group: Group
    @Environment(\.dismiss) var dismiss
    @State private var groupName: String
    @State private var allowMemberEdit: Bool
    
    private var isOwner: Bool {
        group.ownerId == SupabaseService.shared.currentUser?.id
    }
    
    private var canEdit: Bool {
        isOwner || (group.allowMemberEdit ?? false)
    }
    
    init(group: Group) {
        self.group = group
        _groupName = State(initialValue: group.name)
        _allowMemberEdit = State(initialValue: group.allowMemberEdit ?? false)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本情報")) {
                    TextField("グループ名", text: $groupName)
                        .disabled(!canEdit)
                }
                
                Section(header: Text("招待情報")) {
                    HStack {
                        Text("招待コード")
                        Spacer()
                        Text(group.inviteCode)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        
                        Button(action: {
                            UIPasteboard.general.string = group.inviteCode
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
                
                if isOwner {
                    Section(header: Text("権限設定")) {
                        Toggle("他のメンバーの編集を許可する", isOn: $allowMemberEdit)
                    }
                }
            }
            .navigationTitle("グループ設定")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveGroup()
                    }
                    .disabled(!canEdit)
                }
            }
        }
    }
    
    private func saveGroup() {
        var updatedGroup = group
        updatedGroup.name = groupName
        updatedGroup.allowMemberEdit = allowMemberEdit
        
        Task {
            do {
                try await SupabaseService.shared.updateGroup(group: updatedGroup)
                dismiss()
            } catch {
                SecureLog.debug("Failed to update group")
            }
        }
    }
}
