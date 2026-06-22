import SwiftUI
import Supabase
import PhotosUI

struct ItemDetailView: View {
    @Environment(\.dismiss) var dismiss
    @State var item: Item
    let groupId: UUID
    
    // 共通設定 (作成者用)
    @State private var notificationType: String = "none"
    @State private var reminderTime: Date = Date()
    @State private var selectedWeekday: Int = 2
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var members: [Profile] = []
    
    // 自分専用のカスタム設定
    @State private var isCustomReminderEnabled: Bool = false
    @State private var myNotificationType: String = "none"
    @State private var myReminderTime: Date = Date()
    @State private var mySelectedWeekday: Int = 2
    
    // 編集用
    @State private var hasDeadline = false
    @State private var showingLinkInput = false
    @State private var tempLinkUrl = ""
    
    // 写真選択
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploading = false
    
    // 全画面表示
    @State private var showingFullScreenImage = false
    
    // 自分が作成者かどうか
    private var isCreator: Bool {
        item.creatorId == SupabaseService.shared.currentUser?.id
    }
    
    // 編集可能かどうか（作成者本人、または作成者が許可している場合）
    private var canEdit: Bool {
        isCreator || (item.allowCollaboratorEdit ?? false)
    }
    
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
                    .disabled(!canEdit)
                
                TextField("備考・メモ", text: Binding(
                    get: { item.notes ?? "" },
                    set: { item.notes = $0.isEmpty ? nil : $0 }
                ))
                .disabled(!canEdit)
                
                Toggle("期限あり", isOn: $hasDeadline)
                    .disabled(!canEdit)
                
