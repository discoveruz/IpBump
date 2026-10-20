import Foundation
import Testing
@testable import IpBumpCore

struct JSONValueTests {
    @Test func keepsKeyOrderAndNumberSpelling() throws {
        let text = #"{"z":1.0,"a":[1e5,-0,12345678901234567890],"m":{"k":null,"t":true}}"#
        #expect(try JSONValue.parse(text).render(pretty: false) == text)
    }

    @Test func keepsTextReadable() throws {
        let text = #"{"name":"Café ʻ😀 Привет","path":"a/b","q":"say \"hi\"\n\t\u0001"}"#
        #expect(try JSONValue.parse(text).render(pretty: false) == text)
        #expect(try JSONValue.parse(#""😀""#) == .string("😀"))
    }

    @Test func printsLikeJsonStringify() throws {
        #expect(try JSONValue.parse(#"{"a":{},"b":[],"c":[1,{"d":"e"}]}"#).render(pretty: true)
            == "{\n  \"a\": {},\n  \"b\": [],\n  \"c\": [\n    1,\n    {\n      \"d\": \"e\"\n    }\n  ]\n}")
    }

    @Test func editsInPlace() {
        var o = JSONObject([("a", .number("1")), ("b", .number("2"))])
        o["a"] = .bool(true)
        o["c"] = .null
        o["b"] = nil
        #expect(o.keys == ["a", "c"])
        #expect(o["a"] == .bool(true))
    }

    @Test func readsNestedValues() throws {
        let v = try JSONValue.parse(#"{"tools":[{"name":"x"}]}"#)
        #expect(v["tools"]?[0]?["name"] == .string("x"))
        #expect(v["tools"]?[1] == nil)
        #expect(v["nope"] == nil)
    }

    @Test func rejectsBrokenJson() {
        for text in ["{", #"{"a":1,}"#, #"{"a" 1}"#, "[1] x", #""abc"#, "tru", "", "01", "[1,]"] {
            #expect(throws: (any Error).self, "\(text)") { try JSONValue.parse(text) }
        }
    }

    /// Review Focus 3: a config as big and as mixed as a well-used ~/.claude.json (about 1 MB).
    @Test func handlesARealisticClaudeConfig() throws {
        var projects: [String] = []
        for i in 0..<3200 {
            projects.append(#""/Users/someone/dev/проект-\#(i) ʻ😀": {"allowedTools": ["Bash(git:*)", "Edit"], "#
                + #""lastCost": 0.5, "lastSessionId": "6f1c2a8e-\#(i)", "history": [{"display": "fix \"quotes\" and \\ \n", "#
                + #""pastedContents": {}}], "lastTotalInputTokens": 1729000000000, "trusted": true, "files": null}"#)
        }
        let big = #"{"numStartups": 42, "projects": {"# + projects.joined(separator: ", ") + "}}"
        #expect(big.utf8.count > 900_000)

        let start = ContinuousClock.now
        let once = try JSONValue.parse(big).render(pretty: true)
        #expect(try JSONValue.parse(once).render(pretty: true) == once)
        #expect(ContinuousClock.now - start < .seconds(10))   // about 0.5 s on a current Mac; a quadratic slip takes hours
        #expect(once.contains(#""lastTotalInputTokens": 1729000000000"#) && once.contains("проект-3199 ʻ😀"))
    }
}
