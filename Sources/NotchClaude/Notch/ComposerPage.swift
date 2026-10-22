import SwiftUI

struct ComposerPage: View {
    let controller: NotchController
    @EnvironmentObject private var composer: ComposerModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var store: TaskStore
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            editor
            if !composer.context.skills.isEmpty { skillsRow }
            attachmentsRow
            scheduleRow
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(settings.recentDirectories, id: \.self) { path in
                    Button(Formatters.abbreviatedPath(path)) { composer.setDirectory(path) }
                }
                if !settings.recentDirectories.isEmpty { Divider() }
                Button("Escolher pasta…") { controller.chooseDirectory() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                    Text(composer.directoryName).fontWeight(.semibold).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.secondaryText)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Theme.card))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(composer.directory)

            contextBadges

            Spacer(minLength: 4)

            optionMenu(title: "Modelo", value: $composer.model, options: AppSettings.modelOptions)
            optionMenu(title: "Esforço", value: $composer.effort, options: AppSettings.effortOptions)
        }
    }

    private var contextBadges: some View {
        HStack(spacing: 4) {
            if composer.context.hasClaudeMd { badge("CLAUDE.md", symbol: "doc.text.fill") }
            let local = composer.context.skills.filter { !$0.isGlobal }.count
            if local > 0 { badge("\(local) skill\(local == 1 ? "" : "s") da pasta", symbol: "wand.and.stars") }
            if composer.context.hasMcpConfig { badge("MCP", symbol: "puzzlepiece.extension.fill") }
        }
    }

    private func badge(_ text: String, symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8.5))
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.success)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(Theme.success.opacity(0.12)))
    }

    private func optionMenu(title: String, value: Binding<String>, options: [(value: String, label: String)]) -> some View {
        let label = options.first { $0.value == value.wrappedValue }?.label ?? value.wrappedValue
        return Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    value.wrappedValue = option.value
                } label: {
                    if option.value == value.wrappedValue { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(Theme.secondaryText)
                Text(label).fontWeight(.semibold).foregroundStyle(.white)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(Theme.secondaryText)
            }
            .font(.system(size: 10.5))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Theme.card))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $composer.prompt)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($editorFocused)
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
            if composer.prompt.isEmpty {
                Text("O que o Claude deve fazer nesta pasta? Use /skills, descreva o conceito, cole prints com ⌘V…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(editorFocused ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1)
        )
    }

    private var skillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                ForEach(composer.context.skills) { skill in
                    ChipButton(title: "/\(skill.name)", symbol: skill.isGlobal ? nil : "folder.fill") {
                        composer.insert(skill)
                        editorFocused = true
                    }
                    .help(skill.description.isEmpty ? skill.name : skill.description)
                }
            }
        }
        .frame(height: 24)
    }

    private var attachmentsRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(composer.attachments) { attachment in
                        AttachmentThumbnail(url: attachment.url, name: attachment.originalName, isImage: attachment.isImage, size: 40) {
                            withAnimation { composer.remove(attachment) }
                        }
                    }
                    Button { controller.chooseAttachments() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                    .foregroundStyle(Color.white.opacity(0.25))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Anexar imagens ou arquivos")
                    if composer.attachments.isEmpty {
                        Text("Arraste imagens até o notch, cole com ⌘V ou clique em +")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
                .padding(.top, 5)
                .padding(.trailing, 6)
            }
        }
        .frame(height: 46)
    }

    private var scheduleRow: some View {
        HStack(spacing: 6) {
            ChipButton(title: "Agora", symbol: "bolt.fill", selected: composer.when == .now) { composer.when = .now }
            ChipButton(title: "+30 min", symbol: nil) { composer.setDelay(1800) }
            ChipButton(title: "+1 h", symbol: nil) { composer.setDelay(3600) }
            ChipButton(title: "Amanhã 9h", symbol: nil) { composer.setTomorrow(hour: 9) }
            if composer.when == .at {
                DatePicker("", selection: $composer.date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .font(.system(size: 11))
                    .fixedSize()
            } else {
                ChipButton(title: "Data…", symbol: "calendar", selected: false) { composer.when = .at }
            }

            Menu {
                ForEach(RepeatRule.allCases) { rule in
                    Button {
                        composer.repeatRule = rule
                    } label: {
                        if rule == composer.repeatRule { Label(rule.label, systemImage: "checkmark") } else { Text(rule.label) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "repeat").font(.system(size: 9, weight: .semibold))
                    Text(composer.repeatRule == .never ? "Repetir" : composer.repeatRule.label)
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(composer.repeatRule == .never ? Theme.primaryText.opacity(0.8) : .white)
                .padding(.horizontal, 9)
                .frame(height: 23)
                .background(Capsule().fill(composer.repeatRule == .never ? Theme.card : Theme.info.opacity(0.35)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 4)

            Button {
                if container.submitComposer() {
                    withAnimation(Theme.openSpring) { controller.model.page = .tasks }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: composer.when == .now ? "paperplane.fill" : "calendar.badge.plus")
                    Text(composer.when == .now ? "Rodar" : "Agendar")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!composer.canSubmit)
            .opacity(composer.canSubmit ? 1 : 0.45)
            .keyboardShortcut(.return, modifiers: .command)
            .help(store.limit.isBlocked() ? "Tokens esgotados: a tarefa espera a liberação e roda sozinha" : "⌘↩")
        }
    }
}
