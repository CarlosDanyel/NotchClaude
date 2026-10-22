import Foundation
import OSLog

@MainActor
final class UsageMonitor {
    private nonisolated static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let interval: TimeInterval = 120

    private let store: TaskStore
    private let queue = DispatchQueue(label: "app.notchclaude.usage")
    private let log = Logger(subsystem: "app.notchclaude.NotchClaude", category: "usage")
    private var timer: Timer?
    private var lastFetch: Date?
    private var inFlight = false

    init(store: TaskStore) {
        self.store = store
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refreshIfStale() {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 30 { return }
        refresh()
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        lastFetch = Date()
        queue.async {
            Self.fetch { result in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.inFlight = false
                    switch result {
                    case .success(let snapshot):
                        self.store.updateUsage(snapshot)
                    case .failure(let error):
                        if error == .signedOut { self.store.clearUsage() }
                        self.log.error("Uso da conta indisponível: \(String(describing: error), privacy: .public)")
                    }
                }
            }
        }
    }

    enum FetchError: Error, Equatable {
        case signedOut
        case expired
        case http(Int)
        case invalidResponse
    }

    // Lê o token da conta logada no Claude Code a cada consulta, então trocar de conta já muda os números.
    // O token nunca é renovado aqui: quem renova é o próprio Claude Code, para não invalidar o login dele.
    private nonisolated static func fetch(completion: @escaping @Sendable (Result<UsageSnapshot, FetchError>) -> Void) {
        guard let credentials = readCredentials(),
              let oauth = credentials["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return completion(.failure(.signedOut))
        }
        if let expiresAt = (oauth["expiresAt"] as? NSNumber)?.doubleValue, expiresAt / 1000 < Date().timeIntervalSince1970 {
            return completion(.failure(.expired))
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data else { return completion(.failure(.http(status))) }
            guard let snapshot = snapshot(from: data) else { return completion(.failure(.invalidResponse)) }
            completion(.success(snapshot))
        }.resume()
    }

    private nonisolated static func readCredentials() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var data = Data()
        if (try? process.run()) != nil {
            data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        }
        if process.terminationStatus != 0 || data.isEmpty {
            let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
            data = (try? Data(contentsOf: file)) ?? Data()
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    nonisolated static func snapshot(from data: Data, now: Date = Date()) -> UsageSnapshot? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func window(_ key: String, length: TimeInterval) -> UsageWindow? {
            guard let item = object[key] as? [String: Any],
                  let utilization = (item["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let resetsAt = date(item["resets_at"] as? String) ?? now.addingTimeInterval(length)
            return UsageWindow(utilization: utilization / 100, resetsAt: resetsAt)
        }
        let fiveHour = window("five_hour", length: 5 * 3600)
        let sevenDay = window("seven_day", length: 7 * 86400)
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return UsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay, updatedAt: now)
    }

    // A data pode vir com ou sem fração de segundos; sem a fração, um único formato lê as duas.
    nonisolated static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}
