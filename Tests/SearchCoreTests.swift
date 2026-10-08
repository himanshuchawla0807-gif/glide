import Foundation

@main enum CoreTests {
    static func main() throws {
        func expect(_ result: Bool, _ message: String) {
            if !result { fatalError(message) }
        }
        expect(SearchDestination.url(for: "  ") == nil, "Empty input must not launch")
        let phrases = ["swift & appkit", "a+b #c", "日本語 café", "javascript:alert(1)", "hello\nworld", "$(touch /tmp/glide-test)"]
        for text in phrases {
            let url = SearchDestination.url(for: text)!
            expect(url.host == "www.google.com", "Query must become Google search: \(text)")
            expect(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first!.value == text, "Query must round trip: \(text)")
        }
        expect(SearchDestination.url(for: "apple.com")?.absoluteString == "https://apple.com", "Bare domain")
        expect(SearchDestination.url(for: "https://example.com/a?q=b#c")?.absoluteString == "https://example.com/a?q=b#c", "URL retained")
        expect(SearchDestination.url(for: "localhost:3000/path")?.absoluteString == "http://localhost:3000/path", "Local development URL")
        expect(SearchDestination.validProfile("Default"), "Default profile")
        expect(SearchDestination.validProfile("Profile 12"), "Numbered profile")
        expect(!SearchDestination.validProfile("../Profile 2"), "Profile traversal rejected")
        let data = Data(#"["test",["test","Test","testing","testing","test app"]]"#.utf8)
        expect(SearchDestination.suggestions(from: data, query: "test") == ["testing", "test app"], "Deduplication")
        expect(SearchDestination.suggestions(from: Data("[]".utf8), query: "test").isEmpty, "Malformed suggestions")
        print("Passed: query escaping, safe schemes, direct URLs, profiles, suggestion parsing")
    }
}