                if hasDeadline {
                    DatePicker("期限", selection: Binding(
                        get: { item.dueDate ?? Date() },
                        set: { item.dueDate = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                    .disabled(!canEdit)
                } else {
                    HStack {
                        Text("期限")
                        Spacer()
                        Text("期限なし")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("追加情報")) {
                // 商品リンク
                if canEdit || item.linkUrl != nil {
                    HStack {
                        if let urlString = item.linkUrl, let url = URL(string: urlString) {
                            Link(destination: url) {
                                Label("商品ページを開く", systemImage: "arrow.up.right.circle.fill")
                            }
                        } else if canEdit {
                            Text("商品リンク未設定")
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if canEdit {
                            Button(action: {
                                tempLinkUrl = item.linkUrl ?? ""
                                showingLinkInput = true
                            }) {
                                Text(item.linkUrl == nil ? "リンクを追加" : "変更")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // 写真表示
                if let imageUrl = item.imageUrl, let url = URL(string: imageUrl) {
                    VStack(alignment: .leading, spacing: 8) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .clipped()
                                    .cornerRadius(12)
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                                    // タップで全画面
                                    .onTapGesture {
                                        showingFullScreenImage = true
                                    }
                                    // 長押しでポップアップ拡大
                                    .contextMenu {
                                        Button(action: { showingFullScreenImage = true }) {
                                            Label("全画面で表示", systemImage: "arrow.up.left.and.arrow.down.right")
                                        }
                                    } preview: {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 300, height: 300)
                                    }
                            case .failure:
                                Image(systemName: "photo.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray.opacity(0.3))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
                
                // 編集ボタン（作成者または許可されたユーザー）
                if canEdit {
                    HStack {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            HStack {
                                Image(systemName: "photo.badge.plus")
                                Text(item.imageUrl == nil ? "写真を追加" : "写真を変更")
                            }
                            .font(.subheadline)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: selectedPhotoItem) { newItem in
                            Task { await uploadSelectedPhoto(newItem) }
                        }
                        
                        if isUploading {
                            ProgressView().padding(.leading, 8)
                        }
                        
                        Spacer()
                        
                        if item.imageUrl != nil {
                            Button(role: .destructive) {
                                item.imageUrl = nil
                            } label: {
                                Text("写真を削除").font(.subheadline)
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("自分専用のリマインド設定")) {
                Toggle("個別にリマインドを設定する", isOn: $isCustomReminderEnabled)
                
                if isCustomReminderEnabled {
                    Picker("頻度", selection: $myNotificationType) {
                        ForEach(notificationTypes, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    
                    if myNotificationType == "weekly" {
                        Picker("曜日", selection: $mySelectedWeekday) {
                            ForEach(weekdays, id: \.1) { label, value in
                                Text(label).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    if myNotificationType == "once" {
                        DatePicker("通知日時", selection: $myReminderTime, displayedComponents: [.date, .hourAndMinute])
                    } else if myNotificationType != "none" {
                        DatePicker("通知時刻", selection: $myReminderTime, displayedComponents: .hourAndMinute)
                    }
                } else {
                    Text("オフの時は、作成者が設定した共通のリマインド対象に含まれている場合に通知が届きます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("共通のリマインド設定 (作成者のみ編集可)")) {
                Picker("頻度", selection: $notificationType) {
                    ForEach(notificationTypes, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .disabled(!isCreator)
                
                if notificationType == "weekly" {
                    Picker("曜日", selection: $selectedWeekday) {
                        ForEach(weekdays, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!isCreator)
                }
                
                if notificationType == "once" {
                    DatePicker("通知日時", selection: $reminderTime, displayedComponents: [.date, .hourAndMinute])
                        .disabled(!isCreator)
                } else if notificationType != "none" {
                    DatePicker("通知時刻", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .disabled(!isCreator)
                }
            }
            
            if notificationType != "none" {
                Section(header: Text("共通の通知対象メンバー")) {
                    ForEach(members) { member in
                        HStack {
                            Text(member.displayName ?? "名前なし")
                                .foregroundColor(isCreator ? .primary : .secondary)
                            Spacer()
                            if selectedMemberIds.contains(member.id) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(isCreator ? .blue : .secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isCreator {
                                toggleMember(member.id)
                            }
                        }
                    }
                }
            }
            
            if isCreator {
                Section(header: Text("権限設定")) {
                    Toggle("他のメンバーの編集を許可する", isOn: Binding(
                        get: { item.allowCollaboratorEdit ?? false },
                        set: { item.allowCollaboratorEdit = $0 }
                    ))
                }
            }
        }
        .navigationTitle("アイテム詳細")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveItem()
                }
                .disabled(!canEdit)
            }
        }
        .alert("商品リンク設定", isPresented: $showingLinkInput) {
            TextField("https://...", text: $tempLinkUrl)
                .autocapitalization(.none)
                .keyboardType(.URL)
            Button("キャンセル", role: .cancel) { }
            Button("保存") {
                item.linkUrl = tempLinkUrl.isEmpty ? nil : tempLinkUrl
            }
        } message: {
            Text("商品のWebサイトURLを入力してください。")
        }
        .task {
            setupInitialValues()
            await loadMembers()
        }
    }
    
    private func toggleMember(_ id: UUID) {
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }
    
    private func setupInitialValues() {
        // 期限の有無
        self.hasDeadline = item.dueDate != nil
        
        // 共通設定の読み込み
        if let interval = item.reminderInterval {
            self.notificationType = interval.type
            self.reminderTime = parseIntervalDate(interval)
            self.selectedWeekday = interval.weekday ?? 2
        }
        if let targets = item.reminderTargets {
            self.selectedMemberIds = Set(targets)
        }
        
        // 個別設定の読み込み (UserDefaultsからの読み込みを想定)
        loadPersonalSettings()
    }
    
    private func parseIntervalDate(_ interval: NotificationInterval) -> Date {
        let formatter = DateFormatter()
        if interval.type == "once", let dateStr = interval.date, let timeStr = interval.time {
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.date(from: "\(dateStr) \(timeStr)") ?? Date()
        } else if let timeStr = interval.time {
            formatter.dateFormat = "HH:mm"
            return formatter.date(from: timeStr) ?? Date()
        }
        return Date()
    }
    
    private func adjustReminderIfNeeded() {
        // (期限に合わせて通知時間を調整するロジック、必要に応じてmyReminderTimeも調整)
    }
    
    private func loadMembers() async {
        do {
            self.members = try await SupabaseService.shared.fetchGroupMembers(groupId: groupId)
        } catch {
            SecureLog.debug("Failed to load members")
        }
    }
    
    private func loadPersonalSettings() {
        let key = "personal_reminder_\(item.id.uuidString)"
        if let data = UserDefaults.standard.data(forKey: key),
           let settings = try? JSONDecoder().decode(NotificationInterval.self, from: data) {
            self.isCustomReminderEnabled = true
            self.myNotificationType = settings.type
            self.myReminderTime = parseIntervalDate(settings)
            self.mySelectedWeekday = settings.weekday ?? 2
        }
    }
    
    private func saveItem() {
        if !hasDeadline {
            item.dueDate = nil
        }
        
        if isCreator {
            item.reminderInterval = createInterval(type: notificationType, time: reminderTime, weekday: selectedWeekday)
            item.reminderTargets = Array(selectedMemberIds)
        }
        
        // 個別設定の保存 (端末内)
        let key = "personal_reminder_\(item.id.uuidString)"
        if isCustomReminderEnabled {
            let myInterval = createInterval(type: myNotificationType, time: myReminderTime, weekday: mySelectedWeekday)
            if let encoded = try? JSONEncoder().encode(myInterval) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        Task {
            do {
                if canEdit {
                    try await SupabaseService.shared.updateItem(item: item)
                }
                // 通知を再スケジュール
                await NotificationManager.shared.syncAllNotifications()
                dismiss()
            } catch {
                SecureLog.debug("Failed to save item")
            }
        }
    }
    
    private func createInterval(type: String, time: Date, weekday: Int) -> NotificationInterval {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: time)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: time)
        
        return NotificationInterval(
            type: type,
            time: type == "none" ? nil : timeString,
            date: type == "once" ? dateString : nil,
            weekday: type == "weekly" ? weekday : nil
        )
    }
    
    private func uploadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        isUploading = true
        defer { isUploading = false }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let url = try await SupabaseService.shared.uploadItemImage(data: data, fileName: "item.jpg")
                await MainActor.run {
                    self.item.imageUrl = url
                }
            }
        } catch {
            SecureLog.debug("Failed to upload image")
        }
    }
}

// 画像全画面表示用ビュー
struct FullScreenImageView: View {
    let imageUrl: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}
