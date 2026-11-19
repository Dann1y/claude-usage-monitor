import Foundation
import Combine

// MARK: - Prices

/// Anthropic API list prices in USD per million tokens.
/// Cache writes are 1.25x input (5-minute TTL) and 2x input (1-hour TTL).
struct ModelPrice {
    let input: Double
    let output: Double
    let cacheRead: Double

    var cacheWrite5m: Double { input * 1.25 }
    var cacheWrite1h: Double { input * 2 }

    static func scaled(_ p: ModelPrice, by factor: Double) -> ModelPrice {
        ModelPrice(input: p.input * factor, output: p.output * factor, cacheRead: p.cacheRead * factor)
    }

    /// Prices keyed by model id without a date suffix.
    static let table: [String: ModelPrice] = [
        "claude-fable-5-2": ModelPrice(input: 8, output: 40, cacheRead: 0.20),
        "claude-mythos-5-2": ModelPrice(input: 8, output: 40, cacheRead: 0.20),
        "claude-fable-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
        "claude-mythos-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
        "claude-fable-5": ModelPrice(input: 10, output: 50, cacheRead: 1.00),
        "claude-mythos-5": ModelPrice(input: 10, output: 50, cacheRead: 1.00),
        "claude-opus-5-5": ModelPrice(input: 4, output: 20, cacheRead: 0.20),
        "claude-opus-5": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-8": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-7": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-6": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-5": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-1": ModelPrice(input: 15, output: 75, cacheRead: 1.50),
        "claude-opus-4": ModelPrice(input: 15, output: 75, cacheRead: 1.50),
        "claude-sonnet-5-5": ModelPrice(input: 2, output: 10, cacheRead: 0.10),
        "claude-sonnet-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
        "claude-sonnet-4-6": ModelPrice(input: 3, output: 15, cacheRead: 0.30),
        "claude-sonnet-4-5": ModelPrice(input: 3, output: 15, cacheRead: 0.30),
        "claude-sonnet-4": ModelPrice(input: 3, output: 15, cacheRead: 0.30),
        "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01),
        "claude-haiku-4-5": ModelPrice(input: 1, output: 5, cacheRead: 0.10),
    ]

    /// Claude Haiku 5.5 costs more once the prompt passes 100K tokens.
    static let haiku55Long = ModelPrice(input: 0.50, output: 2.50, cacheRead: 0.05)

    /// Price for a bucket key written by the scanner ("model", "model|long", "model|fast").
    static func price(forBucket key: String) -> ModelPrice? {
        let parts = key.split(separator: "|").map(String.init)
        guard let model = parts.first else { return nil }
        let flags = Set(parts.dropFirst())
        var price: ModelPrice?
        if model == "claude-haiku-5-5", flags.contains("long") {
            price = haiku55Long
        } else {
            price = table[model]
        }
        guard let base = price else { return nil }
        // Fast mode is billed at twice the standard rate.
        return flags.contains("fast") ? scaled(base, by: 2) : base
    }

    /// "claude-opus-4-5-20251101" -> "claude-opus-4-5"
    static func normalize(_ model: String) -> String {
        model.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
    }
}

// MARK: - Token totals

struct TokenTotals: Codable, Equatable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheWrite5m: Int = 0
    var cacheWrite1h: Int = 0

    mutating func add(_ other: TokenTotals) {
        input += other.input
        output += other.output
        cacheRead += other.cacheRead
        cacheWrite5m += other.cacheWrite5m
        cacheWrite1h += other.cacheWrite1h
    }

    func cost(_ p: ModelPrice) -> Double {
        (Double(input) * p.input
            + Double(output) * p.output
            + Double(cacheRead) * p.cacheRead
            + Double(cacheWrite5m) * p.cacheWrite5m
            + Double(cacheWrite1h) * p.cacheWrite1h) / 1_000_000
    }
}

struct MonthCost: Identifiable {
    let id: String     // "2026-11"
    let start: Date
    let cost: Double
}

// MARK: - Log scanner

/// Reads Claude Code's session logs (~/.claude/projects/**/*.jsonl) and totals
/// token usage per local calendar month and model.
///
/// Logs are append-only and large (gigabytes), so the scanner remembers how far
/// it read each file and only parses new bytes. The same API response is often
/// written to several files (resumed sessions copy their history), so responses
/// are de-duplicated by message id + request id across all files. Totals are kept
/// on disk, so months survive Claude Code deleting old logs.
final class UsageLogScanner {
    struct State: Codable {
        var version = 1
        var offsets: [String: UInt64] = [:]
        var seen: Set<UInt64> = []
        /// month ("yyyy-MM") -> bucket ("model[|flag]") -> tokens
        var months: [String: [String: TokenTotals]] = [:]
    }

