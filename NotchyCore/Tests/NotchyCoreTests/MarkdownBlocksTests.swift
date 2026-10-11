import Testing
@testable import NotchyCore

struct MarkdownBlocksTests {
    @Test func mixedDocument() {
        let text = """
        ## Subnet
        A **/26** gives
        62 hosts.

        - first `item`
        * second
        1. one
        2) two

        ```bash
        show ip route
          indented
        ```
        Done.
        """
        #expect(MarkdownBlocks.parse(text) == [
            .heading("Subnet"),
            .paragraph("A **/26** gives\n62 hosts."),
            .listItem(marker: "•", text: "first `item`"),
            .listItem(marker: "•", text: "second"),
            .listItem(marker: "1.", text: "one"),
            .listItem(marker: "2.", text: "two"),
            .code(language: "bash", text: "show ip route\n  indented"),
            .paragraph("Done."),
        ])
    }

    @Test func unclosedFenceWhileStreaming() {
        #expect(MarkdownBlocks.parse("Try:\n```\nping 10.0.0.1") == [
            .paragraph("Try:"),
            .code(language: nil, text: "ping 10.0.0.1"),
        ])
    }

    @Test func hashWithoutSpaceIsText() {
        #expect(MarkdownBlocks.parse("#hashtag") == [.paragraph("#hashtag")])
    }

    @Test func emptyInput() {
        #expect(MarkdownBlocks.parse("") == [])
    }
}
