import Foundation

struct TranscriptBuilder {
    private(set) var items: [TranscriptItem] = []
    private(set) var liveText = ""
    private(set) var activity = "Iniciando Claude…"
    private(set) var sessionId: String?
    private(set) var model: String?
    private(set) var cwd: String?
    private(set) var result: ResultInfo?
    private(set) var usageLimitHit: RateLimitHit?
    private(set) var rejectedEvent: RateLimitHit?
    private(set) var latestUsage: UsageSnapshot?
    private(set) var madeProgress = false
    private(set) var creditsRequired = false
    private(set) var exitStatus: Int32?
    private(set) var wasCancelled = false

    static let creditsMessage = "Este modelo exige créditos de uso nesta conta. Troque o modelo da tarefa ou adicione créditos em claude.ai › Configurações › Uso."
    private static let creditErrors: Set<String> = ["model_requires_usage_credits", "long_context_credits_required"]

    private var toolIndex: [String: Int] = [:]
    private var warnedKinds: Set<String> = []
    private var sequence = 0

    @discardableResult
    mutating func consume(_ object: [String: Any]) -> UsageSnapshot? {
        switch object["type"] as? String {
        case "notchclaude_input": consumeInput(object)
        case "notchclaude_exit": consumeExit(object)
        case "system": consumeSystem(object)
        case "assistant": consumeAssistant(object)
        case "user": consumeUser(object)
        case "stream_event": consumeStream(object)
        case "rate_limit_event": return consumeRateLimit(object)
        case "result": consumeResult(object)
        default: break
        }
        return nil
    }

    mutating func finishReplay() {
        liveText = ""
    }

    func outcome(cancelled: Bool, stderr: String) -> (RunOutcome, RateLimitHit?) {
        if cancelled { return (.cancelled, nil) }
        if creditsRequired { return (.failed, nil) }
        if let usageLimitHit { return (.rateLimited, usageLimitHit) }
        if let result, !result.isError { return (.success, nil) }
        if let rejectedEvent { return (.rateLimited, rejectedEvent) }
        if let result, let hit = LimitTextParser.parse(result.text) { return (.rateLimited, hit) }
        if result == nil, let hit = LimitTextParser.parse(stderr) { return (.rateLimited, hit) }
        return (.failed, nil)
    }

    var failureSummary: String? {
        if creditsRequired { return Self.creditsMessage }
        for item in items.reversed() {
            switch item.kind {
            case .failure(let text): return text
            case .result(let info) where info.isError: return info.text
            default: continue
            }
        }
        return nil
    }

    private mutating func nextId() -> String {
        sequence += 1
        return "t\(sequence)"
    }

    private mutating func append(_ kind: TranscriptItem.Kind, nested: Bool = false) {
        items.append(TranscriptItem(id: nextId(), kind: kind, isNested: nested))
    }

    private mutating func consumeInput(_ object: [String: Any]) {
        let attachments = (object["attachments"] as? [[String: Any]] ?? []).map {
            AttachmentReference(
                path: $0["path"] as? String ?? "",
                name: $0["name"] as? String ?? "",
                isImage: $0["isImage"] as? Bool ?? false
            )
        }
        let date = (object["date"] as? Double).map { Date(timeIntervalSince1970: $0) }
        append(.prompt(
            text: object["prompt"] as? String ?? "",
            attachments: attachments,
            isResume: object["resume"] as? Bool ?? false,
            date: date
        ))
    }

    private mutating func consumeExit(_ object: [String: Any]) {
        exitStatus = Int32(object["status"] as? Int ?? 0)
        wasCancelled = object["cancelled"] as? Bool ?? false
        liveText = ""
        guard result == nil else { return }
        if wasCancelled {
            append(.system(text: "Execução interrompida", symbol: "stop.circle"))
            return
        }
        let stderr = (object["stderr"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let message = stderr.isEmpty ? "O Claude encerrou com código \(exitStatus ?? -1)" : stderr
        append(.failure(text: message))
    }

    private mutating func consumeSystem(_ object: [String: Any]) {
        switch object["subtype"] as? String {
        case "init":
            sessionId = object["session_id"] as? String ?? sessionId
            model = object["model"] as? String
            cwd = object["cwd"] as? String
            let skills = (object["skills"] as? [Any])?.count ?? 0
            let servers = (object["mcp_servers"] as? [Any])?.count ?? 0
            var parts = ["Claude Code \(object["claude_code_version"] as? String ?? "")".trimmingCharacters(in: .whitespaces)]
            if let model { parts.append(model) }
            if skills > 0 { parts.append("\(skills) skills") }
            if servers > 0 { parts.append("\(servers) MCP") }
            append(.system(text: parts.joined(separator: " · "), symbol: "sparkle"))
            activity = "Pensando…"
        case "api_retry":
            let attempt = object["attempt"] as? Int ?? 0
            let total = object["max_retries"] as? Int ?? 0
            append(.system(text: "API instável, tentando novamente (\(attempt)/\(total))", symbol: "arrow.clockwise"))
        case "compact_boundary":
            append(.system(text: "Contexto compactado", symbol: "arrow.down.right.and.arrow.up.left"))
        case "status":
            if (object["status"] as? String) == "compacting" { activity = "Compactando contexto…" }
        default:
            break
        }
    }

    private mutating func consumeAssistant(_ object: [String: Any]) {
        guard let message = object["message"] as? [String: Any] else { return }
        let nested = object["parent_tool_use_id"] is String
        let isApiError = object["is_api_error_message"] as? Bool ?? false
        let apiError = object["api_error"] as? String

        if let apiError, Self.creditErrors.contains(apiError) {
            creditsRequired = true
        } else if apiError == "usage_limit_reached" || ((object["error"] as? String) == "rate_limit" && apiError == nil) {
            let params = object["api_error_params"] as? [String: Any]
            let info = params?["rate_limit_info"] as? [String: Any]
            usageLimitHit = RateLimitHit(
                resetsAt: Self.date(info?["resetsAt"]),
                kind: info?["rateLimitType"] as? String ?? (info == nil ? "throttle" : nil)
            )
        }

        for block in message["content"] as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "text":
                let text = block["text"] as? String ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                if isApiError {
                    append(.failure(text: creditsRequired ? "\(Self.creditsMessage)\n\n\(text)" : text), nested: nested)
                } else {
                    append(.assistant(text: text), nested: nested)
                    madeProgress = true
                }
                if !nested { liveText = "" }
            case "thinking":
                let text = block["thinking"] as? String ?? ""
                if !text.isEmpty { append(.thinking(text: text), nested: nested) }
                madeProgress = true
            case "tool_use":
                let call = ToolFormatter.make(
                    id: block["id"] as? String ?? UUID().uuidString,
                    name: block["name"] as? String ?? "Tool",
                    input: block["input"] as? [String: Any] ?? [:],
                    cwd: cwd
                )
                append(.tool(call), nested: nested)
                toolIndex[call.id] = items.count - 1
                activity = ToolFormatter.activity(for: call)
                madeProgress = true
            default:
                break
            }
        }
    }

