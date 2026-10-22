import SwiftUI

struct MarkdownText: View {
    var text: String
    var fontSize: CGFloat = 13
    var color: Color = Theme.primaryText

    private enum Segment: Identifiable {
        case prose(Int, String)
        case code(Int, String, String)

        var id: Int {
            switch self {
            case .prose(let index, _), .code(let index, _, _): return index
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment {
                case .prose(_, let content):
                    Text(attributed(content))
                        .font(.system(size: fontSize))
                        .foregroundStyle(color)
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(_, let language, let content):
                    VStack(alignment: .leading, spacing: 4) {
                        if !language.isEmpty {
                            Text(language)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Text(content)
                            .font(.system(size: fontSize - 1.5, design: .monospaced))
                            .foregroundStyle(color.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .textSelection(.enabled)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var prose: [String] = []
        var code: [String] = []
        var language = ""
        var inCode = false
        var index = 0

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty {
                result.append(.prose(index, joined))
                index += 1
            }
            prose = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    result.append(.code(index, language, code.joined(separator: "\n")))
                    index += 1
                    code = []
                    inCode = false
                } else {
                    flushProse()
                    language = line.trimmingCharacters(in: .whitespaces).dropFirst(3).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
            } else if inCode {
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        if inCode { result.append(.code(index, language, code.joined(separator: "\n"))); index += 1 }
        flushProse()
        return result
    }

    private func attributed(_ content: String) -> AttributedString {
        let normalized = content
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                    return "**\(title)**"
                }
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    let indent = String(repeating: "  ", count: (line.count - line.drop { $0 == " " }.count) / 2)
                    return indent + "• " + trimmed.dropFirst(2)
                }
                return line
            }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: normalized, options: options)) ?? AttributedString(content)
    }
}
