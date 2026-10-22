import SwiftUI

@MainActor
final class TranscriptCache {
    static let shared = TranscriptCache()

    private struct Entry {
        var signature: String
        var items: [TranscriptItem]
    }

    private var entries: [UUID: Entry] = [:]

    func items(for run: RunRecord) -> [TranscriptItem] {
        let size = (try? run.logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let signature = "\(size)-\(run.endedAt?.timeIntervalSince1970 ?? 0)"
        if let entry = entries[run.id], entry.signature == signature { return entry.items }
        let items = TranscriptLoader.load(run.logURL).items
        entries[run.id] = Entry(signature: signature, items: items)
        return items
    }
}

struct TranscriptItemView: View {
    let item: TranscriptItem
    var continuePrompt: String = AppSettings.shared.effectiveContinuePrompt

    var body: some View {
        content
            .padding(.leading, item.isNested ? 26 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .prompt(let text, let attachments, let isResume, let date):
            PromptBubble(text: text, attachments: attachments, isAutomatic: isResume && text == continuePrompt, date: date)
        case .assistant(let text):
            HStack(alignment: .top, spacing: 10) {
                Text("✻")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 16)
                MarkdownText(text: text, fontSize: 13)
            }
        case .thinking(let text):
            ThinkingBlock(text: text)
        case .tool(let call):
            ToolBlock(call: call)
        case .system(let text, let symbol):
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
                Text(text).font(.system(size: 11)).lineLimit(2)
            }
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity)
        case .result(let info):
            ResultCard(info: info)
        case .failure(let text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.danger.opacity(0.12)))
        }
    }
}

struct PromptBubble: View {
    let text: String
    let attachments: [AttachmentReference]
    let isAutomatic: Bool
    let date: Date?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if isAutomatic {
                Label("Continuação automática após a liberação dos tokens", systemImage: "arrow.clockwise.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if !attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(attachments, id: \.path) { attachment in
                            AttachmentThumbnail(url: URL(fileURLWithPath: attachment.path), name: attachment.name, isImage: attachment.isImage, size: 64)
                        }
                    }
                }
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent.opacity(0.22)))
                if let date {
                    Text(Formatters.schedule(date))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, isAutomatic ? 0 : 60)
    }
}

struct ThinkingBlock: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain").font(.system(size: 10))
                    Text("Pensamento").font(.system(size: 11, weight: .medium))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Theme.tertiaryText)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(text)
                    .font(.system(size: 12).italic())
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
            }
        }
        .padding(.leading, 26)
    }
}

struct ToolBlock: View {
    let call: ToolCall
    @State private var expanded: Bool

    init(call: ToolCall) {
        self.call = call
        _expanded = State(initialValue: call.name == "TodoWrite")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: call.symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 16)
                    Text(call.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Text(call.summary)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    status
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                if !call.detail.isEmpty {
                    codeBox(call.detail, tint: .white.opacity(0.85))
                }
                if let output = call.output, !output.isEmpty {
                    codeBox(output, tint: call.isError ? Theme.danger : .white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
    }

    @ViewBuilder
    private var status: some View {
        if !call.isDone {
            ProgressView().controlSize(.mini)
        } else if call.isError {
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger).font(.system(size: 11))
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success).font(.system(size: 11))
        }
    }

    private func codeBox(_ text: String, tint: Color) -> some View {
        let clipped = text.count > 12_000 ? String(text.prefix(12_000)) + "\n…" : text
        return ScrollView(.vertical) {
            Text(clipped)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 260)
        .fixedSize(horizontal: false, vertical: clipped.count < 1_500)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.35)))
    }
}

struct ResultCard: View {
    let info: ResultInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: info.isError ? "xmark.octagon.fill" : "checkmark.seal.fill")
                    .foregroundStyle(info.isError ? Theme.danger : Theme.success)
                Text(info.isError ? "Terminou com erro" : "Concluído")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                stats
            }
            if info.isError, !info.text.isEmpty {
                Text(info.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill((info.isError ? Theme.danger : Theme.success).opacity(0.1)))
    }

    private var stats: some View {
        HStack(spacing: 12) {
            if let duration = info.durationMs { stat("clock", Formatters.duration(Double(duration) / 1000)) }
            if let turns = info.numTurns { stat("arrow.triangle.2.circlepath", "\(turns) turnos") }
            if let input = info.inputTokens, let output = info.outputTokens {
                stat("number", "\(Formatters.tokens(input)) ↓ · \(Formatters.tokens(output)) ↑")
            }
            if let cost = info.costUSD { stat("dollarsign.circle", Formatters.cost(cost)) }
        }
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(.system(size: 10.5, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(Theme.secondaryText)
    }
}

struct LiveRunView: View {
    @ObservedObject var session: RunSession
    let proxy: ScrollViewProxy
    let autoScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(session.items) { item in
                TranscriptItemView(item: item)
            }
            if !session.liveText.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Text("✻")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 16)
                    MarkdownText(text: session.liveText + " ▍", fontSize: 13)
                }
            }
            if session.isRunning {
                HStack(spacing: 8) {
                    ClaudeSpinner(size: 13)
                    Text(session.activity)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ElapsedText(since: session.startedAt, font: .system(size: 11).monospacedDigit(), color: Theme.tertiaryText)
                }
                .padding(.leading, 2)
            }
        }
        .onChange(of: session.items.count) { scroll() }
        .onChange(of: session.liveText.count / 80) { scroll() }
        .onAppear { scroll() }
    }

    private func scroll() {
        guard autoScroll else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

struct StaticRunView: View {
    let run: RunRecord

    var body: some View {
        let items = TranscriptCache.shared.items(for: run)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                TranscriptItemView(item: item)
            }
            if items.isEmpty {
                Text("Sem registro desta execução")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}
