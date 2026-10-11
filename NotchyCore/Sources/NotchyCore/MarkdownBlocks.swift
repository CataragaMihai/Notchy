/// Block-level Markdown that SwiftUI's inline parser does not handle.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(String)
    case code(language: String?, text: String)
    case listItem(marker: String, text: String)
}

/// Splits Markdown into blocks. Inline syntax (bold, italics, `code`, links) stays in the text.
/// An unclosed code fence becomes a code block, so a half-streamed answer still renders.
public enum MarkdownBlocks {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String]?
        var codeLanguage: String?

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var lines = codeLines {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, text: lines.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    lines.append(line)
                    codeLines = lines
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                codeLanguage = language.isEmpty ? nil : language
                codeLines = []
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(.heading(heading))
            } else if let item = listItem(trimmed) {
                flushParagraph()
                blocks.append(item)
            } else {
                paragraph.append(trimmed)
            }
        }

        if let lines = codeLines {
            blocks.append(.code(language: codeLanguage, text: lines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces)
    }

    private static func listItem(_ line: String) -> MarkdownBlock? {
        for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
            return .listItem(marker: "•", text: String(line.dropFirst(2)))
        }
        let digits = line.prefix(while: \.isNumber)
        let rest = line.dropFirst(digits.count)
        if !digits.isEmpty, digits.count <= 3, rest.hasPrefix(". ") || rest.hasPrefix(") ") {
            return .listItem(marker: "\(digits).", text: String(rest.dropFirst(2)))
        }
        return nil
    }
}
