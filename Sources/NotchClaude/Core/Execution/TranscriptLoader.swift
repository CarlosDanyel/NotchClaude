import Foundation

enum TranscriptLoader {
    static func load(_ url: URL) -> TranscriptBuilder {
        var builder = TranscriptBuilder()
        guard let data = try? Data(contentsOf: url) else { return builder }
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            builder.consume(object)
        }
        builder.finishReplay()
        return builder
    }

    static func containsModelOutput(_ url: URL) -> Bool {
        load(url).madeProgress
    }
}
