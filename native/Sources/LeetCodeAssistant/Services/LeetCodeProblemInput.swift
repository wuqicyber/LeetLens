import Foundation

struct LeetCodeProblemInput: Sendable {
    let query: String
    let explicitSlug: String?

    var isNumber: Bool { query.utf8.allSatisfy { (48...57).contains($0) } }

    init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 300,
              value.rangeOfCharacter(from: .controlCharacters) == nil else { throw Self.invalidInput }
        if let url = URLComponents(string: value), url.scheme != nil || value.hasPrefix("//") {
            guard url.scheme?.lowercased() == "https",
                  ["leetcode.cn", "www.leetcode.cn"].contains(url.host?.lowercased() ?? ""),
                  url.user == nil, url.password == nil, url.port == nil,
                  url.query == nil, url.fragment == nil else { throw Self.invalidInput }
            let parts = url.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard (parts.count == 3 || (parts.count == 4 && parts[3].isEmpty)),
                  parts[0].isEmpty, parts[1] == "problems", Self.isValidSlug(String(parts[2])) else {
                throw Self.invalidInput
            }
            query = String(parts[2])
            explicitSlug = query
        } else {
            guard value.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\<>`{};")) == nil,
                  value.unicodeScalars.first.map({ CharacterSet.alphanumerics.contains($0) }) == true else {
                throw Self.invalidInput
            }
            if value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
               !Self.isValidSlug(value) { throw Self.invalidInput }
            query = value
            explicitSlug = nil
        }
    }

    static func isValidSlug(_ value: String) -> Bool {
        // CN also uses opaque, case-sensitive slugs such as 7rLGCR.
        !value.isEmpty && value.utf8.count <= 200
            && value.range(of: #"^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$"#, options: .regularExpression) != nil
    }

    static var invalidInput: LeetCodeAPIError {
        .invalidResponse("请输入题号、中文/英文标题、有效 titleSlug，或 https://leetcode.cn/problems/题目标识/ 链接（不含查询参数）")
    }
}
