import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var displayName = ""
    @State private var notifyOnListDelete = true
    @State private var notifyOnItemDelete = true
    @State private var notifyOnGroupLeave = true
    @State private var showingDeleteAlert = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    @AppStorage("deadline_warning_hours") private var warningHours = 24
    @AppStorage("deadline_critical_hours") private var criticalHours = 5
    
    private var warningHoursStorage: Binding<Int> {
        Binding(
            get: { warningHours },
            set: { 
                warningHours = $0
                if criticalHours >= $0 {
                    criticalHours = max(1, $0 - 1)
                }
            }
        )
    }
    
    private var criticalHoursStorage: Binding<Int> {
        Binding(
            get: { criticalHours },
            set: { criticalHours = min($0, warningHours - 1) }
        )
    }
    
    private func formatHours(_ hours: Int) -> String {
        if hours % 24 == 0 {
            return "\(hours / 24)日前"
        } else if hours < 24 {
            return "\(hours)時間前"
        } else {
            return "\(hours / 24)日と\(hours % 24)時間前"
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("プロフィール")) {
                    TextField("表示名", text: $displayName)
                }
                
                Section(header: Text("通知")) {
                    NavigationLink(destination: NotificationSettingsView()) {
                        Label("通知設定", systemImage: "bell.badge")
                    }
                }
                
                Section(header: Text("期限表示の色分け")) {
                    Stepper(value: warningHoursStorage, in: 1...168) {
                        VStack(alignment: .leading) {
                            Text("注意 (黄色): \(formatHours(warningHoursStorage.wrappedValue))")
                            Text("期限が近づくと黄色で表示します").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Stepper(value: criticalHoursStorage, in: 1...warningHoursStorage.wrappedValue - 1) {
                        VStack(alignment: .leading) {
                            Text("緊急 (赤色): \(formatHours(criticalHoursStorage.wrappedValue))")
                            Text("さらに近づくと赤色で表示します").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button("設定を保存") {
                        Task {
                            do {
                                try await SupabaseService.shared.updateProfile(
                                    displayName: displayName,
                                    notifyOnListDelete: notifyOnListDelete,
                                    notifyOnItemDelete: notifyOnItemDelete,
                                    notifyOnGroupLeave: notifyOnGroupLeave
                                )
                                alertMessage = "設定を更新しました"
                                showingAlert = true
                            } catch {
                                alertMessage = "設定の更新に失敗しました。時間をおいてもう一度お試しください。"
                                showingAlert = true
                            }
                        }
                    }
                }
                
                Section(header: Text("アカウント")) {
                    Button("アカウントを削除") {
                        showingDeleteAlert = true
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("サポートと法規")) {
                    Link(destination: URL(string: "https://kazumaru731.github.io/Shopping-Reminder/terms")!) {
                        Label("利用規約", systemImage: "doc.text")
                    }
                    Link(destination: URL(string: "https://kazumaru731.github.io/Shopping-Reminder/privacy")!) {
                        Label("プライバシーポリシー", systemImage: "shield")
                    }
                    Link(destination: URL(string: "https://kazumaru731.github.io/Shopping-Reminder/support")!) {
                        Label("お問い合わせ・フィードバック", systemImage: "envelope")
                    }
                    NavigationLink(destination: Text("ここにライセンス一覧を表示するか、外部リンクへ飛ばします")) {
                        Label("ライセンス", systemImage: "info.circle")
                    }
                }
                
                Section(header: Text("アプリについて"), footer: Text("買い物リマインダー v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")) {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.secondary)
                    }
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
                            alertMessage = "アカウント削除に失敗しました。時間をおいてもう一度お試しください。"
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
                // プロフィール情報を取得
                do {
                    if let profile = try await SupabaseService.shared.fetchCurrentProfile() {
                        displayName = profile.displayName ?? ""
                        notifyOnListDelete = profile.notifyOnListDelete ?? true
                        notifyOnItemDelete = profile.notifyOnItemDelete ?? true
                        notifyOnGroupLeave = profile.notifyOnGroupLeave ?? true
                    }
                } catch {
                    #if DEBUG
                    SecureLog.debug("Error fetching profile")
                    #endif
                }
            }
        }
    }
}
