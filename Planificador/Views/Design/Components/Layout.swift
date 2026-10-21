import SwiftUI

// Page and sheet scaffolds so every screen has the same margins, titles and footers.

/// Large title row at the top of content pages.
struct PageHeader<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            leading
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).font(Theme.Font.pageTitle)
                if let subtitle {
                    Text(subtitle).font(Theme.Font.rowDetail).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Space.m)
            HStack(spacing: Theme.Space.s) { trailing }
                .buttonStyle(.glass)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }
}

extension PageHeader where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, leading: { EmptyView() }, trailing: trailing)
    }
}

/// Scrollable page body with standard padding and a readable, centered column.
struct PageContent<Content: View>: View {
    var maxWidth: CGFloat = Theme.Size.contentMaxWidth
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) { content }
                .padding(Theme.Space.xl)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Modal sheet layout: eyebrow, content, footer. Sizes itself to its content.
struct SheetScaffold<Content: View, Footer: View>: View {
    let eyebrow: String
    var width: CGFloat = Theme.Size.sheetWidth
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(eyebrow)
                .font(Theme.Font.eyebrow)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
            footer.padding(.top, Theme.Space.xs)
        }
        .padding(Theme.Space.xl)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }
}
