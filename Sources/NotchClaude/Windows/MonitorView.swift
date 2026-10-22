import SwiftUI
import UniformTypeIdentifiers

struct MonitorView: View {
    let taskId: UUID
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var runs: RunManager
    @EnvironmentObject private var container: AppContainer
    @State private var autoScroll = true

    var body: some View {
        Group {
            if let task = store.task(taskId) {
                VStack(spacing: 0) {
                    MonitorHeader(task: task, autoScroll: $autoScroll)
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    transcript(task)
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    MonitorFooter(task: task)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "trash").font(.system(size: 28))
                    Text("Esta tarefa foi excluída")
                }
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07))
    }

    private func transcript(_ task: ClaudeTask) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if task.runs.isEmpty {
                        PromptBubble(text: task.prompt, attachments: task.attachments.map {
                            AttachmentReference(path: $0.url.path, name: $0.originalName, isImage: $0.isImage)
                        }, isAutomatic: false, date: nil)
                        PendingBanner(task: task)
                    }
                    ForEach(Array(task.runs.enumerated()), id: \.element.id) { index, run in
                        RunHeader(run: run, index: index)
                        if let session = runs.session(forRun: run.id) {
                            LiveRunView(session: session, proxy: proxy, autoScroll: autoScroll)
                        } else {
                            StaticRunView(run: run)
                        }
                    }
                    if !task.runs.isEmpty, task.status.isPending {
                        PendingBanner(task: task)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: task.runs.count) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

struct RunHeader: View {
    let run: RunRecord
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
            HStack(spacing: 5) {
                Image(systemName: run.isResume ? "arrow.turn.down.right" : "play.circle")
                Text("Execução \(index + 1)")
                    .fontWeight(.semibold)
                Text("· \(Formatters.schedule(run.startedAt))")
                if run.isResume { Text("· mesma sessão") }
                if let duration = run.duration { Text("· \(Formatters.duration(duration))") }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.tertiaryText)
            .fixedSize()
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}

struct PendingBanner: View {
    let task: ClaudeTask

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.status.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(task.status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(task.status.color.opacity(0.1)))
    }

    private var title: String {
        switch task.status {
        case .scheduled: return "Agendada para \(Formatters.schedule(task.scheduledAt))"
        case .queued: return "Aguardando na fila"
        case .rateLimited:
            if let retry = task.retryAt { return "Tokens esgotados · retoma \(Formatters.resetDescription(retry))" }
            return "Tokens esgotados"
        default: return task.status.label
        }
    }

    private var detail: String? {
        if task.status == .rateLimited {
            return task.hasPendingResume ? "Ao liberar, o Claude continua a mesma sessão de onde parou." : "Ao liberar, a tarefa roda automaticamente."
        }
        if task.hasPendingResume, let prompt = task.nextPrompt { return "Próxima mensagem: \(prompt)" }
        return task.statusDetail
    }
}

struct MonitorHeader: View {
    let task: ClaudeTask
    @Binding var autoScroll: Bool
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                StatusBadge(status: task.status)
                Text(task.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Toggle(isOn: $autoScroll) {
                    Label("Seguir", systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Rolar automaticamente enquanto o Claude trabalha")
            }
            HStack(spacing: 14) {
                Button {
                    TerminalLauncher.revealDirectory(task.directory)
                } label: {
                    Label(Formatters.abbreviatedPath(task.directory), systemImage: "folder.fill")
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Mostrar no Finder")
                meta("cpu", modelLabel)
                if task.repeatRule != .never { meta("repeat", task.repeatRule.label) }
                if !task.runs.isEmpty { meta("number", "\(task.runs.count) execuç\(task.runs.count == 1 ? "ão" : "ões")") }
                if task.totalCost > 0 { meta("dollarsign.circle", Formatters.cost(task.totalCost)) }
                if let session = task.lastSessionId {
                    Button {
                        Clipboard.copy(session)
                    } label: {
                        Label(String(session.prefix(8)), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copiar ID da sessão (\(session))")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
        }
        .padding(.leading, 22)
        .padding(.trailing, 22)
        .padding(.top, 30)
        .padding(.bottom, 12)
    }

    private var modelLabel: String {
        let value = task.model ?? settings.defaultModel
        return AppSettings.modelOptions.first { $0.value == value }?.label ?? value
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
    }
}

struct MonitorFooter: View {
    let task: ClaudeTask
    @EnvironmentObject private var runs: RunManager
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @State private var message = ""
    @State private var attachments: [Attachment] = []
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = runs.liveSession(for: task.id) {
                RunningFooter(session: session) { container.scheduler.cancel(task.id) }
            } else {
                composer
            }
            actions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(white: 0.09))
    }

    private var canSend: Bool {
        task.lastSessionId != nil && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !runs.isRunning(task.id)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        AttachmentThumbnail(url: attachment.url, name: attachment.originalName, isImage: attachment.isImage, size: 44) {
                            attachments.removeAll { $0.id == attachment.id }
                            AttachmentImporter.remove([attachment])
                        }
                    }
                }
                .padding(.top, 4)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: pickFiles) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.card))
                }
                .buttonStyle(.plain)
                .help("Anexar imagens ou arquivos")

                TextField(task.lastSessionId == nil ? "A sessão começa quando a tarefa rodar" : "Responder ao Claude e continuar esta sessão…", text: $message, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(dropTargeted ? Theme.accent : Theme.stroke))
                    .disabled(task.lastSessionId == nil)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(canSend ? Theme.accent : Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { attachments += AttachmentImporter.importFiles([url]) }
                }
            }
            return true
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if task.status.isPending {
                Button("Rodar agora") { container.scheduler.runNow(task.id) }
                Button("Cancelar") { container.scheduler.cancel(task.id) }
            } else if !runs.isRunning(task.id) {
                Button("Rodar do zero") { container.scheduler.retry(task.id) }
            }
            if task.lastSessionId != nil {
                Button("Abrir no Terminal") {
                    TerminalLauncher.resume(task: task, settings: settings, shell: container.shell)
                }
                .help("Abre esta mesma sessão no Claude interativo")
            }
            Button("Mostrar pasta") { TerminalLauncher.revealDirectory(task.directory) }
            Spacer()
            Button("Excluir tarefa", role: .destructive) { container.delete(task.id) }
        }
        .controlSize(.small)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            attachments += AttachmentImporter.importFiles(panel.urls)
        }
    }

    private func send() {
        guard canSend else { return }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        container.scheduler.continueTask(task.id, prompt: text, attachments: attachments)
        message = ""
        attachments = []
    }
}

struct RunningFooter: View {
    @ObservedObject var session: RunSession
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ClaudeSpinner(size: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.activity)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text("Rodando em segundo plano há")
                    ElapsedText(since: session.startedAt, font: .system(size: 11).monospacedDigit(), color: Theme.secondaryText)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button(role: .destructive, action: onStop) {
                Label("Parar", systemImage: "stop.fill")
            }
            .controlSize(.regular)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent.opacity(0.1)))
    }
}
