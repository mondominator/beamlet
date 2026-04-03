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

class BeamletAPI {
    private let authRepository: AuthRepository
    private let session: URLSession
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, session: URLSession = .shared) {
        self.authRepository = authRepository
        self.session = session
        self.decoder = JSONDecoder()

        let iso = ISO8601DateFormatter()
        let isoFrac: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let goNano: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSZ"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()
        let goSpace: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSSSS Z"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()

        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = isoFrac.date(from: string) { return date }
            if let date = iso.date(from: string) { return date }
            if let date = goNano.date(from: string) { return date }
            if let date = goSpace.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
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
        var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: true
        )
        urlComponents?.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Contacts

    func listUsers() async throws -> [BeamletUser] {
        try await request("/api/contacts")
    }

    // MARK: - Upload File

    func uploadFile(
        recipientID: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        message: String? = nil
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
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "recipient_id", value: recipientID)
        if let message = message, !message.isEmpty {
            body.appendMultipart(boundary: boundary, name: "message", value: message)
        }
        body.appendMultipartFile(
            boundary: boundary,
            name: "file",
            filename: filename,
            mimeType: mimeType,
            data: fileData
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: http.statusCode, message: msg)
        }

        return try decoder.decode(BeamletFile.self, from: data)
    }

    // MARK: - Upload Text / Link

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
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "recipient_id", value: recipientID)
        body.appendMultipart(boundary: boundary, name: "content_type", value: contentType)
        body.appendMultipart(boundary: boundary, name: "text_content", value: text)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: http.statusCode, message: msg)
        }

        return try decoder.decode(BeamletFile.self, from: data)
    }
}

// MARK: - Multipart Helpers

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(
        boundary: String,
        name: String,
        filename: String,
        mimeType: String,
        data: Data
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
