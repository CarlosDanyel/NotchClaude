import Foundation

struct SkillInfo: Identifiable, Hashable {
    enum Kind: Hashable {
        case skill
        case command
    }

    var id: String { "\(kind)-\(name)" }
    var name: String
    var description: String
    var kind: Kind
    var isGlobal: Bool
}

struct ProjectContext: Equatable {
    var skills: [SkillInfo] = []
    var hasClaudeMd = false
    var hasMcpConfig = false
    var hasSettings = false

    var isEmpty: Bool { skills.isEmpty && !hasClaudeMd && !hasMcpConfig && !hasSettings }
}

enum ProjectInspector {
    static func inspect(_ directory: String, includeGlobal: Bool = true) -> ProjectContext {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: directory)
        let claudeDirectory = root.appendingPathComponent(".claude")
        var context = ProjectContext()
        context.hasClaudeMd = fileManager.fileExists(atPath: root.appendingPathComponent("CLAUDE.md").path)
            || fileManager.fileExists(atPath: claudeDirectory.appendingPathComponent("CLAUDE.md").path)
        context.hasMcpConfig = fileManager.fileExists(atPath: root.appendingPathComponent(".mcp.json").path)
        context.hasSettings = fileManager.fileExists(atPath: claudeDirectory.appendingPathComponent("settings.json").path)
            || fileManager.fileExists(atPath: claudeDirectory.appendingPathComponent("settings.local.json").path)

        var skills = scan(claudeDirectory, isGlobal: false)
        if includeGlobal {
            let home = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
            if home.standardizedFileURL != claudeDirectory.standardizedFileURL {
                let local = Set(skills.map(\.name))
                skills += scan(home, isGlobal: true).filter { !local.contains($0.name) }
            }
        }
        context.skills = skills
        return context
    }

    private static func scan(_ claudeDirectory: URL, isGlobal: Bool) -> [SkillInfo] {
        let fileManager = FileManager.default
        var result: [SkillInfo] = []

        let skillsDirectory = claudeDirectory.appendingPathComponent("skills")
        if let entries = try? fileManager.contentsOfDirectory(at: skillsDirectory, includingPropertiesForKeys: nil) {
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let file = entry.appendingPathComponent("SKILL.md")
                guard fileManager.fileExists(atPath: file.path) else { continue }
                let meta = frontMatter(file)
                result.append(SkillInfo(
                    name: meta["name"] ?? entry.lastPathComponent,
                    description: meta["description"] ?? "",
                    kind: .skill,
                    isGlobal: isGlobal
                ))
            }
        }

        let commandsDirectory = claudeDirectory.appendingPathComponent("commands")
        if let enumerator = fileManager.enumerator(at: commandsDirectory, includingPropertiesForKeys: nil) {
            for case let file as URL in enumerator where file.pathExtension == "md" {
                let relative = file.path.dropFirst(commandsDirectory.path.count + 1)
                let name = relative.dropLast(3).replacingOccurrences(of: "/", with: ":")
                let meta = frontMatter(file)
                result.append(SkillInfo(
                    name: name,
                    description: meta["description"] ?? "",
                    kind: .command,
                    isGlobal: isGlobal
                ))
            }
        }
        return result
    }

    private static func frontMatter(_ file: URL) -> [String: String] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [:] }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var values: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { values[key] = value }
        }
        return values
    }
}
