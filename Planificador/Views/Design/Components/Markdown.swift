import MarkdownUI
import SwiftUI

/// Renders a note's Markdown with MarkdownUI's GitHub theme: headings, lists, task lists, quotes,
/// code blocks and tables, in the app's type size. Selectable, like a document.
struct MarkdownPreview: View {
    let source: String

    var body: some View {
        Markdown(source)
            .markdownTheme(.gitHub.text {
                FontSize(15)
                BackgroundColor(nil)
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