    private(set) var state: State
    private let stateURL: URL
    private let roots: [URL]

    init(stateURL: URL? = nil, roots: [URL]? = nil) {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageMonitor", isDirectory: true)
        self.stateURL = stateURL ?? support.appendingPathComponent("api-cost-cache.json")
        let home = fm.homeDirectoryForCurrentUser
        self.roots = roots ?? [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(".config/claude/projects", isDirectory: true),
        ]
        if let data = try? Data(contentsOf: self.stateURL),
           let saved = try? JSONDecoder().decode(State.self, from: data),
           saved.version == State().version {
            state = saved
        } else {
            state = State()
        }
    }

    /// Reads any new log lines. Returns true if totals changed.
    @discardableResult
    func scan() -> Bool {
        var changed = false
        for file in logFiles() {
            let path = file.path
            guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value
            else { continue }
            var offset = state.offsets[path] ?? 0
            if size < offset { offset = 0 } // file was rewritten
            guard size > offset else { continue }
            let newOffset = read(file: file, from: offset, changed: &changed)
            if newOffset != state.offsets[path] {
                state.offsets[path] = newOffset
                changed = true
            }
        }
        if changed { save() }
        return changed
    }

    func monthlyCosts() -> (months: [MonthCost], unpricedModels: [String]) {
        var unpriced = Set<String>()
        var result: [MonthCost] = []
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM"
        for (month, buckets) in state.months {
            var total = 0.0
            for (bucket, tokens) in buckets {
                if let price = ModelPrice.price(forBucket: bucket) {
                    total += tokens.cost(price)
                } else {
                    unpriced.insert(String(bucket.split(separator: "|")[0]))
                }
            }
            guard let start = parser.date(from: month) else { continue }
            result.append(MonthCost(id: month, start: start, cost: total))
        }
        return (result.sorted { $0.id > $1.id }, unpriced.sorted())
    }

    // MARK: Reading

