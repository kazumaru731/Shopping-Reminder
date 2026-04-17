import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dismiss) var dismiss
    @State var item: Item
    let groupId: UUID
    
    @State private var notificationType: String = "none"
    @State private var reminderTime: Date = Date()
    @State private var selectedWeekday: Int = 2
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
        Form {
            Section(header: Text("基本情報")) {
                TextField("商品名", text: $item.name)
                DatePicker("期限", selection: Binding(
                    get: { item.dueDate ?? Date() },
                    set: { item.dueDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .onChange(of: item.dueDate) { _ in
                    adjustReminderIfNeeded()
                }
            }
            
            Section(header: Text("リマインド設定")) {
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
                } else if notificationType != "none" {
                    DatePicker("通知時刻", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }
            }
            
            if notificationType != "none" {
                Section(header: Text("通知対象メンバー")) {
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
        .navigationTitle("アイテム詳細")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveItem()
                }
            }
        }
        .task {
            setupInitialValues()
            await loadMembers()
        }
    }
    
    private func setupInitialValues() {
        if let interval = item.reminderInterval {
            self.notificationType = interval.type
            
            let formatter = DateFormatter()
            if interval.type == "once", let dateStr = interval.date, let timeStr = interval.time {
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                if let date = formatter.date(from: "\(dateStr) \(timeStr)") {
                    self.reminderTime = date
                }
            } else if let timeStr = interval.time {
                formatter.dateFormat = "HH:mm"
                if let date = formatter.date(from: timeStr) {
                    self.reminderTime = date
                }
            }
            self.selectedWeekday = interval.weekday ?? 2
        }
        
        if let targets = item.reminderTargets {
            self.selectedMemberIds = Set(targets)
        }
    }
    
    private func adjustReminderIfNeeded() {
        guard let dueDate = item.dueDate, notificationType == "once" else { return }
        
        var adjustedDate = reminderTime
        let calendar = Calendar.current
        
        while adjustedDate >= dueDate {
            if let nextDate = calendar.date(byAdding: .day, value: -1, to: adjustedDate) {
                adjustedDate = nextDate
            } else {
                break
            }
        }
        
        if adjustedDate != reminderTime {
            reminderTime = adjustedDate
        }
    }
    
    private func loadMembers() async {
        do {
            self.members = try await SupabaseService.shared.fetchGroupMembers(groupId: groupId)
        } catch {
            print("Failed to load members: \(error)")
        }
    }
    
    private func saveItem() {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: reminderTime)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: reminderTime)
        
        let interval = NotificationInterval(
            type: notificationType,
            time: notificationType == "none" ? nil : timeString,
            date: notificationType == "once" ? dateString : nil,
            weekday: notificationType == "weekly" ? selectedWeekday : nil
        )
        
        item.reminderInterval = interval
        item.reminderTargets = Array(selectedMemberIds)
        
        Task {
            do {
                try await SupabaseService.shared.updateItem(item: item)
                await NotificationManager.shared.syncAllNotifications()
                dismiss()
            } catch {
                print("Failed to save item: \(error)")
            }
        }
    }
}
