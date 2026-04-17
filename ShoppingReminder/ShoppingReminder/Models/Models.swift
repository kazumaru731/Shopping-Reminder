import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String?
    var avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

struct Group: Codable, Identifiable {
    let id: UUID
    var name: String
    let inviteCode: String
    let ownerId: UUID
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }
}

struct ShoppingList: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    var name: String
    let ownerId: UUID
    let createdAt: Date
    var reminderInterval: NotificationInterval?
    var reminderTargets: [UUID]?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case groupId = "group_id"
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case reminderInterval = "reminder_interval"
        case reminderTargets = "reminder_targets"
    }
}

struct Item: Codable, Identifiable {
    let id: UUID
    let listId: UUID
    var name: String
    var dueDate: Date?
    var isPurchased: Bool
    var purchaserId: UUID?
    var planningPurchaserId: UUID?
    var purchaser: Profile?
    var creatorId: UUID?
    var creator: Profile?
    var reminderInterval: NotificationInterval?
    var reminderTargets: [UUID]?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case listId = "list_id"
        case dueDate = "due_date"
        case isPurchased = "is_purchased"
        case purchaserId = "purchaser_id"
        case planningPurchaserId = "planning_purchaser_id"
        case creatorId = "creator_id"
        case reminderInterval = "reminder_interval"
        case reminderTargets = "reminder_targets"
        case purchaser
        case creator
    }
}

struct NotificationInterval: Codable, Equatable {
    var type: String // "none", "once", "daily", "weekly"
    var time: String? // "HH:mm"
    var date: String? // "yyyy-MM-dd"
    var weekday: Int? // 1: Sunday, ..., 7: Saturday
}
