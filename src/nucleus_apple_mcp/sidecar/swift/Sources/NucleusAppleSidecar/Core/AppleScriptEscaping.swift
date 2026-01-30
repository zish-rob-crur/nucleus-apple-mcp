import Foundation

func appleScriptStringLiteral(_ value: String) -> String {
    // Use a quoted AppleScript string literal, escaping backslashes and double quotes.
    // AppleScript also accepts \n, \r, \t, etc. We keep newlines as-is.
    var s = value
    s = s.replacingOccurrences(of: "\\", with: "\\\\")
    s = s.replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(s)\""
}

