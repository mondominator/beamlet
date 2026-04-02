import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case notAuthenticated
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .notAuthenticated: return "Not authenticated"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code, let message): return message ?? "HTTP error \(code)"
        case .decodingError(let error): return "Decode error: \(error.localizedDescription)"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}

@Observable
class BeamletAPI {
    private let authRepository: AuthRepository
    private let session: URLSession
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, session: URLSession = .shared) {
        self.authRepository = authRepository
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Try ISO 8601 with fractional seconds first, then without
            let formatters = [
                ISO8601DateFormatter(),
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
            ]
            for formatter in formatters {
                if let date = formatter.date(from: string) { return date }
            }
            // Try Go's default time format
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSZ"
            df.locale = Locale(identifier: "en_US_POSIX")
            if let date = df.date(from: string) { return date }
            df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSSSS Z"
            if let date = df.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(string)")
        }
    }

    // MARK: - Base Request

    private func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        guard let baseURL = authRepository.serverURL else {
            throw APIError.notAuthenticated
        }
        guard let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let path = endpoint.hasPrefix("/") ? String(endpoint.dropFirst()) : endpoint
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let deviceToken = authRepository.deviceToken {
            request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
        }

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            await MainActor.run { authRepository.clear() }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Session expired")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            if let json = String(data: data, encoding: .utf8) {
                print("Decode error for \(T.self): \(error)")
                print("Response: \(json.prefix(500))")
            }
            #endif
            throw APIError.decodingError(error)
        }
    }

    private func requestVoid(
        _ endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws {
        guard let baseURL = authRepository.serverURL else {
            throw APIError.notAuthenticated
        }
        guard let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        let path = endpoint.hasPrefix("/") ? endpoint : "/\(endpoint)"
        guard let url = URL(string: base + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let deviceToken = authRepository.deviceToken {
            request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
        }

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            await MainActor.run { authRepository.clear() }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Session expired")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    // MARK: - Users

    func listUsers() async throws -> [BeamletUser] {
        try await request("/api/contacts")
    }

    // MARK: - Device Registration

    func registerDevice(apnsToken: String, platform: String = "ios") async throws {
        let body = try JSONEncoder().encode(["apns_token": apnsToken, "platform": platform])
        try await requestVoid("/api/auth/register-device", method: "POST", body: body)
    }

    // MARK: - Files

    func listFiles(limit: Int = 20, offset: Int = 0) async throws -> [BeamletFile] {
        try await request("/api/files", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
    }

    func listSentFiles(limit: Int = 20, offset: Int = 0) async throws -> [BeamletFile] {
        try await request("/api/files/sent", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
    }

    func markRead(_ fileID: String) async throws {
        try await requestVoid("/api/files/\(fileID)/read", method: "PUT")
    }

    struct PinResponse: Codable {
        let pinned: Bool
    }

    func togglePin(_ fileID: String) async throws -> Bool {
        let response: PinResponse = try await request("/api/files/\(fileID)/pin", method: "PUT")
        return response.pinned
    }

    func deleteFile(_ fileID: String) async throws {
        try await requestVoid("/api/files/\(fileID)", method: "DELETE")
    }

    func downloadFile(_ fileID: String) async throws -> Data {
        guard let baseURL = authRepository.serverURL,
              let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let url = baseURL.appendingPathComponent("api/files/\(fileID)")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.invalidResponse
        }
        return data
    }

    func thumbnailURL(for fileID: String) -> URL? {
        guard let baseURL = authRepository.serverURL else { return nil }
        return baseURL.appendingPathComponent("api/files/\(fileID)/thumbnail")
    }

    var authHeaders: [String: String] {
        guard let token = authRepository.token else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    // MARK: - Upload

    func uploadFile(
        recipientID: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        message: String? = nil,
        expiryDays: Int? = nil
    ) async throws -> BeamletFile {
        guard let baseURL = authRepository.serverURL,
              let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let url = baseURL.appendingPathComponent("api/files")
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let deviceToken = authRepository.deviceToken {
            request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
        }

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "recipient_id", value: recipientID)
        if let message = message, !message.isEmpty {
            body.appendMultipart(boundary: boundary, name: "message", value: message)
        }
        if let expiryDays {
            body.appendMultipart(boundary: boundary, name: "expiry_days", value: "\(expiryDays)")
        }
        body.appendMultipartFile(boundary: boundary, name: "file", filename: filename, mimeType: mimeType, data: fileData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: http.statusCode, message: msg)
        }

        return try decoder.decode(BeamletFile.self, from: data)
    }

    func uploadText(
        recipientID: String,
        text: String,
        contentType: String = "text"
    ) async throws -> BeamletFile {
        guard let baseURL = authRepository.serverURL,
              let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let url = baseURL.appendingPathComponent("api/files")
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let deviceToken = authRepository.deviceToken {
            request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
        }

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "recipient_id", value: recipientID)
        body.appendMultipart(boundary: boundary, name: "content_type", value: contentType)
        body.appendMultipart(boundary: boundary, name: "text_content", value: text)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: http.statusCode, message: msg)
        }

        return try decoder.decode(BeamletFile.self, from: data)
    }

    // MARK: - Invites

    func createInvite() async throws -> InviteResponse {
        try await request("/api/invites", method: "POST")
    }

    func redeemInvite(serverURL: URL, inviteToken: String, name: String) async throws -> RedeemResponse {
        let url = serverURL.appendingPathComponent("api/invites/redeem")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "invite_token": inviteToken,
            "name": name,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: msg
            )
        }

        return try decoder.decode(RedeemResponse.self, from: data)
    }

    func redeemInviteAsExistingUser(inviteToken: String) async throws -> RedeemResponse {
        guard let baseURL = authRepository.serverURL,
              let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let url = baseURL.appendingPathComponent("api/invites/redeem")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["invite_token": inviteToken])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: msg
            )
        }

        return try decoder.decode(RedeemResponse.self, from: data)
    }

    // MARK: - Contacts

    func deleteContact(_ contactID: String) async throws {
        try await requestVoid("/api/contacts/\(contactID)", method: "DELETE")
    }

    // MARK: - Profile

    struct MeResponse: Codable {
        let id: String
        let name: String
        let filesSent: Int?
        let filesReceived: Int?
        let storageUsed: Int64?

        enum CodingKeys: String, CodingKey {
            case id, name
            case filesSent = "files_sent"
            case filesReceived = "files_received"
            case storageUsed = "storage_used"
        }
    }

    func getMe() async throws -> MeResponse {
        try await request("/api/me")
    }

    func getProfile(userID: String) async throws -> MeResponse {
        try await request("/api/users/\(userID)/profile")
    }
}

// MARK: - Multipart Helpers

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
