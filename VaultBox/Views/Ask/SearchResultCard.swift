import SwiftUI

struct SearchResultCard: View {
    let result: SearchResult
    let itemName: String
    let itemType: VaultItem.ItemType
    let queryTerms: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sourceBadge
            excerptText
        }
        .padding(Constants.standardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                .fill(Color.vaultSurface)
        )
    }

    // MARK: - Source Badge

    private var sourceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: typeIcon)
                .font(.caption)
                .foregroundStyle(Color.vaultAccent)

            Text(itemName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.vaultTextPrimary)
                .lineLimit(1)

            if let page = result.pageNumber {
                Text("· p.\(page)")
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)
            }

            Spacer()

            matchBadge
        }
    }

    private var typeIcon: String {
        switch itemType {
        case .photo:
            return "photo"
        case .video:
            return "video"
        case .document:
            return "doc.text"
        }
    }

    private var matchBadge: some View {
        Group {
            switch result.matchType {
            case .hybrid:
                Label("Hybrid", systemImage: "sparkles")
            case .semantic:
                Label("Semantic", systemImage: "brain")
            case .keyword:
                Label("Keyword", systemImage: "textformat")
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.vaultAccent.opacity(0.8))
    }

    // MARK: - Excerpt Text

    private var excerptText: some View {
        highlightedText(result.textExcerpt)
            .font(.subheadline)
            .foregroundStyle(Color.vaultTextPrimary)
            .lineLimit(4)
            .truncationMode(.tail)
    }

    /// Builds an `AttributedString` with query terms bolded and tinted with accent color.
    private func highlightedText(_ text: String) -> Text {
        guard !queryTerms.isEmpty else {
            return Text(text)
        }

        var result = Text("")
        var currentIndex = text.startIndex

        // Collect all highlight ranges for all query terms using
        // case-insensitive search directly on the original string so that
        // the returned indices are always valid for `text`.
        var ranges: [(Range<String.Index>, String)] = []
        for term in queryTerms {
            var searchStart = text.startIndex
            while let range = text.range(of: term, options: .caseInsensitive, range: searchStart..<text.endIndex) {
                ranges.append((range, String(text[range])))
                searchStart = range.upperBound
            }
        }

        // Sort by position and merge overlapping ranges
        ranges.sort { $0.0.lowerBound < $1.0.lowerBound }
        let merged = mergeOverlappingRanges(ranges.map(\.0))

        for range in merged {
            // Add any text before this highlight
            if currentIndex < range.lowerBound {
                result = result + Text(text[currentIndex..<range.lowerBound])
            }
            // Add highlighted text
            result = result + Text(text[range])
                .bold()
                .foregroundColor(Color.vaultAccent)
            currentIndex = range.upperBound
        }

        // Add remaining text
        if currentIndex < text.endIndex {
            result = result + Text(text[currentIndex..<text.endIndex])
        }

        return result
    }

    private func mergeOverlappingRanges(
        _ ranges: [Range<String.Index>]
    ) -> [Range<String.Index>] {
        guard !ranges.isEmpty else { return [] }

        var merged: [Range<String.Index>] = [ranges[0]]
        for range in ranges.dropFirst() {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                let newUpper = max(last.upperBound, range.upperBound)
                merged[merged.count - 1] = last.lowerBound..<newUpper
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
