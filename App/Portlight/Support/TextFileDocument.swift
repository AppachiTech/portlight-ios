import SwiftUI
import UniformTypeIdentifiers

/// A text file for the share/export sheet.
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum FileReading {
    /// Reads a small text file the user picked, inside its security scope.
    static func text(at url: URL, maxBytes: Int = 1 << 20) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= maxBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
