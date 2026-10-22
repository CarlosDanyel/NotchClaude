import Foundation

enum ToolFormatter {
    static func make(id: String, name: String, input: [String: Any], cwd: String?) -> ToolCall {
        let (title, summary, symbol) = describe(name: name, input: input, cwd: cwd)
        return ToolCall(
            id: id,
            name: name,
            title: title,
            summary: summary,
            detail: detail(name: name, input: input),
            symbol: symbol
        )
    }

    static func activity(for tool: ToolCall) -> String {
        switch tool.name {
        case "Bash": return "Executando \(tool.summary)"
        case "Read": return "Lendo \(tool.summary)"
        case "Edit", "MultiEdit": return "Editando \(tool.summary)"
        case "Write": return "Criando \(tool.summary)"
        case "Glob", "Grep": return "Procurando \(tool.summary)"
        case "WebFetch": return "Abrindo \(tool.summary)"
        case "WebSearch": return "Pesquisando \(tool.summary)"
        case "Task", "Agent": return "Subagente: \(tool.summary)"
        case "TodoWrite": return "Atualizando plano"
        case "Skill": return "Usando skill \(tool.summary)"
        default: return "\(tool.title) \(tool.summary)".trimmingCharacters(in: .whitespaces)
        }
    }

    private static func describe(name: String, input: [String: Any], cwd: String?) -> (String, String, String) {
        func string(_ key: String) -> String { (input[key] as? String) ?? "" }
        func path(_ key: String) -> String { relative(string(key), to: cwd) }

        switch name {
        case "Bash":
            let command = string("command").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return ("Bash", command, "terminal")
        case "Read":
            return ("Read", path("file_path"), "doc.text")
        case "Edit", "MultiEdit":
            return ("Edit", path("file_path"), "pencil")
        case "Write":
            return ("Write", path("file_path"), "square.and.pencil")
        case "NotebookEdit":
            return ("Notebook", path("notebook_path"), "book")
        case "Glob":
            return ("Glob", string("pattern"), "folder.badge.questionmark")
        case "Grep":
            let scope = string("path").isEmpty ? "" : " em \(path("path"))"
            return ("Grep", string("pattern") + scope, "magnifyingglass")
        case "WebFetch":
            return ("WebFetch", string("url"), "globe")
        case "WebSearch":
            return ("WebSearch", string("query"), "globe.americas")
        case "Task", "Agent":
            let kind = string("subagent_type")
            let description = string("description")
            return ("Agent", kind.isEmpty ? description : "\(kind) · \(description)", "person.2")
        case "TodoWrite":
            let count = (input["todos"] as? [Any])?.count ?? 0
            return ("Plano", "\(count) itens", "checklist")
        case "Skill":
            return ("Skill", string("skill").isEmpty ? string("command") : string("skill"), "wand.and.stars")
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.split(separator: "_", omittingEmptySubsequences: true)
                let server = parts.count > 1 ? String(parts[1]) : "mcp"
                let tool = parts.count > 2 ? parts[2...].joined(separator: "_") : name
                return ("MCP", "\(server) · \(tool)", "puzzlepiece.extension")
            }
            return (name, compactJSON(input, limit: 120), "wrench.and.screwdriver")
        }
    }

    private static func detail(name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash":
            return (input["command"] as? String) ?? ""
        case "Edit":
            let old = (input["old_string"] as? String) ?? ""
            let new = (input["new_string"] as? String) ?? ""
            return "− " + old.replacingOccurrences(of: "\n", with: "\n− ") + "\n\n+ " + new.replacingOccurrences(of: "\n", with: "\n+ ")
        case "Write":
            return (input["content"] as? String) ?? ""
        case "TodoWrite":
            let todos = (input["todos"] as? [[String: Any]]) ?? []
            return todos.map { todo in
                let mark: String
                switch todo["status"] as? String {
                case "completed": mark = "✓"
                case "in_progress": mark = "▸"
                default: mark = "○"
                }
                return "\(mark) \((todo["content"] as? String) ?? "")"
            }.joined(separator: "\n")
        default:
            return prettyJSON(input)
        }
    }

    static func relative(_ path: String, to cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty, path.hasPrefix(cwd + "/") else { return path }
        return String(path.dropFirst(cwd.count + 1))
    }

    static func prettyJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func compactJSON(_ object: Any, limit: Int) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    static func flattenToolResult(_ content: Any?) -> String {
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block -> String? in
            switch block["type"] as? String {
            case "text": return block["text"] as? String
            case "image": return "[imagem]"
            default: return nil
            }
        }.joined(separator: "\n")
    }
}
