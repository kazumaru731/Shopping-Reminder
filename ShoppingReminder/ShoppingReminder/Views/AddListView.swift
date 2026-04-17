import SwiftUI
import Combine

struct AddListView: View {
    let groupId: UUID
    @ObservedObject var viewModel: GroupHomeViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var notificationType = "none"
    @State private var reminderTime = Date()
    @State private var selectedWeekday = 2
    @State private var selectedMemberIds: Set<UUID> = []
    
    @State private var members: [Profile] = []
    
    let notificationTypes = [
        ("なし", "none"),
        ("一回のみ", "once"),
        ("毎日", "daily"),
        ("毎週", "weekly")
    ]
    
    let weekdays = [
        ("日", 1), ("月", 2), ("火", 3), ("水", 4), ("木", 5), ("金", 6), ("土", 7)
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本情報")) {
                    TextField("リスト名（例: スーパー、ドラッグストア）", text: $name)
                }
                
                Section(header: Text("リマインド頻度")) {
                    Picker("頻度", selection: $notificationType) {
                        ForEach(notificationTypes, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    
                    if notificationType == "weekly" {
                        Picker("曜日", selection: $selectedWeekday) {
                            ForEach(weekdays, id: \.1) { label, value in
                                Text(label).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    if notificationType == "once" {
                        DatePicker("通知日時", selection: $reminderTime, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.wheel)
                    } else if notificationType != "none" {
                        DatePicker("通知時間", selection: $reminderTime, displayedComponents: [.hourAndMinute])
                            .datePickerStyle(.wheel)
                    }
                }
                
                if notificationType != "none" {
                    Section(header: Text("通知対象メンバー")) {
                        Toggle("全員", isOn: Binding(
                            get: { selectedMemberIds.count == members.count && !members.isEmpty },
                            set: { isAll in
                                if isAll {
                                    selectedMemberIds = Set(members.map { $0.id })
                                } else {
                                    selectedMemberIds = []
                                }
                            }
                        ))
                        
                        ForEach(members) { member in
                            Button(action: {
                                if selectedMemberIds.contains(member.id) {
                                    selectedMemberIds.remove(member.id)
                                } else {
                                    selectedMemberIds.insert(member.id)
                                }
                            }) {
                                HStack {
                                    Text(member.displayName ?? "名前なし")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedMemberIds.contains(member.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("新しいリスト")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("作成") {
                        saveList()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .task {
                await loadMembers()
                // 初期状態は全員選択
                selectedMemberIds = Set(members.map { $0.id })
            }
        }
    }
    
    private func loadMembers() async {
        do {
            self.members = try await SupabaseService.shared.fetchGroupMembers(groupId: groupId)
            // メンバー読み込み後に再度全員選択をセット
            if selectedMemberIds.isEmpty {
                selectedMemberIds = Set(members.map { $0.id })
            }
        } catch {
            print("Failed to load members: \(error)")
        }
    }
    
    private func saveList() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeString = formatter.string(from: reminderTime)
        
        let dateFormater = DateFormatter()
        dateFormater.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormater.string(from: reminderTime)
        
        let interval = NotificationInterval(
            type: notificationType,
            time: notificationType == "none" ? nil : timeString,
            date: notificationType == "once" ? dateString : nil,
            weekday: notificationType == "weekly" ? selectedWeekday : nil
        )
        
        Task {
            await viewModel.createList(
                groupId: groupId, 
                name: name, 
                interval: interval, 
                targets: Array(selectedMemberIds)
            )
            dismiss()
        }
    }
}
