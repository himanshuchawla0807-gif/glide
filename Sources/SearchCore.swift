import Foundation

enum SearchDestination {
    static func url(for input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let parts = URLComponents(string: text),
           ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
           let host = parts.host, !host.isEmpty, !text.contains(where: { $0.isWhitespace }) {
            return parts.url
        }
        let pattern = #"^(localhost|(?:[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?\.)+[\p{L}]{2,}|(?:\d{1,3}\.){3}\d{1,3})(:\d{1,5})?([/?#][^\s]*)?$"#
        if text.range(of: pattern, options: .regularExpression) != nil {
            return URL(string: (text.hasPrefix("localhost") ? "http://" : "https://") + text)
        }
        var parts = URLComponents(string: "https://www.google.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: text)]
        return parts.url
    }

    static func isWebsite(_ text: String) -> Bool {
        guard let url = url(for: text) else { return false }
        return !(url.host == "www.google.com" && url.path == "/search")
    }

    static func suggestions(from data: Data, query: String) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1, let strings = json[1] as? [String] else { return [] }
        var seen = Set([query.lowercased()])
        return strings.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(5).map { $0 }
    }

    static func validProfile(_ value: String) -> Bool {
        value == "Default" || value.range(of: #"^Profile [0-9]+$"#, options: .regularExpression) != nil
    }
}
