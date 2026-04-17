import WidgetKit
import SwiftUI

// --- 1. データ構造 ---
struct WidgetItem: Codable, Identifiable {
    let id: UUID
    let name: String
    let listName: String
    let dueDate: Date?
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let items: [WidgetItem]
}

// --- 2. データ提供ロジック ---
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), items: [
            WidgetItem(id: UUID(), name: "テスト商品", listName: "リスト", dueDate: nil)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        let appGroupId = "group.com.kazuma.ShoppingReminder"
        let widgetDataKey = "widget_shopping_items"
        
        var items: [WidgetItem] = []
        if let defaults = UserDefaults(suiteName: appGroupId),
           let data = defaults.data(forKey: widgetDataKey),
           let decoded = try? JSONDecoder().decode([WidgetItem].self, from: data) {
            items = decoded
        }
        
        let entry = SimpleEntry(date: Date(), items: items)
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

// --- 3. View (見た目) ---
struct ShoppingReminderWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🛒 買うもの")
                .font(.headline)
            
            if entry.items.isEmpty {
                Text("なし")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entry.items.prefix(family == .systemSmall ? 3 : 5)) { item in
                    Text("・\(item.name)")
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding()
        .widgetBackground(Color(UIColor.systemBackground))
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

// --- 4. Widget 本体 (EntryPoint) ---
@main  // ← ここで直接起動するように指定
struct ShoppingReminderWidget: Widget {
    let kind: String = "ShoppingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ShoppingReminderWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("お買い物")
        .description("リストを即座にチェック")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
