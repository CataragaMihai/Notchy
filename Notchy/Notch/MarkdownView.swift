import NotchyCore
import SwiftUI

/// Renders block-level Markdown from `MarkdownBlocks`, with inline syntax via `AttributedString`.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                row(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .paragraph(text):
            wrapped(Text(inline(text)))
        case let .heading(text):
            wrapped(Text(inline(text)).font(.headline))
        case let .code(_, text):
            wrapped(Text(text).font(.system(.callout, design: .monospaced)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        case let .listItem(marker, text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary)
                wrapped(Text(inline(text)))
            }
        }
    }

    private func wrapped(_ text: Text) -> some View {
        text.fixedSize(horizontal: false, vertical: true)
    }

    private func inline(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}
