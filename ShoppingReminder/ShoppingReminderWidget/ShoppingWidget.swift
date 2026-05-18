import WidgetKit
import SwiftUI
import AppIntents

// --- 1. 共通のデータ構造 ---
struct WidgetItem: Codable, Identifiable {
    let id: UUID
    let name: String
    let listName: String
    let listId: UUID
    let dueDate: Date?
}

// OSバージョンに関わらず使用できる共通のエントリ
struct WidgetEntry: TimelineEntry {
    let date: Date
    let items: [WidgetItem]
    let selectedListName: String?
}

// --- 2. iOS 17+ 専用の定義 (SelectListIntent) ---
@available(iOS 17.0, *)
struct SelectListIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "表示リストの選択"
    static var description = IntentDescription("ウィジェットに表示する買い物リストを選択します。")

    @Parameter(title: "リスト")
    var list: ShoppingListEntity?

    func perform() async throws -> some IntentResult {
        return .result()
    }

    struct ShoppingListEntity: AppEntity, Identifiable {
        let id: UUID
        let name: String
        static var typeDisplayRepresentation: TypeDisplayRepresentation = "買い物リスト"
        static var defaultQuery = ShoppingListQuery()
        var displayRepresentation: DisplayRepresentation {
            DisplayRepresentation(title: "\(name)")
        }
    }
}

@available(iOS 17.0, *)
struct ShoppingListQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SelectListIntent.ShoppingListEntity] {
        return fetchLists().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [SelectListIntent.ShoppingListEntity] {
        return fetchLists()
    }
    private func fetchLists() -> [SelectListIntent.ShoppingListEntity] {
        if let defaults = UserDefaults(suiteName: AppConstants.appGroupId),
           let data = defaults.data(forKey: AppConstants.widgetListsKey),
           let decoded = try? JSONDecoder().decode([WidgetListInfo].self, from: data) {
            return decoded.map { SelectListIntent.ShoppingListEntity(id: $0.id, name: $0.name) }
        }
        return []
    }
}

struct WidgetListInfo: Codable {
    let id: UUID
    let name: String
}

// --- 3. データ取得ユーティリティ ---
struct WidgetDataFetcher {
    static func fetchItems(for listId: UUID?) -> [WidgetItem] {
        if let defaults = UserDefaults(suiteName: AppConstants.appGroupId),
           let data = defaults.data(forKey: AppConstants.widgetDataKey),
           let decoded = try? JSONDecoder().decode([WidgetItem].self, from: data) {
            if let listId = listId {
                return decoded.filter { $0.listId == listId }
            } else {
                return decoded
            }
        }
        return []
    }
}

// --- 4. タイムラインプロバイダー ---

// iOS 17+ 用 (AppIntent)
@available(iOS 17.0, *)
struct AppIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), items: [], selectedListName: nil)
    }
    func snapshot(for configuration: SelectListIntent, in context: Context) async -> WidgetEntry {
        let items = WidgetDataFetcher.fetchItems(for: configuration.list?.id)
        return WidgetEntry(date: Date(), items: items, selectedListName: configuration.list?.name)
    }
    func timeline(for configuration: SelectListIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let items = WidgetDataFetcher.fetchItems(for: configuration.list?.id)
        let entry = WidgetEntry(date: Date(), items: items, selectedListName: configuration.list?.name)
        return Timeline(entries: [entry], policy: .atEnd)
    }
}

// iOS 16用 (Static)
struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), items: [], selectedListName: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> ()) {
        completion(placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> ()) {
        let items = WidgetDataFetcher.fetchItems(for: nil)
        let entry = WidgetEntry(date: Date(), items: items, selectedListName: nil)
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}

// --- 5. View (共通の見た目) ---
struct ShoppingReminderWidgetEntryView : View {
    var entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.selectedListName ?? "🛒 買うもの")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            
            if entry.items.isEmpty {
                Spacer()
                Text("未購入のアイテムはありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                let displayItems = entry.items.prefix(family == .systemSmall ? 3 : 5)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displayItems) { item in
                        HStack(alignment: .top, spacing: 4) {
                            Text("・")
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                
                                if let due = item.dueDate {
                                    Text(formatDueDate(due))
                                        .font(.system(size: 10))
                                        .foregroundColor(dueDateColor(due))
                                }
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .widgetBackground(Color(UIColor.systemBackground))
    }
    
    private func formatDueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "今日 HH:mm"
        } else if Calendar.current.isDateInTomorrow(date) {
            formatter.dateFormat = "明日 HH:mm"
        } else {
            formatter.dateFormat = "M/d HH:mm"
        }
        return formatter.string(from: date)
    }
    
    private func dueDateColor(_ date: Date) -> Color {
        let diff = date.timeIntervalSinceNow
        if diff < 0 { return .red }
        if diff < 3600 * 5 { return .orange }
        return .secondary
    }
}

extension View {
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(iOS 17.0, *) {
            return self.containerBackground(for: .widget) { backgroundView }
        } else {
            return self.background(backgroundView)
        }
    }
}

// --- 6. Widget 本体 ---

// iOS 17+ 用
@available(iOS 17.0, *)
struct AppIntentShoppingWidget: Widget {
    let kind: String = "ShoppingWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectListIntent.self, provider: AppIntentProvider()) { entry in
            ShoppingReminderWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("お買い物リスト")
        .description("リストのアイテムを期限順に表示。長押しでリストを選択できます。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// iOS 16用
struct StaticShoppingWidget: Widget {
    let kind: String = "ShoppingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticProvider()) { entry in
            ShoppingReminderWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("お買い物リスト")
        .description("リストのアイテムを期限順に表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ShoppingReminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        // WidgetBundle内での if #available エラーを回避するため、
        // コンパイルが通る構成にします。
        #if swift(>=5.9) && canImport(AppIntents)
        if #available(iOS 17.0, *) {
            return AppIntentShoppingWidget()
        }
        #endif
        return StaticShoppingWidget()
    }
}
