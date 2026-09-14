import Foundation
import Testing
@testable import LeetCodeAssistant

@MainActor
@Suite("任务工作台草稿、动作与集合")
struct WorkspaceTaskTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "WorkspaceTaskTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("草稿保存恢复、空草稿、题目与语言隔离、官方模板回退和延迟响应防覆盖")
    func draftsSurviveSwitchesAndRestore() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = LeetCodeDraftStore(dataDirectory: directory)
        drafts.select(titleSlug: "reverse-linked-list", language: "java", snippet: nil)
        drafts.edit("my Java solution", for: drafts.key)
        let oldKey = drafts.key
        drafts.select(titleSlug: "reverse-linked-list", language: "java", snippet: "official Java")
        #expect(drafts.code == "my Java solution")
        drafts.select(titleSlug: "reverse-linked-list", language: "python3", snippet: "official Python")
        #expect(drafts.code == "official Python")
        drafts.edit("late Java callback", for: oldKey)
        #expect(drafts.code == "official Python")
        drafts.edit("", for: drafts.key)
        drafts.select(titleSlug: "two-sum", language: "java", snippet: "official Two Sum")
        #expect(drafts.code == "official Two Sum")
        drafts.edit("different problem", for: drafts.key)
        drafts.flush()
        #expect(drafts.errorMessage == nil)

        let reopened = LeetCodeDraftStore(dataDirectory: directory)
        reopened.select(titleSlug: "reverse-linked-list", language: "java", snippet: "new official Java")
        #expect(reopened.code == "my Java solution")
        reopened.select(titleSlug: "reverse-linked-list", language: "java", snippet: "late official Java")
        #expect(reopened.code == "my Java solution")
        reopened.select(titleSlug: "reverse-linked-list", language: "python3", snippet: "official Python")
        #expect(reopened.code.isEmpty)
        reopened.select(titleSlug: "two-sum", language: "java", snippet: nil)
        #expect(reopened.code == "different problem")
        reopened.select(titleSlug: "two-sum", language: "cpp", snippet: nil)
        reopened.select(titleSlug: "two-sum", language: "cpp", snippet: "late official C++")
        #expect(reopened.code == "late official C++")
    }

    @Test("防抖写入可被新实例恢复，无需正常关闭")
    func debouncePersistsWithoutFlush() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = LeetCodeDraftStore(dataDirectory: directory)
        drafts.select(titleSlug: "two-sum", language: "java", snippet: "official")
        drafts.edit("first", for: drafts.key)
        drafts.edit("latest", for: drafts.key)
        var restored = ""
        for _ in 0..<20 where restored != "latest" {
            try await Task.sleep(for: .milliseconds(100))
            let reopened = LeetCodeDraftStore(dataDirectory: directory)
            reopened.select(titleSlug: "two-sum", language: "java", snippet: "official")
            restored = reopened.code
        }
        #expect(restored == "latest")
    }

    @Test("保存失败保留内存草稿，损坏文件不会被模板或编辑覆盖")
    func draftIOFailuresDoNotLoseCode() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let draftDirectory = directory.appending(path: "leetcode-drafts")
        try Data("blocked directory".utf8).write(to: draftDirectory)
        let drafts = LeetCodeDraftStore(dataDirectory: directory)
        // Load a new key before inducing a write error, not an unreadable existing file.
        try FileManager.default.removeItem(at: draftDirectory)
        drafts.select(titleSlug: "two-sum", language: "java", snippet: "official")
        try Data("blocked directory".utf8).write(to: draftDirectory)
        drafts.edit("keep this", for: drafts.key)
        drafts.flush()
        #expect(drafts.errorMessage != nil)
        #expect(drafts.code == "keep this")
        try FileManager.default.removeItem(at: draftDirectory)
        drafts.flush()
        #expect(drafts.errorMessage == nil)
        let url = try #require(FileManager.default.contentsOfDirectory(at: draftDirectory, includingPropertiesForKeys: nil).first)
        let corrupt = Data([0xFF, 0xFE, 0xFF])
        try corrupt.write(to: url, options: .atomic)
        let reopened = LeetCodeDraftStore(dataDirectory: directory)
        reopened.select(titleSlug: "two-sum", language: "java", snippet: "official")
        #expect(!reopened.canEdit)
        #expect(reopened.errorMessage != nil)
        reopened.edit("do not overwrite", for: reopened.key)
        reopened.flush()
        #expect(try Data(contentsOf: url) == corrupt)
        try Data("repaired draft".utf8).write(to: url, options: .atomic)
        reopened.select(titleSlug: "two-sum", language: "java", snippet: "official")
        #expect(reopened.canEdit)
        #expect(reopened.errorMessage == nil)
        #expect(reopened.code == "repaired draft")
    }

    @Test("严格解析题单 URL 或 slug", arguments: [
        "top-100-liked", " interview-crash-course-data-structures-and-algorithms \n",
        "https://leetcode.cn/studyplan/top-100-liked/", "https://www.leetcode.cn/studyplan/top-100-liked"
    ])
    func acceptsPlanInput(_ input: String) throws {
        #expect(!(try LeetCodeStudyPlanInput.slug(from: input)).isEmpty)
        if input.contains("top-100-liked") {
            #expect(try LeetCodeStudyPlanInput.slug(from: input) == "top-100-liked")
        }
    }

    @Test("拒绝非力扣站点、脚本、路径与编码注入", arguments: [
        "", "javascript:alert(1)", "https://evil.test/studyplan/top-100-liked/",
        "https://leetcode.cn.evil.test/studyplan/top-100-liked/",
        "https://leetcode.cn@evil.test/studyplan/top-100-liked/",
        "http://leetcode.cn/studyplan/top-100-liked/", "https://leetcode.cn:443/studyplan/a/",
        "https://leetcode.cn/studyplan/a/?next=javascript:alert(1)",
        "https://leetcode.cn/studyplan/a/#script", "https://leetcode.cn/studyplan/%61/",
        "https://leetcode.cn/studyplan/a/../b/", "https://leetcode.cn//studyplan/a/",
        "https://leetcode.cn/problems/two-sum/", "a/b", "a_b", "a--b", "-a", "a-",
        "a\nb", "a';alert(1)//", String(repeating: "a", count: 101)
    ])
    func rejectsPlanInput(_ input: String) {
        #expect(throws: (any Error).self) { try LeetCodeStudyPlanInput.slug(from: input) }
    }

    private var account: [String: Any] { ["isSignedIn": true, "username": "test-user"] }

    private func plan(_ slug: String, questionSlug: String, number: String, title: String, english: String) -> [String: Any] {
        ["slug": slug, "name": slug, "planSubGroups": [["name": "测试组", "questions": [[
            "titleSlug": questionSlug, "questionFrontendId": number,
            "translatedTitle": title, "title": english, "difficulty": "EASY", "paidOnly": false
        ]]]]]
    }

    @Test("导入保留旧集合、提交与额外字段，重开后自动选中新集合，Agent 可打开非当前集合的 206")
    func importingAndOpeningAcrossCollections() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "leetcode-cn.json")
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 7, "custom": "preserve"])
            .write(to: file, options: .atomic)
        let store = LegacyDataStore(dataDirectory: directory)
        let first = plan("first-plan", questionSlug: "reverse-linked-list", number: "206", title: "反转链表", english: "Reverse Linked List")
        let second = plan("second-plan", questionSlug: "two-sum", number: "1", title: "两数之和", english: "Two Sum")
        let validated = try LeetCodeAPIClient.studyPlanSnapshot(from: ["userStatus": account, "studyPlanV2Detail": first], slug: "first-plan")
        try store.applyLeetCodeWebSync(account: validated.account, submissions: [[
            "id": "test-submission", "title": "Reverse Linked List", "statusDisplay": "Accepted",
            "timestamp": 1_800_000_000, "lang": "java"
        ]], studyPlan: validated.studyPlan)
        let oldRoot = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        try store.applyLeetCodeWebSync(account: account, submissions: [], studyPlan: second)
        let newRoot = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let oldPlans = try #require(oldRoot["plans"] as? NSDictionary)
        let newPlans = try #require(newRoot["plans"] as? NSDictionary)
        #expect((oldPlans["first-plan"] as? NSDictionary) == (newPlans["first-plan"] as? NSDictionary))
        #expect(newRoot["schemaVersion"] as? Int == 7)
        #expect(newRoot["custom"] as? String == "preserve")
        #expect(store.leetCodeSubmissions.map(\.id) == ["test-submission"])
        let reopened = LegacyDataStore(dataDirectory: directory)
        await reopened.hydrate()
        #expect(Set(reopened.leetCodePlans.map(\.id)) == ["first-plan", "second-plan"])
        #expect(reopened.activeLeetCodePlanID == "second-plan")
        #expect(reopened.leetCodeQuestions.map(\.titleSlug) == ["two-sum"])
        let snapshot = AgentDataSnapshot.capture(from: reopened)
        let suite = "WorkspaceTaskTests-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceState(preferences: preferences)
        let network = ProblemTestSession(try [.json(["data": ["problemsetQuestionList": ["questions": [], "hasMore": false]]])])
        defer { network.close() }
        let execute = ConversationWorkspaceView.agentToolExecutor(
            snapshot: snapshot, dataStore: reopened, workspace: workspace, conversationID: "test", leetCodeClient: network.client
        )
        for query in ["206", "反转链表", "Reverse Linked List", "reverse-linked-list"] {
            workspace.pendingLeetCodeSlug = nil
            workspace.selectedSection = .conversation
            let arguments = String(decoding: try JSONSerialization.data(withJSONObject: ["query": query]), as: UTF8.self)
            let result = await execute("open_problem", arguments)
            let payload = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
            #expect(payload["error"] == nil)
            #expect(workspace.pendingLeetCodeSlug == "reverse-linked-list")
            #expect(workspace.selectedSection == .leetCode)
        }
        workspace.pendingLeetCodeSlug = nil
        workspace.selectedSection = .conversation
        let result = await execute("open_problem", #"{"query":"2060"}"#)
        let failure = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        #expect(failure["error"] != nil)
        #expect(workspace.pendingLeetCodeSlug == nil)
        #expect(workspace.selectedSection == .conversation)
        #expect(network.requests.count == 1)
    }

    @Test("歧义、未知及空题目不执行导航")
    func ambiguousProblemsNeverNavigate() async throws {
        let snapshot: AgentDataSnapshot = {
            var value = AgentDataSnapshot()
            value.questionIndex = [
                .init(slug: "reverse-linked-list", title: "反转链表", frontendID: "206", englishTitle: "Reverse Linked List"),
                .init(slug: "reverse-linked-list-ii", title: "反转链表 II", frontendID: "92", englishTitle: "Reverse Linked List II"),
                .init(slug: "", title: "无标识题")
            ]
            return value
        }()
        for query in ["反转", "no-such-problem", "", "20", "无标识题"] {
            let args = String(decoding: try JSONSerialization.data(withJSONObject: ["query": query]), as: UTF8.self)
            let result = await LearningAgentTools.run(
                name: "open_problem", arguments: args, snapshot: snapshot,
                memorySearch: { _ in [] }, solutionSearch: { _ in [] },
                solutionRead: { _ in nil }, videoSearch: { _ in [] },
                openProblem: { query in
                    let match = try snapshot.resolveProblem(query)
                    Issue.record("Must not navigate for an unresolved query")
                    return match
                }
            )
            let payload = try #require(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])
            #expect(payload["error"] != nil)
        }
        #expect(snapshot.resolveSlug("206") == "reverse-linked-list")
    }

    @Test("未登录、查不到、返回错集合与权限受限均拒绝导入")
    func invalidPlanResponses() {
        for data: [String: Any] in [
            ["userStatus": ["isSignedIn": false]],
            ["userStatus": account],
            ["userStatus": account, "studyPlanV2Detail": ["slug": "wrong"]],
            ["userStatus": account, "studyPlanV2Detail": ["slug": "test", "planSubGroups": []]]
        ] {
            #expect(throws: (any Error).self) { try LeetCodeAPIClient.studyPlanSnapshot(from: data, slug: "test") }
        }
    }

    @Test("损坏的现有集合文件不会被导入覆盖")
    func importDoesNotOverwriteUnreadableData() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "leetcode-cn.json")
        let store = LegacyDataStore(dataDirectory: directory)
        for corrupt in [Data("{broken".utf8), Data(#"{"plans":"broken"}"#.utf8)] {
            try corrupt.write(to: file, options: .atomic)
            #expect(throws: (any Error).self) {
                try store.applyLeetCodeWebSync(account: account, submissions: [], studyPlan: plan(
                    "new-plan", questionSlug: "two-sum", number: "1", title: "两数之和", english: "Two Sum"
                ))
            }
            #expect(try Data(contentsOf: file) == corrupt)
        }
    }
}
