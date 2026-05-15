import Foundation

enum LogLoader {
    static func load(url: URL) async throws -> LogDocument {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            try Task.checkCancellation()
            return LogParser.parse(data: data, url: url)
        }.value
    }
}
