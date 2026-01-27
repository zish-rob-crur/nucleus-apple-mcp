import Foundation

func writeStdoutJSON(_ object: Any) throws {
    guard JSONSerialization.isValidJSONObject(object) else {
        throw NSError(domain: "nucleus.sidecar", code: 2, userInfo: [NSLocalizedDescriptionKey: "Response is not valid JSON."])
    }

    let data = try JSONSerialization.data(withJSONObject: object, options: [])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