    private func logFiles() -> [URL] {
        var files: [URL] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                files.append(url)
            }
        }
        return files
    }

    /// Parses complete lines from `offset` on and returns the offset after the last newline.
    private func read(file: URL, from offset: UInt64, changed: inout Bool) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return offset }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return offset }

        var consumed = offset
        var pending = Data()
        while true {
            guard let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty else { break }
            pending.append(chunk)
            let lastLineEnd = pending.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
                let count = raw.count
                var start = 0
                var end = -1
                while start < count,
                      let nl = memchr(base + start, 0x0A, count - start) {
                    let i = base.distance(to: nl.assumingMemoryBound(to: UInt8.self))
                    if process(line: UnsafeBufferPointer(start: base + start, count: i - start)) { changed = true }
                    start = i + 1
                    end = i
                }
                return end
            }
            if lastLineEnd >= 0 {
                consumed += UInt64(lastLineEnd + 1)
                pending = pending.subdata(in: (lastLineEnd + 1)..<pending.count)
            }
        }
        return consumed
    }

    private static let usageKey = Array(#""usage":{"#.utf8)
    private static let assistantKey = Array(#""type":"assistant""#.utf8)
    private static let messageIdKey = Array(#""id":"msg_"#.utf8)
    private static let modelKey = Array(#""model":""#.utf8)
    private static let requestIdKey = Array(#""requestId":""#.utf8)
    private static let timestampKey = Array(#""timestamp":""#.utf8)

    /// Pulls the few fields we need out of an assistant log line without parsing the
    /// whole line (lines carry full message content, gigabytes in total). Claude Code
    /// writes `message` (id, model, content, usage) before the top-level `requestId`
    /// and `timestamp`, so message fields are the first match and top-level fields
    /// the last. Keys inside string values are escaped, so they can't match.
    private func process(line: UnsafeBufferPointer<UInt8>) -> Bool {
        guard Self.find(Self.usageKey, in: line) != nil,
              Self.find(Self.assistantKey, in: line) != nil,
              let idStart = Self.find(Self.messageIdKey, in: line).map({ $0 + Self.messageIdKey.count - 4 }),
              let messageId = Self.string(in: line, at: idStart),
              let modelStart = Self.find(Self.modelKey, in: line).map({ $0 + Self.modelKey.count }),
              let rawModel = Self.string(in: line, at: modelStart), rawModel != "<synthetic>",
              let tsStart = Self.find(Self.timestampKey, in: line, last: true).map({ $0 + Self.timestampKey.count }),
              let timestamp = Self.string(in: line, at: tsStart),
              let usageStart = Self.find(Self.usageKey, in: line, last: true).map({ $0 + Self.usageKey.count - 1 }),
              let usageEnd = Self.objectEnd(in: line, from: usageStart)
        else { return false }

        let requestId = Self.find(Self.requestIdKey, in: line, last: true)
            .flatMap { Self.string(in: line, at: $0 + Self.requestIdKey.count) } ?? ""
        let key = Self.fnv1a("\(messageId)|\(requestId)")
        guard !state.seen.contains(key) else { return false }

        let usageData = Data(UnsafeBufferPointer(rebasing: line[usageStart...usageEnd]))
        guard let usage = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any],
              let date = Self.parseDate(timestamp)
        else { return false }
        state.seen.insert(key)

        func int(_ any: Any?) -> Int { (any as? NSNumber)?.intValue ?? 0 }
        var tokens = TokenTotals()
        tokens.input = int(usage["input_tokens"])
        tokens.output = int(usage["output_tokens"])
        tokens.cacheRead = int(usage["cache_read_input_tokens"])
        if let creation = usage["cache_creation"] as? [String: Any] {
            tokens.cacheWrite5m = int(creation["ephemeral_5m_input_tokens"])
            tokens.cacheWrite1h = int(creation["ephemeral_1h_input_tokens"])
        } else {
            tokens.cacheWrite5m = int(usage["cache_creation_input_tokens"])
        }

        let model = ModelPrice.normalize(rawModel)
        var bucket = model
        let prompt = tokens.input + tokens.cacheRead + tokens.cacheWrite5m + tokens.cacheWrite1h
        if model == "claude-haiku-5-5", prompt > 100_000 { bucket += "|long" }
        if usage["speed"] as? String == "fast" { bucket += "|fast" }

        let month = Self.monthFormatter.string(from: date)
        state.months[month, default: [:]][bucket, default: TokenTotals()].add(tokens)
        return true
    }

    // MARK: Byte helpers

    private static func find(_ needle: [UInt8], in line: UnsafeBufferPointer<UInt8>, last: Bool = false) -> Int? {
        guard let base = line.baseAddress else { return nil }
        var from = 0
        var found: Int?
        while from + needle.count <= line.count {
            let hit = needle.withUnsafeBytes { n in
                memmem(base + from, line.count - from, n.baseAddress, needle.count)
            }
            guard let hit else { break }
            let index = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(hit))
            if !last { return index }
            found = index
            from = index + 1
        }
        return found
    }

    /// A JSON string value starting right after its opening quote.
    private static func string(in line: UnsafeBufferPointer<UInt8>, at start: Int) -> String? {
        var i = start
        while i < line.count {
            if line[i] == 0x5C { i += 2; continue } // backslash escape
            if line[i] == 0x22 { return String(decoding: UnsafeBufferPointer(rebasing: line[start..<i]), as: UTF8.self) }
            i += 1
        }
        return nil
    }

    /// Index of the `}` closing the object that opens at `start`.
    private static func objectEnd(in line: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        guard start < line.count, line[start] == 0x7B else { return nil }
        var depth = 0
        var inString = false
        var i = start
        while i < line.count {
            let c = line[i]
            if inString {
                if c == 0x5C { i += 2; continue }
                if c == 0x22 { inString = false }
            } else if c == 0x22 {
                inString = true
            } else if c == 0x7B {
                depth += 1
            } else if c == 0x7D {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? UsageSummary.parseISO8601(string)
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            print("⚠️ Couldn't save API cost cache: \(error)")
        }
    }
}

// MARK: - Observable wrapper

@MainActor
final class APICostTracker: ObservableObject {
    @Published private(set) var months: [MonthCost] = []
    @Published private(set) var unpricedModels: [String] = []
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false

    private let scanner = UsageLogScanner()
    private let queue = DispatchQueue(label: "ClaudeUsageMonitor.APICostTracker", qos: .utility)
    private var lastScan: Date?
    private var timer: Timer?

    init() {
        // Show what we already know right away; the scan only adds new lines.
        publish(scanner.monthlyCosts())
        hasScanned = !months.isEmpty
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isScanning else { return }
        if let lastScan, Date().timeIntervalSince(lastScan) < 30 { return }
        isScanning = true
        let scanner = self.scanner
        queue.async {
            scanner.scan()
            let result = scanner.monthlyCosts()
            DispatchQueue.main.async {
                self.publish(result)
                self.lastScan = Date()
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    private func publish(_ result: (months: [MonthCost], unpricedModels: [String])) {
        months = result.months
        unpricedModels = result.unpricedModels
    }
}