    private mutating func consumeUser(_ object: [String: Any]) {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return }
        for block in content where (block["type"] as? String) == "tool_result" {
            guard let id = block["tool_use_id"] as? String,
                  let index = toolIndex[id],
                  case .tool(var call) = items[index].kind else { continue }
            call.output = ToolFormatter.flattenToolResult(block["content"])
            call.isError = block["is_error"] as? Bool ?? false
            call.isDone = true
            items[index].kind = .tool(call)
        }
        if !(object["parent_tool_use_id"] is String) { activity = "Pensando…" }
    }

    private mutating func consumeStream(_ object: [String: Any]) {
        guard !(object["parent_tool_use_id"] is String),
              let event = object["event"] as? [String: Any] else { return }
        switch event["type"] as? String {
        case "content_block_start":
            let block = event["content_block"] as? [String: Any]
            switch block?["type"] as? String {
            case "thinking": activity = "Pensando…"
            case "text":
                activity = "Escrevendo…"
                liveText = ""
            case "tool_use": activity = "Preparando \(block?["name"] as? String ?? "ferramenta")…"
            default: break
            }
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any]
            if (delta?["type"] as? String) == "text_delta", let text = delta?["text"] as? String {
                liveText += text
            }
        default:
            break
        }
    }

    private mutating func consumeRateLimit(_ object: [String: Any]) -> UsageSnapshot? {
        guard let info = object["rate_limit_info"] as? [String: Any] else { return nil }
        var snapshot = latestUsage ?? UsageSnapshot(updatedAt: Date())
        snapshot.updatedAt = Date()

        if let windows = info["unifiedWindows"] as? [String: Any] {
            if let window = Self.window(windows["five_hour"]) { snapshot.fiveHour = window }
            if let window = Self.window(windows["seven_day"]) { snapshot.sevenDay = window }
        } else if let kind = info["rateLimitType"] as? String,
                  let utilization = Self.number(info["utilization"]),
                  let resetsAt = Self.date(info["resetsAt"]) {
            let window = UsageWindow(utilization: utilization, resetsAt: resetsAt)
            if kind == "five_hour" { snapshot.fiveHour = window } else if kind.hasPrefix("seven_day") { snapshot.sevenDay = window }
        }

        let kind = info["rateLimitType"] as? String
        switch info["status"] as? String {
        case "rejected":
            if (info["errorCode"] as? String) != "credits_required" {
                rejectedEvent = RateLimitHit(resetsAt: Self.date(info["resetsAt"]), kind: kind)
            }
        case "allowed_warning":
            let key = kind ?? "limit"
            if !warnedKinds.contains(key) {
                warnedKinds.insert(key)
                let percent = Self.number(info["utilization"]).map { " · \(Int(($0 * 100).rounded()))% usado" } ?? ""
                append(.system(text: "Perto do \(LimitState.label(for: kind).lowercased())\(percent)", symbol: "exclamationmark.triangle"))
            }
        default:
            break
        }

        latestUsage = snapshot
        return snapshot
    }

    private mutating func consumeResult(_ object: [String: Any]) {
        let usage = object["usage"] as? [String: Any] ?? [:]
        let input = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            .compactMap { Self.number(usage[$0]) }
            .reduce(0, +)
        var text = object["result"] as? String ?? ""
        if text.isEmpty, let errors = object["errors"] as? [String] { text = errors.joined(separator: "\n") }
        let info = ResultInfo(
            isError: object["is_error"] as? Bool ?? false,
            subtype: object["subtype"] as? String ?? "",
            text: text,
            costUSD: Self.number(object["total_cost_usd"]),
            durationMs: Self.number(object["duration_ms"]).map { Int($0) },
            numTurns: Self.number(object["num_turns"]).map { Int($0) },
            inputTokens: Int(input),
            outputTokens: Self.number(usage["output_tokens"]).map { Int($0) },
            sessionId: object["session_id"] as? String
        )
        result = info
        sessionId = info.sessionId ?? sessionId
        liveText = ""
        activity = info.isError ? "Falhou" : "Concluído"
        append(.result(info))
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let dictionary = value as? [String: Any],
              let utilization = number(dictionary["utilization"]),
              let resetsAt = date(dictionary["resetsAt"]) else { return nil }
        return UsageWindow(utilization: utilization, resetsAt: resetsAt)
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        guard let seconds = number(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
    }
}
