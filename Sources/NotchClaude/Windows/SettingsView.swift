import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var container: AppContainer
    @State private var detectedPath: String?
    @State private var version: String?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                LabeledContent("Executável") {
                    VStack(alignment: .trailing, spacing: 4) {
                        TextField("Detectar automaticamente", text: $settings.claudePath)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                        Text(statusLine)
                            .font(.caption)
                            .foregroundStyle(detectedPath == nil ? Theme.danger : Theme.success)
                    }
                }
                Toggle("Pular permissões (--dangerously-skip-permissions)", isOn: $settings.skipPermissions)
                Picker("Modelo padrão", selection: $settings.defaultModel) {
                    ForEach(AppSettings.modelOptions, id: \.value) { Text($0.label).tag($0.value) }
                }
                Picker("Esforço padrão", selection: $settings.defaultEffort) {
                    ForEach(AppSettings.effortOptions, id: \.value) { Text($0.label).tag($0.value) }
                }
                Stepper("Tarefas simultâneas: \(settings.maxConcurrent)", value: $settings.maxConcurrent, in: 1...4)
                LabeledContent("Argumentos extras") {
                    TextField("ex.: --add-dir ~/Design", text: $settings.extraArguments)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("As tarefas rodam com o mesmo Claude do Terminal: suas configurações, skills, CLAUDE.md, MCPs e plugins da pasta escolhida.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $settings.continuePrompt)
                    .font(.system(size: 12))
                    .frame(height: 64)
                Button("Restaurar texto padrão") { settings.continuePrompt = AppSettings.defaultContinuePrompt }
                    .controlSize(.small)
            } header: {
                Text("Quando o limite de 5h ou semanal acabar")
            } footer: {
                Text("Se o Claude for cortado no meio de uma tarefa, ela fica como “Tokens esgotados” e, quando o limite libera, a mesma sessão é retomada com esta mensagem.")
                    .foregroundStyle(.secondary)
            }

            Section("Notch") {
                Toggle("Abrir ao passar o mouse", isOn: $settings.openOnHover)
                Toggle("Feedback tátil ao abrir", isOn: $settings.hapticsEnabled)
                Toggle("Manter aberto enquanto digito", isOn: $settings.preventCloseWhileTyping)
                Toggle("Mostrar em telas sem notch", isOn: $settings.showOnNonNotchScreens)
            }

            Section("Sistema") {
                Toggle("Abrir ao iniciar o Mac", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        LaunchAtLogin.set(launchAtLogin)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                    .disabled(!LaunchAtLogin.isInstalledLocation)
                if !LaunchAtLogin.isInstalledLocation {
                    Text("Mova o NotchClaude para a pasta Aplicativos para ele abrir sozinho com o Mac.")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                } else if launchAtLogin {
                    Text("Abre no login e reabre sozinho se fechar inesperadamente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Notificações", isOn: $settings.notificationsEnabled)
                HStack {
                    Button("Abrir pasta de dados") { NSWorkspace.shared.open(AppPaths.base) }
                    Spacer()
                    Button("Encerrar NotchClaude", role: .destructive) { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 22)
        .onAppear(perform: detect)
        .onChange(of: settings.claudePath) { detect() }
    }

    private var statusLine: String {
        guard let detectedPath else { return "Claude Code não encontrado" }
        return [version, Formatters.abbreviatedPath(detectedPath)].compactMap { $0 }.joined(separator: " · ")
    }

    private func detect() {
        let path = container.shell.claudeExecutable(override: settings.claudePath)
        detectedPath = path
        version = nil
        guard let path else { return }
        let environment = container.shell.environment
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--version"]
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { version = text.isEmpty ? nil : "v\(text)" }
        }
    }
}
