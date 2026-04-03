import Foundation

struct BeamletUser: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

struct BeamletFile: Codable, Identifiable, Hashable {
    let id: String
    let senderID: String
    let recipientID: String
    let filename: String
    let fileType: String
    let fileSize: Int64
    let contentType: String
    let textContent: String?
    let message: String?
    let read: Bool
    let pinned: Bool?
    let expiresAt: Date?
    let createdAt: Date?
    let senderName: String?
    let recipientName: String?

    enum CodingKeys: String, CodingKey {
        case id, filename, message, read, pinned
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case fileType = "file_type"
        case fileSize = "file_size"
        case contentType = "content_type"
        case textContent = "text_content"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case senderName = "sender_name"
        case recipientName = "recipient_name"
    }
}
