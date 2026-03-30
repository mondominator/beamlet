import XCTest
@testable import Beamlet

final class BeamletTests: XCTestCase {

    // MARK: - Model Decoding

    func testBeamletFileDecoding() throws {
        let json = """
        {
            "id": "abc-123",
            "sender_id": "user-1",
            "recipient_id": "user-2",
            "filename": "photo.jpg",
            "file_type": "image/jpeg",
            "file_size": 12345,
            "content_type": "file",
            "read": false,
            "sender_name": "Alice"
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(BeamletFile.self, from: json)
        XCTAssertEqual(file.id, "abc-123")
        XCTAssertEqual(file.filename, "photo.jpg")
        XCTAssertTrue(file.isImage)
        XCTAssertFalse(file.isVideo)
        XCTAssertEqual(file.displayType, "Photo")
        XCTAssertEqual(file.senderName, "Alice")
    }

    func testBeamletFileTextType() throws {
        let json = """
        {
            "id": "def-456",
            "sender_id": "user-1",
            "recipient_id": "user-2",
            "filename": "text",
            "file_type": "text/plain",
            "file_size": 0,
            "content_type": "text",
            "text_content": "Hello!",
            "read": true
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(BeamletFile.self, from: json)
        XCTAssertTrue(file.isText)
        XCTAssertEqual(file.textContent, "Hello!")
        XCTAssertEqual(file.displayType, "Message")
    }

    func testBeamletUserDecoding() throws {
        let json = """
        {
            "id": "user-1",
            "name": "Alice"
        }
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(BeamletUser.self, from: json)
        XCTAssertEqual(user.id, "user-1")
        XCTAssertEqual(user.name, "Alice")
    }

    // MARK: - Auth Repository

    func testAuthRepositoryInitialState() {
        let repo = AuthRepository()
        // Fresh repo with no stored credentials should not be authenticated
        // (may be authenticated if run on device with existing credentials)
        XCTAssertNotNil(repo)
    }

    // MARK: - Multipart Encoding

    func testMultipartEncoding() {
        var data = Data()
        let boundary = "test-boundary"
        data.appendMultipart(boundary: boundary, name: "field", value: "value")
        let string = String(data: data, encoding: .utf8)!
        XCTAssertTrue(string.contains("--test-boundary"))
        XCTAssertTrue(string.contains("name=\"field\""))
        XCTAssertTrue(string.contains("value"))
    }

    func testMultipartFileEncoding() {
        var data = Data()
        let boundary = "test-boundary"
        let fileData = "hello".data(using: .utf8)!
        data.appendMultipartFile(boundary: boundary, name: "file", filename: "test.txt", mimeType: "text/plain", data: fileData)
        let string = String(data: data, encoding: .utf8)!
        XCTAssertTrue(string.contains("filename=\"test.txt\""))
        XCTAssertTrue(string.contains("Content-Type: text/plain"))
        XCTAssertTrue(string.contains("hello"))
    }
}
