import SwiftUI
import Combine

struct ListReminderSettingsView: View {
    @Binding var list: ShoppingList
    @StateObject private var viewModel = ListReminderSettingsViewModel()
    @Environment(\.dismiss) var dismiss
    
    @State private var notificationType: String = "none"
    @State private var reminderTime = Date()
    @State private var selectedWeekday = 2
    @State private var selectedMemberIds: Set<UUID> = []
    
    let notificationTypes = [
        ("なし", "none"),
        ("一回のみ", "once"),
        ("毎日", "daily"),
        ("毎週", "weekly")
    ]
    
    let weekdays = [
        ("日", 1), ("月", 2), ("火", 3), ("水", 4), ("木", 5), ("金", 6), ("土", 7)
    ]
    
    init(list: Binding<ShoppingList>) {
        self._list = list
        _notificationType = State(initialValue: list.wrappedValue.reminderInterval?.type ?? "none")
        _selectedMemberIds = State(initialValue: Set(list.wrappedValue.reminderTargets ?? []))
        
        if let dateStr = list.wrappedValue.reminderInterval?.date, let timeStr = list.wrappedValue.reminderInterval?.time {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            if let date = formatter.date(from: "\(dateStr) \(timeStr)") {
                _reminderTime = State(initialValue: date)
            }
        } else if let timeStr = list.wrappedValue.reminderInterval?.time {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            if let date = formatter.date(from: timeStr) {
                _reminderTime = State(initialValue: date)
            }
        }
        
        if let weekday = list.wrappedValue.reminderInterval?.weekday {
            _selectedWeekday = State(initialValue: weekday)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
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
                
                Section(header: Text("通知対象メンバー")) {
                    Toggle("全員", isOn: Binding(
                        get: { selectedMemberIds.count == viewModel.members.count && !viewModel.members.isEmpty },
                        set: { isAll in
                            if isAll {
                                selectedMemberIds = Set(viewModel.members.map { $0.id })
                            } else {
                                selectedMemberIds = []
                            }
                        }
                    ))
                    
                    ForEach(viewModel.members) { member in
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
            .navigationTitle("リマインド設定")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveSettings()
                    }
                }
            }
            .task {
                await viewModel.loadMembers(groupId: list.groupId)
                // 初期ロード時にターゲットが空の場合のケアなどが必要ならここで
            }
        }
    }
    
    private func saveSettings() {
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
        
        // ローカルの状態を更新する（これにより ItemListView の list が更新され、次のアイテム追加時のデフォルトになる）
        var updatedList = list
        updatedList.reminderInterval = interval
        updatedList.reminderTargets = Array(selectedMemberIds)
        self.list = updatedList
        
        Task {
            await viewModel.updateReminder(list: list, interval: interval, targets: Array(selectedMemberIds))
            dismiss()
        }
    }
}

class ListReminderSettingsViewModel: ObservableObject {
    @Published var members: [Profile] = []
    
    func loadMembers(groupId: UUID) async {
        do {
            self.members = try await SupabaseService.shared.fetchGroupMembers(groupId: groupId)
        } catch {
            print("Failed to load members: \(error)")
        }
    }
    
    func updateReminder(list: ShoppingList, interval: NotificationInterval, targets: [UUID]) async {
        do {
            try await SupabaseService.shared.updateListReminder(listId: list.id, interval: interval, targets: targets)
            await NotificationManager.shared.syncAllNotifications()
        } catch {
            print("Failed to update reminder: \(error)")
        }
    }
}
