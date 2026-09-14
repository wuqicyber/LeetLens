import Foundation

enum LeetCodeStudyPlanInput {
    static let shortcuts: [(slug: String, title: String)] = [
        ("top-100-liked", "热题 100"), ("leetcode-75", "LeetCode 75"),
        ("top-interview-150", "面试经典 150"), ("programming-skills", "编程能力"),
        ("dynamic-programming", "动态规划"), ("graph-theory", "图论"), ("binary-search", "二分查找")
    ]

    static func slug(from input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSlug(value) { return value }
        if let url = URLComponents(string: value),
           url.scheme?.lowercased() == "https",
           ["leetcode.cn", "www.leetcode.cn"].contains(url.host?.lowercased() ?? ""),
           url.user == nil, url.password == nil, url.port == nil,
           url.query == nil, url.fragment == nil {
            let path = url.percentEncodedPath
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            if (parts.count == 3 || (parts.count == 4 && parts[3].isEmpty)),
               parts[0].isEmpty, parts[1] == "studyplan", isSlug(String(parts[2])) {
                return String(parts[2])
            }
        }
        throw LeetCodeAPIError.invalidResponse("请输入有效的 planSlug 或 https://leetcode.cn/studyplan/题单标识/ 链接（不含查询参数）")
    }

    private static func isSlug(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 100
            && value.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil
    }
}
