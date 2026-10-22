import SwiftUI

struct TasksPage: View {
    let controller: NotchController
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var runs: RunManager
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        HStack(spacing: 14) {
            NowWidget(controller: controller)
                .frame(width: 214)
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1)
                .padding(.vertical, 4)
            taskList
        }
    }

    private var sortedTasks: [ClaudeTask] {
        func rank(_ status: TaskStatus) -> Int {
            switch status {
            case .running: return 0
            case .rateLimited: return 1
            case .queued: return 2
            case .scheduled: return 3
            default: return 4
            }
        }
        return store.tasks.sorted { lhs, rhs in
            let left = rank(lhs.status)
            let right = rank(rhs.status)
            if left != right { return left < right }
            if left == 4 { return (lhs.finishedAt ?? lhs.createdAt) > (rhs.finishedAt ?? rhs.createdAt) }
            return lhs.scheduledAt < rhs.scheduledAt
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tarefas")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(store.tasks.count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Theme.card))
                Spacer()
                if store.tasks.contains(where: { $0.status.isFinished && $0.repeatRule == .never }) {
                    Button("Limpar concluídas") { withAnimation { store.removeFinished() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if store.tasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.tertiaryText)
                    Text("Nenhuma tarefa ainda")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Button("Criar tarefa") { controller.open(page: .compose) }
                        .buttonStyle(PillButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(sortedTasks) { task in
                            TaskRow(task: task, controller: controller)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .mask(
                    LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: UnitPoint(x: 0.5, y: 0.85), endPoint: .bottom)
                )
            }
        }
    }
}

struct TaskRow: View {
    let task: ClaudeTask
    let controller: NotchController
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var runs: RunManager
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(task.status.color.opacity(0.16))
                if task.status == .running {
                    ClaudeSpinner(size: 12)
                } else {
                    Image(systemName: task.status.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(task.status.color)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill").font(.system(size: 8))
                    Text(task.directoryName).lineLimit(1)
                    Text("·")
                    Text(subtitle).lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 6)

            if hovering {
                actions.transition(.opacity)
            } else {
                StatusBadge(status: task.status, compact: true).transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Theme.cardHover : Theme.card))
        .contentShape(Rectangle())
        .onHover { value in withAnimation(.easeOut(duration: 0.12)) { hovering = value } }
        .onTapGesture { controller.showMonitor(task.id) }
        .contextMenu { menu }
    }

    private var subtitle: String {
        switch task.status {
        case .running:
            return runs.liveSession(for: task.id)?.activity ?? "Executando"
        case .scheduled:
            let repeatText = task.repeatRule == .never ? "" : " · \(task.repeatRule.label.lowercased())"
            return Formatters.schedule(task.scheduledAt) + repeatText
        case .queued, .rateLimited:
            return task.statusDetail ?? task.status.label
        case .completed, .failed, .cancelled:
            let when = task.finishedAt.map { Formatters.relativeTime($0) } ?? ""
            return [when, task.statusDetail ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if task.status == .running {
                NotchIconButton(symbol: "stop.fill", help: "Parar", tint: Theme.danger, size: 24) {
                    container.scheduler.cancel(task.id)
                }
            } else {
                NotchIconButton(symbol: "play.fill", help: "Rodar agora", tint: Theme.success, size: 24) {
                    if task.status.isFinished { container.scheduler.retry(task.id) } else { container.scheduler.runNow(task.id) }
                }
            }
            NotchIconButton(
                symbol: copied ? "checkmark" : "doc.on.doc.fill",
                help: copied ? "Prompt copiado" : "Copiar prompt",
                tint: copied ? Theme.success : Theme.primaryText,
                size: 24,
                action: copyPrompt
            )
            NotchIconButton(symbol: "eye.fill", help: "Acompanhar", size: 24) {
                controller.showMonitor(task.id)
            }
            NotchIconButton(symbol: "trash.fill", help: "Excluir", tint: Theme.danger, size: 24) {
                withAnimation { container.delete(task.id) }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Acompanhar") { controller.showMonitor(task.id) }
        Button("Rodar agora") {
            if task.status.isFinished { container.scheduler.retry(task.id) } else { container.scheduler.runNow(task.id) }
        }
        .disabled(task.status == .running)
        if task.status.isPending {
            Button("Cancelar") { container.scheduler.cancel(task.id) }
        }
        if task.status == .running {
            Button("Parar") { container.scheduler.cancel(task.id) }
        }
        Divider()
        Button("Copiar prompt") { copyPrompt() }
        Button("Duplicar") { container.duplicate(task.id) }
        Button("Mostrar pasta no Finder") { TerminalLauncher.revealDirectory(task.directory) }
        if task.lastSessionId != nil {
            Button("Abrir sessão no Terminal") {
                TerminalLauncher.resume(task: task, settings: container.settings, shell: container.shell)
            }
        }
        Divider()
        Button("Excluir", role: .destructive) { container.delete(task.id) }
    }

    private func copyPrompt() {
        Clipboard.copy(task.prompt)
        withAnimation(.easeOut(duration: 0.12)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.12)) { copied = false }
        }
    }
}

struct NowWidget: View {
    let controller: NotchController
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var runs: RunManager
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session = runs.sessions.values.min(by: { $0.startedAt < $1.startedAt }),
               let task = store.task(session.taskId) {
                RunningCard(session: session, task: task, extra: runs.sessions.count - 1, controller: controller)
            } else if store.limit.isBlocked(), let until = store.limit.blockedUntil {
                limitedCard(until: until)
            } else if let next = store.tasks.filter({ $0.status.isPending }).min(by: { $0.scheduledAt < $1.scheduledAt }) {
                nextCard(next)
            } else {
                emptyCard
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    private func limitedCard(until: Date) -> some View {
        let waiting = store.tasks.filter { $0.status == .rateLimited || $0.status == .queued }.count
        return VStack(alignment: .leading, spacing: 8) {
            Label("Tokens esgotados", systemImage: "gauge.with.needle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.danger)
            Text(store.limit.kindLabel)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
            Text("Libera \(Formatters.resetDescription(until))")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("em \(Formatters.duration(until.timeIntervalSince(context.date)))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(waiting == 0 ? "Nenhuma tarefa esperando" : "\(waiting) tarefa\(waiting == 1 ? "" : "s") vai\(waiting == 1 ? "" : "o") rodar ao liberar")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
            Button("Tentar agora") {
                store.clearLimit()
                container.scheduler.tick()
            }
            .buttonStyle(PillButtonStyle(tint: Theme.danger, prominent: false))
        }
    }

    private func nextCard(_ task: ClaudeTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Próxima", systemImage: "calendar.badge.clock")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.info)
            Text(task.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
            Label(task.directoryName, systemImage: "folder.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
            Text(Formatters.schedule(task.scheduledAt).capitalized)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Formatters.relativeTime(task.scheduledAt, now: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            Button("Rodar agora") { container.scheduler.runNow(task.id) }
                .buttonStyle(PillButtonStyle(tint: Theme.info, prominent: false))
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClaudeSpinner(size: 22, animating: false)
            Text("Tudo tranquilo")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            Text("Agende um prompt e o Claude roda em segundo plano, na pasta que você escolher.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Nova tarefa") { controller.open(page: .compose) }
                .buttonStyle(PillButtonStyle())
        }
    }
}

struct RunningCard: View {
    @ObservedObject var session: RunSession
    let task: ClaudeTask
    let extra: Int
    let controller: NotchController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ClaudeSpinner(size: 13)
                Text("Executando")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                ElapsedText(since: session.startedAt)
            }
            Text(task.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Label(task.directoryName, systemImage: "folder.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
            Text(session.activity)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.05)))
            HStack {
                Button("Acompanhar") { controller.showMonitor(task.id) }
                    .buttonStyle(PillButtonStyle())
                if extra > 0 {
                    Text("+\(extra) rodando")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
}
