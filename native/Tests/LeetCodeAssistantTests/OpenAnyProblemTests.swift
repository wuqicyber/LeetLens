import Foundation
import Testing
@testable import LeetCodeAssistant

// Every session has its own queue, so parallel tests cannot consume each other's
// responses. Unexpected requests fail here and never reach the real network.
final class ProblemURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body = Data()
        var error: URLError?

        static func json(_ object: [String: Any]) throws -> Self {
            Self(body: try JSONSerialization.data(withJSONObject: object))
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [String: (replies: [Reply], requests: [URLRequest])] = [:]

    static func register(_ replies: [Reply], for key: String) {
        lock.withLock { queues[key] = (replies, []) }
    }
    static func requests(for key: String) -> [URLRequest] { lock.withLock { queues[key]?.requests ?? [] } }
    static func remove(_ key: String) { _ = lock.withLock { queues.removeValue(forKey: key) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            captured.httpBody = body
        }
        let reply: Reply? = Self.lock.withLock {
            let key = request.value(forHTTPHeaderField: "X-Problem-Test") ?? ""
            guard var queue = Self.queues[key] else { return nil }
            queue.requests.append(captured)
            let reply = queue.replies.isEmpty ? nil : queue.replies.removeFirst()
            Self.queues[key] = queue
            return reply
        }
        guard let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class ProblemTestSession {
    private let key = UUID().uuidString
    private let session: URLSession
    let client: LeetCodeAPIClient
    var requests: [URLRequest] { ProblemURLProtocol.requests(for: key) }

    init(_ replies: [ProblemURLProtocol.Reply] = []) {
        ProblemURLProtocol.register(replies, for: key)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProblemURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Problem-Test": key]
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
        client = LeetCodeAPIClient(session: session, cookies: { [] })
    }
    func close() { session.invalidateAndCancel(); ProblemURLProtocol.remove(key) }
}

@MainActor
@Suite("打开任意力扣题目")
struct OpenAnyProblemTests {
    @MainActor private struct Environment {
        let directory: URL
        let suite = "OpenAnyProblem-\(UUID())"
        let preferences: UserDefaults
        let store: LegacyDataStore
        let workspace: WorkspaceState

        init() throws {
            directory = FileManager.default.temporaryDirectory.appending(path: "OpenAnyProblem-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            preferences = UserDefaults(suiteName: suite)!
            store = LegacyDataStore(dataDirectory: directory)
            workspace = WorkspaceState(preferences: preferences)
            workspace.pendingLeetCodeSlug = "previous-problem"
            workspace.selectedSection = .conversation
        }
        func close() {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func hit(_ id: String = "704", slug: String = "binary-search", title: String = "二分查找", english: String = "Binary Search") -> [String: Any] {
        ["frontendQuestionId": id, "titleSlug": slug, "titleCn": title, "title": english, "paidOnly": false]
    }
    private func search(_ hits: [[String: Any]], more: Bool = false) throws -> ProblemURLProtocol.Reply {
        try .json(["data": ["problemsetQuestionList": ["questions": hits, "hasMore": more, "total": hits.count]]])
    }
    private func problem(_ id: String = "704", slug: String = "binary-search", content: String = "<p>二分查找题面</p>", translated: String? = nil, paid: Bool = false) throws -> ProblemURLProtocol.Reply {
        try .json(["data": ["question": [
            "questionId": "792", "questionFrontendId": id, "titleSlug": slug,
            "title": "Binary Search", "translatedTitle": "二分查找", "content": content,
            "translatedContent": translated ?? content, "isPaidOnly": paid, "difficulty": "Easy",
            "codeSnippets": [["langSlug": "python3", "lang": "Python3", "code": "official template"]],
            "enableRunCode": true, "enableSubmit": true, "exampleTestcases": "[1,2,3]\n2",
            "metaData": #"{"params":[{},{}]}"#
        ]]] )
    }
    private func variables(_ request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try #require(object["variables"] as? [String: Any])
    }

    @Test("Agent 成功加载后挂载来源会话，冲突可恢复；手动打开保留已有挂载")
    func agentMountsOnlyAfterLoading() async throws {
        let env = try Environment()
        let network = ProblemTestSession(try [problem()])
        defer { network.close(); env.close() }
        try JSONSerialization.data(withJSONObject: ["plans": ["route": ["questions": [[
            "titleSlug": "binary-search", "frontendId": "704", "title": "Binary Search", "translatedTitle": "二分查找"
        ]]]]]).write(to: env.directory.appending(path: "leetcode-cn.json"))
        let previous = try env.store.createConversation(title: "原有分析", firstMessage: .init(id: "old", role: "user", content: "保留原有上下文", createdAt: .now))
        let source = try env.store.createConversation(title: "来源会话")
        try env.store.mountConversation(previous, for: "binary-search")
        env.workspace.leetCodeWorkbench.conversationCollapsed = true
        let execute = ConversationWorkspaceView.agentToolExecutor(
            snapshot: AgentDataSnapshot.capture(from: env.store), dataStore: env.store,
            workspace: env.workspace, conversationID: source, leetCodeClient: network.client
        )
        let output = await execute("open_problem", #"{"query":"704"}"#)
        #expect(!output.contains("\"error\""))
        #expect(network.requests.count == 1)
        #expect(env.store.leetCodeWorkspaces["binary-search"] != nil)
        #expect(env.store.mountedConversation(for: "binary-search")?.id == source)
        #expect(!env.workspace.leetCodeWorkbench.conversationCollapsed)
        #expect(env.workspace.leetCodeWorkbenchNotice?.previousConversationID == previous)
        #expect(env.workspace.leetCodeWorkbenchNotice?.message.contains("完整保留") == true)
        #expect(env.store.conversations.first { $0.id == previous }?.messages.map(\.content) == ["保留原有上下文"])
        try env.store.mountConversation(previous, for: "binary-search")
        try await env.workspace.openLeetCodeProblem("704", dataStore: env.store, client: network.client)
        #expect(env.store.mountedConversation(for: "binary-search")?.id == previous)
        let reopened = LegacyDataStore(dataDirectory: env.directory)
        await reopened.hydrate()
        #expect(reopened.mountedConversation(for: "binary-search")?.id == previous)
        #expect(network.requests.count == 1)
    }

    @Test("来源题面失败不挂载不导航；来源删除后不复活会话")
    func failedLoadDoesNotMount() async throws {
        let env = try Environment()
        let failure = ProblemTestSession([.init(status: 503)])
        defer { failure.close(); env.close() }
        try JSONSerialization.data(withJSONObject: ["plans": ["route": ["questions": [[
            "titleSlug": "binary-search", "frontendId": "704"
        ]]]]]).write(to: env.directory.appending(path: "leetcode-cn.json"))
        let previous = try env.store.createConversation(title: "原会话")
        let source = try env.store.createConversation(title: "来源")
        try env.store.mountConversation(previous, for: "binary-search")
        do {
            try await env.workspace.openLeetCodeProblem("704", dataStore: env.store, client: failure.client, sourceConversationID: source)
            Issue.record("Failed statement must not mount")
        } catch { #expect(error.localizedDescription.contains("503")) }
        #expect(env.store.mountedConversation(for: "binary-search")?.id == previous)
        #expect(env.workspace.pendingLeetCodeSlug == "previous-problem")
        try env.store.deleteConversation(source)
        try await env.workspace.openLeetCodeProblem("704", dataStore: env.store, client: failure.client, sourceConversationID: source)
        #expect(env.store.mountedConversation(for: "binary-search")?.id == previous)
        #expect(env.workspace.leetCodeWorkbenchNotice?.message.contains("已删除") == true)
        #expect(!env.store.conversations.contains { $0.id == source })
        #expect(failure.requests.count == 1)
    }

    @Test("返回集合保留最后题目和草稿，重启恢复总览；主题与快捷集合沿用现有格式")
    func libraryAndAppearancePersistence() async throws {
        let env = try Environment()
        defer { env.close() }
        await env.store.hydrate()
        env.workspace.activateLeetCodeProblem("binary-search", dataStore: env.store)
        env.store.leetCodeDrafts.select(titleSlug: "binary-search", language: "java", snippet: nil)
        env.store.leetCodeDrafts.edit("private draft", for: env.store.leetCodeDrafts.key)
        env.workspace.leetCodeWorkbench.statementCollapsed = true
        env.workspace.leetCodeWorkbench.statementHeight = 310
        try env.workspace.showLeetCodeLibrary(dataStore: env.store)
        let restored = WorkspaceState(preferences: env.preferences)
        #expect(restored.leetCodeWorkbench.showsLibrary == true)
        #expect(restored.leetCodeWorkbench.selectedQuestionSlug == "binary-search")
        #expect(restored.leetCodeWorkbench.overviewSection == "library")
        #expect(restored.pendingLeetCodeSlug == nil)
        let drafts = LeetCodeDraftStore(dataDirectory: env.directory)
        drafts.select(titleSlug: "binary-search", language: "java", snippet: "late template")
        #expect(drafts.code == "private draft")
        restored.activateLeetCodeProblem("binary-search", dataStore: env.store)
        #expect(restored.leetCodeWorkbench.showsLibrary == false)
        #expect(restored.leetCodeWorkbench.statementCollapsed)
        #expect(restored.leetCodeWorkbench.statementHeight == 310)
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored.leetCodeWorkbench)) as? [String: Any])
        old.removeValue(forKey: "showsLibrary")
        old.removeValue(forKey: "overviewSection")
        let decoded = try JSONDecoder().decode(LeetCodeWorkbenchPreferences.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.selectedQuestionSlug == "binary-search")
        #expect(decoded.showsLibrary == nil)
        for appearance in ["dark", "light", "system"] {
            try env.store.saveAppearance(appearance, emphasizeMotion: false)
            let reopened = LegacyDataStore(dataDirectory: env.directory)
            await reopened.hydrate()
            #expect(reopened.settings.appearance == appearance)
            #expect(!reopened.settings.emphasizeMotion)
        }
        #expect(Set(LeetCodeStudyPlanInput.shortcuts.map(\.slug)) == ["top-100-liked", "leetcode-75", "top-interview-150", "programming-skills", "dynamic-programming", "graph-theory", "binary-search"])
        for shortcut in LeetCodeStudyPlanInput.shortcuts {
            #expect(try LeetCodeStudyPlanInput.slug(from: shortcut.slug) == shortcut.slug)
        }
        #expect(env.store.leetCodePlans.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: env.directory.appending(path: "leetcode-cn.json").path))
    }
    private func expectFailure(_ query: String, replies: [ProblemURLProtocol.Reply], containing text: String) async throws {
        let env = try Environment()
        let network = ProblemTestSession(replies)
        defer { network.close(); env.close() }
        do {
            try await env.workspace.openLeetCodeProblem(query, dataStore: env.store, client: network.client)
            Issue.record("Expected open to fail for \(query)")
        } catch {
            #expect(error.localizedDescription.contains(text))
        }
        #expect(env.workspace.pendingLeetCodeSlug == "previous-problem")
        #expect(env.workspace.selectedSection == .conversation)
        #expect(env.store.leetCodeWorkspaces.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: env.directory.appending(path: "leetcode-cn.json").path))
        #expect(!FileManager.default.fileExists(atPath: env.directory.appending(path: "leetcode-content.json").path))
        #expect(network.requests.count == replies.count)
    }

    @Test("远程按前端题号或完整中英文标题精确匹配，而非内部 ID 或相似题号", arguments: ["704", "二分查找", "Binary Search"])
    func exactRemoteMatch(_ query: String) async throws {
        let env = try Environment()
        let network = ProblemTestSession(try [search([hit("7040", slug: "wrong", title: "相似题", english: "Other"), hit()], more: true), problem()])
        defer { network.close(); env.close() }
        let reference = try await env.workspace.openLeetCodeProblem(query, dataStore: env.store, client: network.client)
        #expect(reference.frontendID == "704")
        #expect(reference.slug == "binary-search")
        #expect(env.workspace.pendingLeetCodeSlug == "binary-search")
        #expect(env.workspace.selectedSection == .leetCode)
        #expect(env.store.leetCodeWorkspaces["binary-search"] != nil)
        #expect(env.store.leetCodePlans.isEmpty)
        #expect(env.store.leetCodeQuestions.isEmpty)
        #expect(network.requests.count == 2)
        let filters = try #require(variables(network.requests[0])["filters"] as? [String: String])
        #expect(filters["searchKeywords"] == query)
        #expect(try variables(network.requests[1])["titleSlug"] as? String == "binary-search")
        #expect(network.requests.allSatisfy { $0.url?.absoluteString == "https://leetcode.cn/graphql/" && $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Cookie") == nil })
    }

    @Test("URL 与大小写混合 slug 直接取题面", arguments: ["binary-search", "https://leetcode.cn/problems/binary-search/", "https://www.leetcode.cn/problems/7rLGCR"])
    func directSlug(_ query: String) async throws {
        let slug = query.contains("7rLGCR") ? "7rLGCR" : "binary-search"
        let network = ProblemTestSession(try [problem(slug: slug)])
        defer { network.close() }
        let value = try await network.client.resolveWorkspace(LeetCodeProblemInput(query))
        #expect((value["question"] as? [String: Any])?["titleSlug"] as? String == slug)
        #expect(network.requests.count == 1)
        #expect(try variables(network.requests[0])["titleSlug"] as? String == slug)
    }

    @Test("单词标题可从 slug 查询回退；分页按精确题号匹配")
    func wordAndPagination() async throws {
        let word = ProblemTestSession(try [.json(["data": ["question": NSNull()]]), search([hit("9", slug: "palindrome-number", title: "回文数", english: "Palindrome")]), problem("9", slug: "palindrome-number")])
        defer { word.close() }
        _ = try await word.client.resolveWorkspace(LeetCodeProblemInput("Palindrome"))
        #expect(word.requests.count == 3)
        let pages = ProblemTestSession(try [search([hit("7040", slug: "wrong")], more: true), search([hit()]), problem()])
        defer { pages.close() }
        _ = try await pages.client.resolveWorkspace(LeetCodeProblemInput("704"))
        #expect(pages.requests.count == 3)
        #expect(try variables(pages.requests[1])["skip"] as? Int == 100)
        let partial = ProblemTestSession(try [search([hit()]), problem()])
        defer { partial.close() }
        _ = try await partial.client.resolveWorkspace(LeetCodeProblemInput("二分"))
        #expect(partial.requests.count == 2)
    }

    @Test("歧义、不存在和服务端错题均不缓存不导航")
    func noGuessing() async throws {
        try await expectFailure("206", replies: [search([hit("2060", slug: "other")])], containing: "没有找到")
        try await expectFailure("反转", replies: [search([
            hit("206", slug: "reverse-linked-list", title: "反转链表"), hit("92", slug: "reverse-linked-list-ii", title: "反转链表 II")
        ])], containing: "多道题")
        try await expectFailure("反转链表", replies: [search([
            hit("206", slug: "reverse-linked-list", title: "反转链表"), hit("LCR 024", slug: "UHnkqh", title: "反转链表")
        ])], containing: "多道题")
        try await expectFailure("https://leetcode.cn/problems/missing/", replies: [.json(["data": ["question": NSNull()]])], containing: "没有找到")
        try await expectFailure("704", replies: [search([hit()]), problem("7040")], containing: "题号")
        try await expectFailure("binary-search", replies: [problem(slug: "other")], containing: "题目标识")
    }

    @Test("严格拒绝不可信 URL、编码与路径注入", arguments: [
        "", "javascript:alert(1)", "http://leetcode.cn/problems/a/", "https://evil.test/problems/a/",
        "https://leetcode.cn.evil.test/problems/a/", "https://leetcode.cn@evil.test/problems/a/",
        "https://user@leetcode.cn/problems/a/", "https://leetcode.cn:443/problems/a/",
        "https://leetcode.cn/problems/a/?x=1", "https://leetcode.cn/problems/a/#x",
        "https://leetcode.cn/problems/%61/", "https://leetcode.cn/problems/a%2Fb/",
        "https://leetcode.cn/problems/a/../b/", "https://leetcode.cn/problems/a/description/",
        "https://leetcode.cn//problems/a/", "//leetcode.cn/problems/a/", "a/b", "a\\b", "a_b", "a--b", "-a", "a-", "a\nb",
        "a';alert(1)", String(repeating: "a", count: 301)
    ])
    func rejectsInput(_ input: String) {
        #expect(throws: (any Error).self) { try LeetCodeProblemInput(input) }
    }

    @Test("网络、权限和响应错误给出可理解提示")
    func failures() async throws {
        for (status, message) in [(401, "登录"), (403, "权限"), (429, "频繁"), (503, "503")] {
            try await expectFailure("704", replies: [.init(status: status)], containing: message)
        }
        try await expectFailure("704", replies: [.init(error: URLError(.notConnectedToInternet))], containing: "网络")
        try await expectFailure("704", replies: [.init(error: URLError(.timedOut))], containing: "超时")
        try await expectFailure("704", replies: [.init(body: Data("not json".utf8))], containing: "无效")
        try await expectFailure("704", replies: [.json(["errors": [["message": "需要账户权限"]]])], containing: "权限")
        try await expectFailure("binary-search", replies: [problem(content: "", paid: true)], containing: "付费")
    }

    @Test("搜索上限不猜题，取消不导航，缺少翻译时保留英文题面")
    func boundedSearchAndCancellation() async throws {
        try await expectFailure("二分", replies: Array(repeating: search([hit()], more: true), count: 5), containing: "范围过大")
        let env = try Environment()
        let cancelled = ProblemTestSession([.init(error: URLError(.cancelled))])
        defer { cancelled.close(); env.close() }
        do {
            try await env.workspace.openLeetCodeProblem("704", dataStore: env.store, client: cancelled.client)
            Issue.record("Cancelled open must not navigate")
        } catch is CancellationError {} catch { Issue.record(error) }
        #expect(env.workspace.pendingLeetCodeSlug == "previous-problem")
        #expect(env.store.leetCodeWorkspaces.isEmpty)
        let english = ProblemTestSession(try [problem(content: "<p>English statement</p>", translated: "")])
        defer { english.close() }
        let value = try await english.client.fetchWorkspace(titleSlug: "binary-search")
        #expect((value["question"] as? [String: Any])?["content"] as? String == "<p>English statement</p>")
    }

    @Test("远程临时题重启后本地命中，不写集合，切题保留草稿和挂载")
    func cacheDraftAndPlanIsolation() async throws {
        let env = try Environment()
        let network = ProblemTestSession(try [search([hit()]), problem()])
        defer { network.close(); env.close() }
        let planFile = env.directory.appending(path: "leetcode-cn.json")
        try JSONSerialization.data(withJSONObject: ["custom": "preserve", "activePlanSlug": "route", "plans": ["route": [
            "slug": "route", "name": "路线", "questions": [[
                "titleSlug": "two-sum", "questionFrontendId": "1", "title": "Two Sum", "translatedTitle": "两数之和"
            ]]
        ]], "submissions": []]).write(to: planFile)
        let originalPlan = try Data(contentsOf: planFile)
        let cacheFile = env.directory.appending(path: "leetcode-content.json")
        try Data(#"{"custom":"retain","workspaces":{}}"#.utf8).write(to: cacheFile)
        let drafts = env.store.leetCodeDrafts
        drafts.select(titleSlug: "two-sum", language: "python3", snippet: nil)
        drafts.edit("private previous code", for: drafts.key)
        env.workspace.leetCodeWorkbench.statementCollapsed = true
        env.workspace.leetCodeWorkbench.statementHeight = 320
        _ = try await env.workspace.openLeetCodeProblem("704", dataStore: env.store, client: network.client)
        let codeAfterOpen = LeetCodeDraftStore(dataDirectory: env.directory)
        codeAfterOpen.select(titleSlug: "two-sum", language: "python3", snippet: "late template")
        #expect(codeAfterOpen.code == "private previous code")
        drafts.select(titleSlug: "binary-search", language: "python3", snippet: "official template")
        drafts.edit("private binary search code", for: drafts.key)
        let conversation = try env.store.createConversation(title: "704. 二分查找")
        try env.store.mountConversation(conversation, for: "binary-search")
        _ = try await env.workspace.openLeetCodeProblem("1", dataStore: env.store, client: network.client)
        let reopened = LegacyDataStore(dataDirectory: env.directory)
        let state = WorkspaceState(preferences: env.preferences)
        for query in ["704", "二分查找", "Binary Search", "binary-search", "https://leetcode.cn/problems/binary-search/"] {
            _ = try await state.openLeetCodeProblem(query, dataStore: reopened, client: network.client)
            #expect(state.pendingLeetCodeSlug == "binary-search")
        }
        #expect(network.requests.count == 2)
        #expect(state.leetCodeWorkbench.statementCollapsed)
        #expect(state.leetCodeWorkbench.statementHeight == 320)
        #expect(reopened.mountedConversation(for: "binary-search")?.id == conversation)
        reopened.leetCodeDrafts.select(titleSlug: "binary-search", language: "python3", snippet: "replacement template")
        #expect(reopened.leetCodeDrafts.code == "private binary search code")
        #expect(reopened.leetCodeQuestions.map(\.titleSlug) == ["two-sum"])
        #expect(try Data(contentsOf: planFile) == originalPlan)
        let cached = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: cacheFile)) as? [String: Any])
        #expect(cached["custom"] as? String == "retain")
    }

    @Test("损坏缓存保留原字节；成功的 Agent 工具真实导航，失败不导航")
    func cacheSafetyAndAgent() async throws {
        let env = try Environment()
        defer { env.close() }
        let cacheFile = env.directory.appending(path: "leetcode-content.json")
        let corrupt = Data(#"{"workspaces":"broken"}"#.utf8)
        try corrupt.write(to: cacheFile)
        let badCacheNetwork = ProblemTestSession(try [problem()])
        defer { badCacheNetwork.close() }
        do {
            _ = try await env.workspace.openLeetCodeProblem("binary-search", dataStore: env.store, client: badCacheNetwork.client)
            Issue.record("Must preserve invalid cache")
        } catch { #expect(error.localizedDescription.contains("缓存")) }
        #expect(try Data(contentsOf: cacheFile) == corrupt)
        #expect(env.workspace.pendingLeetCodeSlug == "previous-problem")
        try FileManager.default.removeItem(at: cacheFile)
        let network = ProblemTestSession(try [search([hit()]), problem(), search([])])
        defer { network.close() }
        let execute = ConversationWorkspaceView.agentToolExecutor(
            snapshot: AgentDataSnapshot.capture(from: env.store), dataStore: env.store,
            workspace: env.workspace, conversationID: "test", leetCodeClient: network.client
        )
        let success = await execute("open_problem", #"{"query":"704"}"#)
        let payload = try #require(JSONSerialization.jsonObject(with: Data(success.utf8)) as? [String: Any])
        #expect(payload["error"] == nil)
        #expect(env.workspace.pendingLeetCodeSlug == "binary-search")
        #expect(env.workspace.selectedSection == .leetCode)
        let failure = await execute("open_problem", #"{"query":"206"}"#)
        #expect(failure.contains("没有找到"))
        #expect(env.workspace.pendingLeetCodeSlug == "binary-search")
        #expect(network.requests.count == 3)
        #expect(env.store.leetCodePlans.isEmpty)
    }
}
