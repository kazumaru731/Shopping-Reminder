import SwiftUI

struct NotificationSettingsView: View {
    @State private var selectedTab = 0
    
    // グループ
    @AppStorage("notify_group_create_enabled") private var groupCreate = true
    @AppStorage("notify_group_leave_enabled") private var groupLeave = true
    
    // リスト
    @AppStorage("notify_list_add_enabled") private var listAdd = true
    @AppStorage("notify_list_delete_enabled") private var listDelete = true
    
    // アイテム
    @AppStorage("notify_item_add_enabled") private var itemAdd = true
    @AppStorage("notify_item_delete_enabled") private var itemDelete = true
    @AppStorage("notify_item_reserved_enabled") private var itemReserved = true
    @AppStorage("notify_item_purchased_enabled") private var itemPurchased = true

    var body: some View {
        VStack {
            Picker("カテゴリー", selection: $selectedTab) {
                Text("グループ").tag(0)
                Text("リスト").tag(1)
                Text("アイテム").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            Form {
                if selectedTab == 0 {
                    Section(header: Text("グループの通知")) {
                        Toggle("グループ作成時", isOn: $groupCreate)
                        Toggle("グループ退出時", isOn: $groupLeave)
                    }
                } else if selectedTab == 1 {
                    Section(header: Text("リストの通知")) {
                        Toggle("リスト追加時", isOn: $listAdd)
                        Toggle("リスト削除時", isOn: $listDelete)
                    }
                } else {
                    Section(header: Text("アイテムの通知")) {
                        Toggle("アイテム追加時", isOn: $itemAdd)
                        Toggle("アイテム削除時", isOn: $itemDelete)
                        Toggle("購入予約時", isOn: $itemReserved)
                        Toggle("購入完了時", isOn: $itemPurchased)
                    }
                }
            }
        }
        .navigationTitle("通知設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        NotificationSettingsView()
    }
}
