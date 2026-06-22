import SwiftUI
import PhotosUI

struct AddItemView: View {
    @Environment(\.dismiss) var dismiss
    let list: ShoppingList
    @ObservedObject var viewModel: ItemListViewModel
    
    @State private var name = ""
    @State private var dueDate = Date()
    @State private var hasDeadline = false
    @State private var linkUrl = ""
    @State private var imageUrl = ""
    @State private var notes = "" // 備考欄
    
    // 写真選択
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploading = false
    
    // リマインド項目
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
                    TextField("たまご、牛乳など", text: $name)
                    TextField("備考・メモ（例: 安ければメーカー問わず）", text: $notes)
                }
                
                Section(header: Text("期日設定")) {
                    Toggle("期限あり", isOn: $hasDeadline)
                    
                    if hasDeadline {
                        DatePicker("期日", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .onChange(of: dueDate) { _ in
                                adjustReminderIfNeeded()
                            }
                    }
                }
                
                Section(header: Text("追加情報（任意）")) {
                    // 商品リンク入力
                    TextField("商品リンク (URL)", text: $linkUrl)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.none)
                        #endif
                    
                    Divider().padding(.vertical, 4)
                    
                    // 写真選択
                    HStack {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label(imageUrl.isEmpty ? "写真を選択" : "写真を変更", systemImage: "photo.badge.plus")
                        }
                        .onChange(of: selectedPhotoItem) { newItem in
                            Task { await uploadSelectedPhoto(newItem) }
                        }
                        
                        if isUploading {
                            ProgressView().padding(.leading, 8)
                        } else if !imageUrl.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        if !imageUrl.isEmpty {
                            Button(role: .destructive) {
                                imageUrl = ""
                                selectedPhotoItem = nil
                            } label: {
                                Text("削除").font(.caption)
                            }
                        }
                    }
                    
                    if !imageUrl.isEmpty {
                        AsyncImage(url: URL(string: imageUrl)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 100)
                                .cornerRadius(8)
                        } placeholder: {
                            ProgressView()
                        }
                    }
                }
                
                Section(header: Text("リマインド設定（デフォルトはリスト設定）")) {
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
            .navigationTitle("アイテム追加")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加") {
                        saveItem()
                    }
                    .disabled(name.isEmpty || isUploading)
                }
            }
            .task {
                await loadMembers()
                setupDefaults()
            }
        }
    }
    
    private func adjustReminderIfNeeded() {
        guard hasDeadline, notificationType == "once" else { return }
        
        // リマインドが期限以降になっている場合、時間を維持したまま期限前になるまで日付を遡る
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
    
    private func setupDefaults() {
        // リストのリマインド設定をデフォルトとしてセット
        if let interval = list.reminderInterval {
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
            
            // 初回セットアップ時も必要なら調整
            if notificationType == "once" {
                adjustReminderIfNeeded()
            }
        }
        
        if let targets = list.reminderTargets {
            self.selectedMemberIds = Set(targets)
        } else {
            // リストにターゲットがない場合は、現在の全メンバーをデフォルトにする
            self.selectedMemberIds = Set(members.map { $0.id })
        }
    }
    
    private func loadMembers() async {
        do {
            self.members = try await SupabaseService.shared.fetchGroupMembers(groupId: list.groupId)
        } catch {
            #if DEBUG
            SecureLog.debug("Failed to load members")
            #endif
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
        
        Task {
            await viewModel.addItem(
                listId: list.id, 
                name: name, 
                dueDate: hasDeadline ? dueDate : nil,
                interval: interval,
                targets: Array(selectedMemberIds),
                linkUrl: linkUrl.isEmpty ? nil : linkUrl,
                imageUrl: imageUrl.isEmpty ? nil : imageUrl,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
        }
    }
    
    private func uploadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        isUploading = true
        defer { isUploading = false }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let url = try await SupabaseService.shared.uploadItemImage(data: data, fileName: "item.jpg")
                await MainActor.run {
                    self.imageUrl = url
                }
            }
        } catch {
            #if DEBUG
            SecureLog.debug("Failed to upload image")
            #endif
        }
    }
}
