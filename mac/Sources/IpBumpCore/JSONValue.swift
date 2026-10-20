/// JSON that keeps what people care about in their own config files: the order of keys, the spelling of numbers
/// and readable text. Connect and Disconnect change IpBump's entries and leave the rest as it was.
public indirect enum JSONValue: Equatable, Sendable {
    case object(JSONObject)
    case array([JSONValue])
    case string(String)
    /// The number as written, so 1.0 stays 1.0 and big numbers keep every digit.
    case number(String)
    case bool(Bool)
    case null

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var parser = Parser(bytes: Array(text.utf8))
        return try parser.document()
    }

    /// Compact, or laid out like JSON.stringify(value, null, 2).
    public func render(pretty: Bool) -> String {
        var out: [UInt8] = []
        write(into: &out, pretty: pretty, depth: 0)
        return String(decoding: out, as: UTF8.self)
    }

    func write(into out: inout [UInt8], pretty: Bool, depth: Int) {
        func newline(_ depth: Int) {
            guard pretty else { return }
            out.append(0x0A)
            out.append(contentsOf: repeatElement(0x20, count: depth * 2))
        }
        switch self {
        case .null: out.append(contentsOf: "null".utf8)
        case .bool(let b): out.append(contentsOf: (b ? "true" : "false").utf8)
        case .number(let n): out.append(contentsOf: n.utf8)
        case .string(let s): Self.quote(s, into: &out)
        case .array(let items):
            guard !items.isEmpty else { return out.append(contentsOf: "[]".utf8) }
            out.append(UInt8(ascii: "["))
            for (n, item) in items.enumerated() {
                if n > 0 { out.append(UInt8(ascii: ",")) }
                newline(depth + 1)
                item.write(into: &out, pretty: pretty, depth: depth + 1)
            }
            newline(depth)
            out.append(UInt8(ascii: "]"))
        case .object(let o):
            guard o.count > 0 else { return out.append(contentsOf: "{}".utf8) }
            out.append(UInt8(ascii: "{"))
            for (n, entry) in o.entries.enumerated() {
                if n > 0 { out.append(UInt8(ascii: ",")) }
                newline(depth + 1)
                Self.quote(entry.key, into: &out)
                out.append(contentsOf: (pretty ? ": " : ":").utf8)
                entry.value.write(into: &out, pretty: pretty, depth: depth + 1)
            }
            newline(depth)
            out.append(UInt8(ascii: "}"))
        }
    }

    /// Escapes only what JSON requires; other characters, "/" included, stay as they are.
    static func quote(_ s: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for byte in s.utf8 {
            switch byte {
            case UInt8(ascii: "\""): out.append(contentsOf: #"\""#.utf8)
            case UInt8(ascii: "\\"): out.append(contentsOf: #"\\"#.utf8)
            case 0x0A: out.append(contentsOf: #"\n"#.utf8)
            case 0x0D: out.append(contentsOf: #"\r"#.utf8)
            case 0x09: out.append(contentsOf: #"\t"#.utf8)
            case 0x08: out.append(contentsOf: #"\b"#.utf8)
            case 0x0C: out.append(contentsOf: #"\f"#.utf8)
            case ..<0x20:
                let hex = Array("0123456789abcdef".utf8)
                out.append(contentsOf: #"\u00"#.utf8)
                out.append(hex[Int(byte >> 4)])
                out.append(hex[Int(byte & 15)])
            default: out.append(byte)
            }
        }
        out.append(UInt8(ascii: "\""))
    }
}

/// A JSON object whose keys stay in the order they were written. A new key goes last.
public struct JSONObject: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var key: String
        public var value: JSONValue
    }

    public private(set) var entries: [Entry]

    public init(_ pairs: [(String, JSONValue)] = []) {
        entries = pairs.map { Entry(key: $0.0, value: $0.1) }
    }

    init(entries: [Entry]) { self.entries = entries }

    public var keys: [String] { entries.map(\.key) }
    public var count: Int { entries.count }

    /// Setting nil removes the key; an existing key keeps its place.
    public subscript(key: String) -> JSONValue? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let i = entries.firstIndex(where: { $0.key == key }) {
                if let newValue { entries[i].value = newValue } else { entries.remove(at: i) }
            } else if let newValue {
                entries.append(Entry(key: key, value: newValue))
            }
        }
    }
}

/// RFC 8259, strictly, over UTF-8 bytes.
private struct Parser {
    let bytes: [UInt8]
    var i = 0

    mutating func document() throws -> JSONValue {
        skipSpace()
        let value = try self.value()
        skipSpace()
        guard i == bytes.count else { throw fail("unexpected text after the end") }
        return value
    }

    mutating func value() throws -> JSONValue {
        guard i < bytes.count else { throw fail("it ends too early") }
        switch bytes[i] {
        case UInt8(ascii: "{"): return .object(try object())
        case UInt8(ascii: "["): return .array(try array())
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
        default: throw fail("unexpected character")
        }
    }

    mutating func object() throws -> JSONObject {
        i += 1
        var entries: [JSONObject.Entry] = []
        skipSpace()
        if peek(UInt8(ascii: "}")) { i += 1; return JSONObject(entries: entries) }
        while true {
            skipSpace()
            guard peek(UInt8(ascii: "\"")) else { throw fail("expected a key in quotes") }
            let key = try string()
            skipSpace()
            guard peek(UInt8(ascii: ":")) else { throw fail("expected \":\"") }
            i += 1
            skipSpace()
            entries.append(JSONObject.Entry(key: key, value: try value()))
            skipSpace()
            if peek(UInt8(ascii: ",")) { i += 1; continue }
            if peek(UInt8(ascii: "}")) { i += 1; return JSONObject(entries: entries) }
            throw fail("expected \",\" or \"}\"")
        }
    }

    mutating func array() throws -> [JSONValue] {
        i += 1
        var items: [JSONValue] = []
        skipSpace()
        if peek(UInt8(ascii: "]")) { i += 1; return items }
        while true {
            skipSpace()
            items.append(try value())
            skipSpace()
            if peek(UInt8(ascii: ",")) { i += 1; continue }
            if peek(UInt8(ascii: "]")) { i += 1; return items }
            throw fail("expected \",\" or \"]\"")
        }
    }

    mutating func string() throws -> String {
        i += 1
        var text: [UInt8] = []
        var start = i
        while i < bytes.count {
            switch bytes[i] {
            case UInt8(ascii: "\""):
                text.append(contentsOf: bytes[start..<i])
                i += 1
                return String(decoding: text, as: UTF8.self)
            case UInt8(ascii: "\\"):
                text.append(contentsOf: bytes[start..<i])
                try escape(into: &text)
                start = i
            case ..<0x20:
                throw fail("control character inside a string")
            default:
                i += 1
            }
        }
        throw fail("a string is not closed")
    }

    mutating func escape(into text: inout [UInt8]) throws {
        i += 1
        guard i < bytes.count else { throw fail("it ends too early") }
        let c = bytes[i]
        i += 1
        switch c {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): text.append(c)
        case UInt8(ascii: "b"): text.append(0x08)
        case UInt8(ascii: "f"): text.append(0x0C)
        case UInt8(ascii: "n"): text.append(0x0A)
        case UInt8(ascii: "r"): text.append(0x0D)
        case UInt8(ascii: "t"): text.append(0x09)
        case UInt8(ascii: "u"):
            var code = try hex4()
            // A character outside the Basic Multilingual Plane comes as two escapes, a surrogate pair
            if (0xD800...0xDBFF).contains(code), bytes[i...].starts(with: Array(#"\u"#.utf8)) {
                i += 2
                let low = try hex4()
                guard (0xDC00...0xDFFF).contains(low) else { throw fail("broken surrogate pair") }
                code = 0x10000 + (code - 0xD800) << 10 + (low - 0xDC00)
            }
            text.append(contentsOf: String(Unicode.Scalar(code).map(Character.init) ?? "\u{FFFD}").utf8)
        default:
            throw fail("unknown escape")
        }
    }

    mutating func hex4() throws -> UInt32 {
        guard i + 4 <= bytes.count, let n = UInt32(String(decoding: bytes[i..<(i + 4)], as: UTF8.self), radix: 16) else {
            throw fail("bad \\u escape")
        }
        i += 4
        return n
    }

    mutating func number() throws -> String {
        let start = i
        func digits() -> Int {
            let from = i
            while i < bytes.count, bytes[i] >= UInt8(ascii: "0"), bytes[i] <= UInt8(ascii: "9") { i += 1 }
            return i - from
        }
        if peek(UInt8(ascii: "-")) { i += 1 }
        if peek(UInt8(ascii: "0")) { i += 1 } else if digits() == 0 { throw fail("bad number") }
        if peek(UInt8(ascii: ".")) {
            i += 1
            guard digits() > 0 else { throw fail("bad number") }
        }
        if peek(UInt8(ascii: "e")) || peek(UInt8(ascii: "E")) {
            i += 1
            if peek(UInt8(ascii: "+")) || peek(UInt8(ascii: "-")) { i += 1 }
            guard digits() > 0 else { throw fail("bad number") }
        }
        return String(decoding: bytes[start..<i], as: UTF8.self)
    }

    mutating func literal(_ word: String) throws {
        let w = Array(word.utf8)
        guard bytes[i...].starts(with: w) else { throw fail("unexpected character") }
        i += w.count
    }

    func peek(_ c: UInt8) -> Bool { i < bytes.count && bytes[i] == c }

    mutating func skipSpace() {
        while i < bytes.count {
            switch bytes[i] {
            case 0x20, 0x09, 0x0A, 0x0D: i += 1
            default: return
            }
        }
    }

    func fail(_ what: String) -> JSONValue.ParseError {
        JSONValue.ParseError(description: "It is not valid JSON: \(what) at byte \(i + 1).")
    }
}
