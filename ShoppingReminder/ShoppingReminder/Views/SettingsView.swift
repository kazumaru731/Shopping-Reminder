import SwiftUI
import Auth

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var displayName = ""
    @State private var showingDeleteAlert = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("プロフィール")) {
                    TextField("表示名", text: $displayName)
                    Button("名前を保存") {
                        Task {
                            do {
                                try await SupabaseService.shared.updateProfile(displayName: displayName)
                                alertMessage = "名前を更新しました"
                                showingAlert = true
                            } catch {
                                alertMessage = "エラー: \(error.localizedDescription)"
                                showingAlert = true
                            }
                        }
                    }
                }
                
                Section(header: Text("アカウント")) {
                    Button("ログアウト") {
                        Task {
                            try? await SupabaseService.shared.signOut()
                            dismiss()
                        }
                    }
                    .foregroundColor(.blue)
                    
                    Button("アカウントを削除") {
                        showingDeleteAlert = true
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("アプリについて"), footer: Text("Shopping Reminder v1.0.0")) {
                    Text("バージョン 1.0.0")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .alert("アカウント削除", isPresented: $showingDeleteAlert) {
                Button("削除する", role: .destructive) {
                    Task {
                        do {
                            try await SupabaseService.shared.deleteAccount()
                            dismiss()
                        } catch {
                            alertMessage = "削除に失敗しました: \(error.localizedDescription)"
                            showingAlert = true
                        }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("アカウントを削除すると、あなたが作成したすべてのリストとアイテムが永久に削除されます。この操作は取り消せません。")
            }
            .alert("通知", isPresented: $showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .task {
                // 現在の名前を初期値にセット
                if let user = SupabaseService.shared.currentUser {
                    if let json = user.userMetadata["display_name"],
                       case let .string(name) = json {
                        displayName = name
                    }
                }
            }
        }
    }
}
