import SwiftUI
import Combine
import Auth

struct ListReminderSettingsView: View {
    @Binding var list: ShoppingList
    @StateObject private var viewModel = ListReminderSettingsViewModel()
    @Environment(\.dismiss) var dismiss
    
    @State private var notificationType: String = "none"
    @State private var reminderTime = Date()
    @State private var selectedWeekday = 2
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var showingDeleteAlert = false // 削除確認アラート表示用
    
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
        
        _listName = State(initialValue: list.wrappedValue.name)
        _listNotes = State(initialValue: list.wrappedValue.notes ?? "") // 備考初期値
    }
    
    @State private var listName: String
    @State private var listNotes: String
    
    private var isOwner: Bool {
        list.ownerId == SupabaseService.shared.currentUser?.id
    }
    
    private var canEdit: Bool {
        isOwner || (list.allowMemberEdit ?? false)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本設定")) {
                    TextField("リスト名", text: $listName)
                        .disabled(!canEdit)
                    TextField("備考・メモ", text: $listNotes)
                        .disabled(!canEdit)
                }
                
                Section(header: Text("リマインド頻度")) {
                    Picker("頻度", selection: $notificationType) {
                        ForEach(notificationTypes, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    .disabled(!canEdit)
                    
                    if notificationType == "weekly" {
                        Picker("曜日", selection: $selectedWeekday) {
                            ForEach(weekdays, id: \.1) { label, value in
                                Text(label).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!canEdit)
                    }
                    
                    if notificationType == "once" {
                        DatePicker("通知日時", selection: $reminderTime, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.wheel)
                            .disabled(!canEdit)
                    } else if notificationType != "none" {
                        DatePicker("通知時間", selection: $reminderTime, displayedComponents: [.hourAndMinute])
                            .datePickerStyle(.wheel)
                            .disabled(!canEdit)
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
                    .disabled(!canEdit)
                    
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
                                    .foregroundColor(canEdit ? .primary : .secondary)
                                Spacer()
                                if selectedMemberIds.contains(member.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(canEdit ? .blue : .secondary)
                                }
                            }
                        }
                        .disabled(!canEdit)
                    }
                }
                
                if isOwner {
                    Section(header: Text("権限設定")) {
                        Toggle("他のメンバーの編集を許可する", isOn: Binding(
                            get: { list.allowMemberEdit ?? false },
                            set: { list.allowMemberEdit = $0 }
                        ))
                    }
                }
                
                if canEdit {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("リストを削除")
                                Spacer()
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
            .alert("リストの削除", isPresented: $showingDeleteAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("削除", role: .destructive) {
                    deleteList()
                }
            } message: {
                Text("このリストを削除してもよろしいですか？リスト内のすべてのアイテムとリマインド設定が削除され、元に戻すことはできません。")
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
        
        // ローカルの状態を更新する
        var updatedList = list
        updatedList.name = listName
        updatedList.notes = listNotes.isEmpty ? nil : listNotes
        updatedList.reminderInterval = interval
        updatedList.reminderTargets = Array(selectedMemberIds)
        self.list = updatedList
        
        Task {
            await viewModel.updateList(list: list)
            await viewModel.updateReminder(list: list, interval: interval, targets: Array(selectedMemberIds))
            dismiss()
        }
    }
    
    private func deleteList() {
        Task {
            await viewModel.deleteList(list: list)
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
            SecureLog.debug("Failed to load members")
        }
    }
    
    func updateList(list: ShoppingList) async {
        do {
            try await SupabaseService.shared.updateList(list: list)
        } catch {
            SecureLog.debug("Failed to update list")
        }
    }
    
    func updateReminder(list: ShoppingList, interval: NotificationInterval, targets: [UUID]) async {
        do {
            try await SupabaseService.shared.updateListReminder(listId: list.id, interval: interval, targets: targets)
            await NotificationManager.shared.syncAllNotifications()
        } catch {
            SecureLog.debug("Failed to update reminder")
        }
    }
    
    func deleteList(list: ShoppingList) async {
        do {
            try await SupabaseService.shared.deleteList(id: list.id)
            await NotificationManager.shared.syncAllNotifications()
        } catch {
            SecureLog.debug("Failed to delete list")
        }
    }
}
