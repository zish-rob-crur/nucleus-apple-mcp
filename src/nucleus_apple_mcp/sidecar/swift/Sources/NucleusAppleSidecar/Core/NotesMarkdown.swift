import Foundation
import Markdown

func plaintextToHTML(_ text: String) -> String {
    let escaped = escapeHTML(text)
    let withBreaks = escaped.replacingOccurrences(of: "\n", with: "<br/>")
    return "<div>\(withBreaks)</div>"
}

func markdownToSafeHTML(_ markdown: String) -> String {
    let doc = Document(parsing: markdown)
    var sanitizer = NotesMarkdownSanitizer()
    let sanitized = sanitizer.visit(doc) ?? doc
    return HTMLFormatter.format(sanitized)
}

private func escapeHTML(_ s: String) -> String {
    var out = s
    out = out.replacingOccurrences(of: "&", with: "&amp;")
    out = out.replacingOccurrences(of: "<", with: "&lt;")
    out = out.replacingOccurrences(of: ">", with: "&gt;")
    out = out.replacingOccurrences(of: "\"", with: "&quot;")
    return out
}

private let allowedLinkSchemes: Set<String> = ["http", "https", "mailto", "file"]

private func linkScheme(_ destination: String) -> String? {
    // Detect a URL scheme per RFC3986 (best-effort).
    guard let colon = destination.firstIndex(of: ":") else {
        return nil
    }

    let prefix = destination[..<colon]
    guard let first = prefix.first, first.isLetter else {
        return nil
    }
    for ch in prefix.dropFirst() {
        if ch.isLetter || ch.isNumber || ch == "+" || ch == "-" || ch == "." {
            continue
        }
        return nil
    }
    return String(prefix).lowercased()
}

private struct NotesMarkdownSanitizer: MarkupRewriter {
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> Markup? {
        Paragraph(Text(html.rawHTML))
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> Markup? {
        Text(inlineHTML.rawHTML)
    }

    mutating func visitImage(_ image: Image) -> Markup? {
        let alt = image.plainText
        if alt.isEmpty {
            return Text("[image]")
        }
        return Text(alt)
    }

    mutating func visitLink(_ link: Link) -> Markup? {
        if let dest = link.destination, let scheme = linkScheme(dest), !allowedLinkSchemes.contains(scheme) {
            return Text(link.plainText)
        }
        return defaultVisit(link)
    }
}

