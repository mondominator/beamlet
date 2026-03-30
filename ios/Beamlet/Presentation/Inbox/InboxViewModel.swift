import Foundation

@Observable
@MainActor
class InboxViewModel {
    private let api: BeamletAPI

    var files: [BeamletFile] = []
    var isLoading = true
    var error: String?

    init(api: BeamletAPI) {
        self.api = api
    }

    func loadFiles() async {
        do {
            files = try await api.listFiles()
            isLoading = false
            error = nil
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func deleteFiles(at offsets: IndexSet) {
        let toDelete = offsets.map { files[$0] }
        files.remove(atOffsets: offsets)
        Task {
            for file in toDelete {
                try? await api.deleteFile(file.id)
            }
        }
    }

    func thumbnailURL(for fileID: String) -> URL? {
        api.thumbnailURL(for: fileID)
    }

    var authHeaders: [String: String] {
        api.authHeaders
    }
}
