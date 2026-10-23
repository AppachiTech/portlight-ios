import Foundation

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

func bytes(hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        out.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return out
}

/// Runs a command-line tool if it exists; nil when it isn't installed, so
/// interop tests skip on machines without OpenSSH.
func runTool(_ path: String, _ arguments: [String], input: String? = nil) -> (status: Int32, output: String)? {
    guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let out = Pipe()
    process.standardOutput = out
    process.standardError = out
    if let input {
        let inPipe = Pipe()
        process.standardInput = inPipe
        inPipe.fileHandleForWriting.write(Data(input.utf8))
        try? inPipe.fileHandleForWriting.close()
    }
    do { try process.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

func temporaryFile(_ contents: String, mode: Int = 0o600) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("portlight-\(UUID().uuidString)")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    return url
}
