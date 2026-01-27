import ArgumentParser
import Darwin
import Foundation

@main
struct SidecarEntrypoint {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.contains("-h") || args.first == "help" {
            SidecarCLI.main()
            return
        }

        do {
            var command = try SidecarCLI.parseAsRoot()
            do {
                try command.run()
            } catch {
                writeErrorAndExit(code: "INTERNAL", error: error)
            }
        } catch {
            if error is CleanExit {
                SidecarCLI.exit(withError: error)
            }
            writeErrorAndExit(code: "INVALID_ARGUMENTS", error: error)
        }
    }

    private static func writeErrorAndExit(code: String, error: Error) -> Never {
        let response: [String: Any]
        if let sidecarError = error as? SidecarError {
            response = makeErrorResponse(code: sidecarError.code, message: sidecarError.message)
        } else {
            response = makeErrorResponse(code: code, message: String(describing: error))
        }
        do {
            try writeStdoutJSON(response)
        } catch {
            FileHandle.standardError.write(Data("Failed to write error response.\n".utf8))
        }
        Darwin.exit(1)
    }
}
