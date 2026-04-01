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
    }

    var isImage: Bool { fileType.hasPrefix("image/") }
    var isVideo: Bool { fileType.hasPrefix("video/") }
    var isText: Bool { contentType == "text" }
    var isLink: Bool { contentType == "link" }

    var displayType: String {
        if isImage { return "Photo" }
        if isVideo { return "Video" }
        if isText { return "Message" }
        if isLink { return "Link" }
        return "File"
    }
}

struct InviteResponse: Codable {
    let inviteToken: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case inviteToken = "invite_token"
        case expiresAt = "expires_at"
    }
}

struct RedeemResponse: Codable {
    let userID: String?
    let name: String?
    let token: String?
    let contact: RedeemContact?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name, token, contact
    }
}

struct RedeemContact: Codable {
    let id: String
    let name: String
}

struct QRPayload: Codable, Identifiable {
    var id: String { invite }
    let url: String
    let invite: String

    enum CodingKeys: String, CodingKey {
        case url = "u"
        case invite = "i"
    }
}
