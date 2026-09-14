import Foundation
import SwiftUI
import Testing
import WebKit
@testable import LeetCodeAssistant

@MainActor
@Suite("工作台折叠与挂载会话")
struct WorkbenchInteractionTests {
    private func directory() throws -> URL {
        let result = FileManager.default.temporaryDirectory.appending(path: "WorkbenchInteraction-\(UUID())")
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    private var problem: LeetCodeConversationContext {
        LeetCodeConversationContext(frontendID: "206", title: "反转链表", titleSlug: "reverse-linked-list",
                                    statement: "给你单链表的头节点 head，请反转链表，并返回反转后的链表。", language: "python3")
    }

    @Test("折叠释放空间，切题和重建工作区保留选择与语言")
    func collapseAndSelectionPersist() throws {
        let suite = "WorkbenchInteraction-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let state = WorkspaceState(preferences: preferences)
        #expect(!state.leetCodeWorkbench.statementCollapsed)
        #expect(state.leetCodeWorkbench.isSolving)
        let size = CGSize(width: 1_200, height: 700)
        let expanded = LeetCodeWorkbenchLayout.panels(size: size, preferences: state.leetCodeWorkbench, hasConversation: false)
        state.leetCodeWorkbench.statementCollapsed = true
        state.leetCodeWorkbench.selectedQuestionSlug = problem.titleSlug
        state.leetCodeWorkbench.language = "python3"
        state.leetCodeWorkbench.selectedQuestionSlug = "two-sum"
        #expect(state.leetCodeWorkbench.statementCollapsed)
        let reopened = WorkspaceState(preferences: preferences)
        #expect(reopened.leetCodeWorkbench == state.leetCodeWorkbench)
        let collapsed = LeetCodeWorkbenchLayout.panels(size: size, preferences: reopened.leetCodeWorkbench, hasConversation: false)
        #expect(collapsed.statementSize == .zero)
        #expect(collapsed.editorSize.width == size.width)
        #expect(collapsed.editorSize.width > expanded.editorSize.width)
    }

    @Test("宽窗并排、窄高窗上下、窄矮窗切换显示，布局不越界")
    func adaptivePanels() {
        for size in [CGSize(width: 1_500, height: 800), CGSize(width: 820, height: 1_000), CGSize(width: 640, height: 440)] {
            var preferences = LeetCodeWorkbenchPreferences()
            let panels = LeetCodeWorkbenchLayout.panels(size: size, preferences: preferences, hasConversation: true)
            #expect(panels.conversationSize.width >= 340)
            #expect(panels.conversationSize.height >= 250)
            if panels.conversationBeside {
                #expect(panels.workSize.width + panels.conversationSize.width == size.width)
                #expect(panels.editorSize.width >= 380)
            } else {
                #expect(panels.workSize.height + panels.conversationSize.height == size.height)
                #expect(panels.conversationFocused == (size.height < 780))
            }
            preferences.conversationCollapsed = true
            let hidden = LeetCodeWorkbenchLayout.panels(size: size, preferences: preferences, hasConversation: true)
            #expect(hidden.workSize == size)
            #expect(!hidden.conversationFocused)
            preferences.statementCollapsed = true
            let codeOnly = LeetCodeWorkbenchLayout.panels(size: size, preferences: preferences, hasConversation: true)
            #expect(codeOnly.editorSize == size)
        }

        var preferences = LeetCodeWorkbenchPreferences()
        preferences.statementHeight = 320
        let resized = LeetCodeWorkbenchLayout.panels(
            size: CGSize(width: 700, height: 900), preferences: preferences, hasConversation: false
        )
        #expect(resized.statementSize.height == 320)
        #expect(resized.editorSize.height == 580)
        preferences.statementHeight = 900
        #expect(LeetCodeWorkbenchLayout.panels(
            size: CGSize(width: 700, height: 900), preferences: preferences, hasConversation: false
        ).editorSize.height == 220)
    }

    @Test("关联原子持久化、切换和解除不改变其他题目，复制与删除不留下挂载")
    func associationsSurviveAndInvalidate() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LegacyDataStore(dataDirectory: dir)
        let first = try store.createConversation(title: "206. 反转链表", leetCodeContext: problem)
        let second = try store.createConversation(title: "已有会话")
        #expect(store.mountedConversation(for: problem.titleSlug)?.id == first)
        try store.mountConversation(second, for: "two-sum")
        try store.mountConversation(second, for: problem.titleSlug)
        #expect(store.mountedConversation(for: problem.titleSlug)?.id == second)
        #expect(store.conversations.first { $0.id == first }?.mountedProblemSlugs.isEmpty == true)
        #expect(throws: (any Error).self) { try store.mountConversation("deleted", for: problem.titleSlug) }
        #expect(store.mountedConversation(for: problem.titleSlug)?.id == second)
        let duplicate = try store.duplicateConversation(second)
        #expect(store.conversations.first { $0.id == duplicate }?.mountedProblemSlugs.isEmpty == true)
        let reopened = LegacyDataStore(dataDirectory: dir)
        await reopened.hydrate()
        #expect(reopened.mountedConversation(for: "two-sum")?.id == second)
        #expect(reopened.mountedConversation(for: problem.titleSlug)?.id == second)
        try reopened.mountConversation(nil, for: problem.titleSlug)
        #expect(reopened.mountedConversation(for: problem.titleSlug) == nil)
        #expect(reopened.mountedConversation(for: "two-sum")?.id == second)
        try reopened.deleteConversation(second)
        #expect(reopened.mountedConversation(for: "two-sum") == nil)
        let afterDelete = LegacyDataStore(dataDirectory: dir)
        await afterDelete.hydrate()
        #expect(afterDelete.mountedConversation(for: "two-sum") == nil)
    }

    @Test("题目上下文走真实请求组装，元数据不成为消息或代码记忆")
    func problemContextIsRequestOnly() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "WorkbenchInteraction-\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let store = LegacyDataStore(dataDirectory: dir)
        store.leetCodeDrafts.select(titleSlug: problem.titleSlug, language: "python3", snippet: nil)
        store.leetCodeDrafts.edit("PRIVATE_UNSUBMITTED_CODE", for: store.leetCodeDrafts.key)
        store.leetCodeDrafts.flush()
        let id = try store.createConversation(title: "206. 反转链表", leetCodeContext: problem)
        try store.appendMessage(.init(id: "m_test", role: "user", content: "解释题意", createdAt: .now), to: id)
        #expect(store.conversations.first { $0.id == id }?.leetCodeContext == problem)
        #expect(store.conversations.first { $0.id == id }?.mountedProblemSlugs == [problem.titleSlug])
        let reopened = LegacyDataStore(dataDirectory: dir)
        await reopened.hydrate()
        let state = WorkspaceState(preferences: prefs)
        state.selectedConversationID = "main-conversation"
        let view = ConversationWorkspaceView(workspace: state, dataStore: reopened, mountedConversationID: id)
        let messages = view.requestHistory(
            conversationID: id, excluding: nil, memoryPrompts: [], continuityPrompt: nil,
            runtimeIdentity: .init(providerID: "test", providerName: "Test", model: "test")
        )
        let context = try #require(messages.first { $0.content.contains("【当前任务工作台题目】") })
        for field in [problem.frontendID, problem.title, problem.titleSlug, problem.statement, problem.language] {
            #expect(context.content.contains(field))
        }
        #expect(context.role == "system")
        #expect(!messages.contains { $0.content.contains("PRIVATE_UNSUBMITTED_CODE") })
        #expect(state.selectedConversationID == "main-conversation")
        #expect(reopened.conversations.first { $0.id == id }?.messages.map(\.content) == ["解释题意"])
        #expect(reopened.pendingLearningAnalysis(for: id)?.messages.map(\.content) == ["解释题意"])
        let file = try String(contentsOf: dir.appending(path: "conversations.json"), encoding: .utf8)
        #expect(!file.contains("PRIVATE_UNSUBMITTED_CODE"))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "memory-facts.json").path))
    }

    @Test("挂载、切题、重新加载与重启不丢代码草稿，聊天输入与附件不串会话")
    func draftsAreIndependent() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "WorkbenchInteraction-\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let state = WorkspaceState(preferences: prefs)
        let store = LegacyDataStore(dataDirectory: dir)
        let id = try store.createConversation(title: "206", leetCodeContext: problem)
        state.leetCodeWorkbench.selectedQuestionSlug = problem.titleSlug
        state.leetCodeWorkbench.language = "python3"
        store.leetCodeDrafts.select(titleSlug: problem.titleSlug, language: "python3", snippet: "official")
        store.leetCodeDrafts.edit("my code", for: store.leetCodeDrafts.key)
        state.leetCodeWorkbench.statementCollapsed = true
        state.leetCodeWorkbench.conversationCollapsed = true
        store.reload()
        #expect(store.leetCodeDrafts.code == "my code")
        store.leetCodeDrafts.select(titleSlug: "two-sum", language: "java", snippet: "other official")
        store.leetCodeDrafts.edit("other code", for: store.leetCodeDrafts.key)
        store.leetCodeDrafts.flush()
        let reopenedState = WorkspaceState(preferences: prefs)
        let reopenedStore = LegacyDataStore(dataDirectory: dir)
        await reopenedStore.hydrate()
        reopenedStore.leetCodeDrafts.select(titleSlug: reopenedState.leetCodeWorkbench.selectedQuestionSlug,
                                           language: reopenedState.leetCodeWorkbench.language, snippet: "late official")
        #expect(reopenedStore.leetCodeDrafts.code == "my code")
        #expect(reopenedStore.mountedConversation(for: problem.titleSlug)?.id == id)
        state.setConversationDraft("first input", for: id)
        state.setConversationDraft("second input", for: "other")
        let image = ConversationArtifact(type: "image", url: "data:image/png;base64,AA==", title: "test")
        state.setConversationArtifacts([image], for: id)
        #expect(state.conversationDraft(for: id) == "first input")
        #expect(state.conversationDraft(for: "other") == "second input")
        #expect(state.conversationArtifacts(for: "other").isEmpty)
        #expect(state.conversationArtifacts(for: id) == [image])
    }

    @Test("工作台发送携带最新未提交代码快照，仅进请求；普通会话、错题错语言不误注入")
    func liveEditorSnapshotIsRequestOnly() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "WorkbenchInteraction-\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let state = WorkspaceState(preferences: prefs)
        state.leetCodeWorkbench.selectedQuestionSlug = problem.titleSlug
        state.leetCodeWorkbench.language = problem.language
        let store = LegacyDataStore(dataDirectory: dir)
        let id = try store.createConversation(title: "代码讨论", leetCodeContext: problem)
        try store.appendMessage(.init(id: "user", role: "user", content: "检查当前代码", createdAt: .now), to: id)
        let file = dir.appending(path: "conversations.json")
        let before = try Data(contentsOf: file)
        let drafts = store.leetCodeDrafts
        drafts.select(titleSlug: problem.titleSlug, language: problem.language, snippet: nil)
        drafts.edit("FIRST_PRIVATE_DRAFT", for: drafts.key)
        let mounted = ConversationWorkspaceView(workspace: state, dataStore: store, mountedConversationID: id, problemContext: problem)
        let identity = ConversationRuntimeIdentity(providerID: "test", providerName: "Test", model: "test")
        let snapshot = try #require(mounted.requestProblemContext(conversationID: id))
        drafts.edit("UPDATED_PRIVATE_DRAFT", for: drafts.key)
        let frozen = mounted.requestHistory(conversationID: id, excluding: nil, memoryPrompts: [], continuityPrompt: nil, runtimeIdentity: identity, taskContextSnapshot: snapshot)
        #expect(frozen.contains { $0.role == "system" && $0.content.contains("FIRST_PRIVATE_DRAFT") })
        #expect(!frozen.contains { $0.content.contains("UPDATED_PRIVATE_DRAFT") })
        let fresh = mounted.requestHistory(conversationID: id, excluding: nil, memoryPrompts: [], continuityPrompt: nil, runtimeIdentity: identity)
        let context = try #require(fresh.first { $0.role == "system" && $0.content.contains("UPDATED_PRIVATE_DRAFT") })
        for field in [problem.frontendID, problem.title, problem.titleSlug, problem.language, problem.statement] {
            #expect(context.content.contains(field))
        }
        #expect(!fresh.contains { $0.content.contains("FIRST_PRIVATE_DRAFT") })
        #expect(fresh.filter { $0.role == "user" }.map(\.content) == ["检查当前代码"])
        state.selectedConversationID = id
        let ordinary = ConversationWorkspaceView(workspace: state, dataStore: store)
        #expect(!(ordinary.requestProblemContext(conversationID: id) ?? "").contains("UPDATED_PRIVATE_DRAFT"))
        #expect(try Data(contentsOf: file) == before)
        let unrelated = try store.createConversation(title: "普通会话")
        #expect(ordinary.requestProblemContext(conversationID: unrelated) == nil)
        try store.deleteConversation(unrelated)
        #expect(store.conversations.first { $0.id == id }?.messages.map(\.content) == ["检查当前代码"])
        #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("PRIVATE_DRAFT"))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "memory-facts.json").path))
        drafts.edit(String(repeating: "x", count: 50_000) + "PRIVATE_TAIL", for: drafts.key)
        let limited = try #require(mounted.requestProblemContext(conversationID: id))
        #expect(limited.contains("草稿已截断"))
        #expect(!limited.contains("PRIVATE_TAIL"))
        drafts.select(titleSlug: "two-sum", language: problem.language, snippet: "WRONG_PROBLEM_CODE")
        #expect(!(mounted.requestProblemContext(conversationID: id) ?? "").contains("WRONG_PROBLEM_CODE"))
        drafts.select(titleSlug: problem.titleSlug, language: "java", snippet: "WRONG_LANGUAGE_CODE")
        #expect(!(mounted.requestProblemContext(conversationID: id) ?? "").contains("WRONG_LANGUAGE_CODE"))
    }

    @Test("收起不停止流式生成，删除后取消任务并清理输入和队列")
    func generationLifetimeFollowsConversation() {
        let suite = "WorkbenchInteraction-\(UUID())"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let state = WorkspaceState(preferences: prefs)
        state.conversationGeneration = .init(conversationID: "c1", messageID: "m1", content: "partial", phase: .generating)
        let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        state.conversationGenerationTask = task
        state.leetCodeWorkbench.conversationCollapsed = true
        state.leetCodeWorkbench.statementCollapsed = true
        #expect(state.conversationGeneration?.phase == .generating)
        #expect(!task.isCancelled)
        state.setConversationDraft("pending", for: "c1")
        state.queuedConversationID = "c1"
        state.queuedConversationDrafts = [.init(text: "queued", artifacts: [])]
        state.reconcileConversations([])
        #expect(task.isCancelled)
        #expect(state.conversationGeneration == nil)
        #expect(state.queuedConversationDrafts.isEmpty)
        #expect(state.conversationDraft(for: "c1").isEmpty)
    }

    @Test("损坏的会话文件不能被新建或挂载覆盖")
    func corruptConversationFileIsPreserved() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "conversations.json")
        let damaged = Data("{damaged".utf8)
        try damaged.write(to: url)
        let store = LegacyDataStore(dataDirectory: dir)
        #expect(throws: (any Error).self) { try store.createConversation(title: "206", leetCodeContext: problem) }
        #expect(throws: (any Error).self) { try store.mountConversation("c1", for: problem.titleSlug) }
        #expect(try Data(contentsOf: url) == damaged)
    }

    @Test("同修订号切换会话仍重绘，聊天为展开输入框留出实际空间")
    func webRendererUsesConversationIdentity() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 500), configuration: configuration)
        let coordinator = RichConversationWebView.Coordinator()
        coordinator.webView = webView
        webView.navigationDelegate = coordinator
        coordinator.conversationID = "first"
        coordinator.conversationRevision = ConversationRevision(updatedAtMilliseconds: 42, messageCount: 1)
        coordinator.messages = [.init(id: "m1", role: "user", content: "FIRST_CONVERSATION", createdAt: .now)]
        coordinator.contentBottomInset = 210
        coordinator.loadTemplate()
        defer { webView.stopLoading(); webView.navigationDelegate = nil }
        try await waitForText("FIRST_CONVERSATION", in: webView)
        coordinator.conversationID = "second"
        coordinator.messages = [.init(id: "m2", role: "user", content: "SECOND_CONVERSATION", createdAt: .now)]
        coordinator.renderIfNeeded()
        try await waitForText("SECOND_CONVERSATION", in: webView)
        let text = try await webView.evaluateJavaScript("document.body.innerText") as? String ?? ""
        #expect(!text.contains("FIRST_CONVERSATION"))
        let inset = try await webView.evaluateJavaScript("getComputedStyle(document.documentElement).getPropertyValue('--conversation-bottom-inset').trim()") as? String
        #expect(inset == "210px")
    }

    private func waitForText(_ text: String, in webView: WKWebView) async throws {
        for _ in 0..<100 {
            if let rendered = try? await webView.evaluateJavaScript("document.body.innerText") as? String,
               rendered.contains(text) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Web conversation never rendered \(text)")
    }

    @Test("真实编辑器：等价候选 Enter 换行，其他候选与 Tab 接受，方向键和 IME 保持原行为")
    func completionEnterAndTheme() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let drafts = LeetCodeDraftStore(dataDirectory: dir)
        drafts.select(titleSlug: "reverse-linked-list", language: "java", snippet: nil)
        let editor: (ColorScheme) -> AnyView = { scheme in
            AnyView(LeetCodeCodeEditor(
                code: Binding(get: { drafts.code }, set: { drafts.edit($0, for: drafts.key) }),
                language: "java", diagnostics: .constant(.init()), loadStatus: .constant(.loading),
                completionStatus: .constant(.localOnly), formatRequest: 0, undoRequest: 0, redoRequest: 0
            ).environment(\.colorScheme, scheme))
        }
        let host = NSHostingView(rootView: editor(.light))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 500), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close(); drafts.flush() }
        host.layoutSubtreeIfNeeded()
        let webView = try #require(descendantWebViews(host).first)
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript("!!window.editorBridge")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let results = try await webView.evaluateJavaScript(#"""
        (() => {
          const cm = document.querySelector('.CodeMirror').CodeMirror;
          const setup = (prefix = 'head') => {
            cm.closeHint();
            window.editorBridge.setValue('class Solution {\n    ListNode head;\n    ListNode header;\n    ' + prefix, 'java');
            cm.setCursor(3, 4 + prefix.length);
            cm.getOption('extraKeys')['Cmd-Space'](cm);
            if (!cm.state.completionActive?.widget) throw Error('Completion menu not opened');
          };
          const key = (code, composing = false) => {
            const event = new KeyboardEvent('keydown', {keyCode: code, which: code, bubbles: true, cancelable: true, isComposing: composing});
            cm.triggerOnKeyDown(event);
            return event;
          };
          setup(); key(13);
          const identical = cm.lineCount() === 5 && cm.getLine(3).trim() === 'head' && cm.getLine(4).trim() === '';
          setup('hea'); key(40); key(13);
          const different = cm.lineCount() === 4 && cm.getLine(3).trim() === 'header';
          setup('hea'); key(40); key(38); key(13);
          const arrows = cm.lineCount() === 4 && cm.getLine(3).trim() === 'head';
          setup(); key(9);
          const tabIdentical = cm.lineCount() === 4 && cm.getLine(3).trim() === 'head';
          setup('hea'); key(40); key(9);
          const tabDifferent = cm.lineCount() === 4 && cm.getLine(3).trim() === 'header';
          setup(); const before = cm.getValue(); const ime = key(13, true);
          const composing = cm.getValue() === before && !ime.defaultPrevented;
          cm.closeHint(); key(13);
          const plainEnter = cm.lineCount() === 5;
          window.__themeMarker = 'keep-editor';
          return {identical, different, arrows, tabIdentical, tabDifferent, composing, plainEnter};
        })()
        """#) as? [String: Bool]
        let checks = try #require(results)
        #expect(checks.count == 7)
        for (name, passed) in checks { #expect(passed, "Editor keyboard check: \(name)") }
        let codeBeforeTheme = try await webView.evaluateJavaScript("document.querySelector('.CodeMirror').CodeMirror.getValue()") as? String
        // Read the final asynchronous editorChanged before updating the SwiftUI root.
        for _ in 0..<40 {
            if drafts.code == codeBeforeTheme { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        for scheme in [ColorScheme.dark, .light] {
            host.rootView = editor(scheme)
            host.layoutSubtreeIfNeeded()
            for _ in 0..<60 {
                let dark = (try? await webView.evaluateJavaScript("matchMedia('(prefers-color-scheme: dark)').matches")) as? Bool
                if dark == (scheme == .dark) { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            #expect(try await webView.evaluateJavaScript("matchMedia('(prefers-color-scheme: dark)').matches") as? Bool == (scheme == .dark))
            #expect(try await webView.evaluateJavaScript("window.__themeMarker") as? String == "keep-editor")
            #expect(try await webView.evaluateJavaScript("document.querySelector('.CodeMirror').CodeMirror.getValue()") as? String == codeBeforeTheme)
            let keyword = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('.cm-keyword')).color") as? String
            #expect(keyword == (scheme == .dark ? "rgb(198, 120, 221)" : "rgb(166, 38, 164)"))
        }
    }

    @Test("隔离数据的工作台布局截图", .enabled(if: ProcessInfo.processInfo.environment["LEETCODE_WORKBENCH_QA_DIR"] != nil))
    func workbenchLayoutSnapshots() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = URL(filePath: try #require(ProcessInfo.processInfo.environment["LEETCODE_WORKBENCH_QA_DIR"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let content: [String: Any] = ["workspaces": [problem.titleSlug: ["value": [
            "question": ["questionId": "206", "frontendId": "206", "titleSlug": problem.titleSlug,
                         "title": "Reverse Linked List", "translatedTitle": problem.title, "difficulty": "EASY",
                         "content": "<h2>反转链表</h2><p>\(problem.statement)</p><h3>示例</h3><pre>输入：[1,2,3,4,5]\n输出：[5,4,3,2,1]</pre>",
                         "exampleTestcases": ["[1,2,3,4,5]"], "enableRunCode": false, "enableSubmit": false],
            "snippets": [["lang": "Python3", "langSlug": "python3", "code": "class Solution:\n    def reverseList(self, head):\n        previous = None\n        while head:\n            following = head.next\n            head.next = previous\n            previous = head\n            head = following\n        return previous"]]
        ]]]]
        try JSONSerialization.data(withJSONObject: content).write(to: dir.appending(path: "leetcode-content.json"))
        let store = LegacyDataStore(dataDirectory: dir)
        let conversationID = try store.createConversation(title: "206 · 反转链表的指针顺序", leetCodeContext: problem)
        try store.appendMessage(.init(id: "qa-user", role: "user", content: "为什么要先保存下一个节点？", createdAt: .now), to: conversationID)
        try store.appendMessage(.init(id: "qa-agent", role: "assistant", content: "修改 `head.next` 后，原来的后继节点就无法通过它找到。先保存 `following`，才能在反转指针后继续遍历。\n\n可以手动走一遍 `1 → 2 → 3`，检查每一步还保留着哪些指针。", createdAt: .now), to: conversationID)
        let suite = "WorkbenchInteraction-\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let state = WorkspaceState(preferences: prefs)
        state.leetCodeWorkbench.selectedQuestionSlug = problem.titleSlug
        state.leetCodeWorkbench.language = "python3"
        let host = NSHostingView(rootView: LeetCodeWorkspaceView(workspace: state, dataStore: store))
        let window = NSWindow(contentRect: CGRect(x: 60, y: 60, width: 1_450, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Workbench isolated layout check"
        window.contentView = host
        // WebKit pauses CSS animations in fully occluded windows; show only this
        // isolated test window while capturing, without activating/terminating the app.
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        for _ in 0..<100 {
            if let chat = descendantWebViews(host).first(where: { $0.url?.lastPathComponent == "conversation.html" }) {
                try await waitForText("为什么要先保存下一个节点", in: chat)
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        for (name, size, statementCollapsed, chatCollapsed) in [
            ("wide", CGSize(width: 1_450, height: 800), false, false),
            ("wide-code", CGSize(width: 1_450, height: 800), true, false),
            ("stacked-with-chat", CGSize(width: 1_100, height: 800), false, false),
            ("narrow-chat", CGSize(width: 640, height: 510), false, false),
            ("narrow-code", CGSize(width: 640, height: 510), true, true),
            ("tall", CGSize(width: 820, height: 1_000), false, false)
        ] {
            state.leetCodeWorkbench.statementCollapsed = statementCollapsed
            state.leetCodeWorkbench.conversationCollapsed = chatCollapsed
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(650))
            if !chatCollapsed, let chat = descendantWebViews(host).first(where: { $0.url?.lastPathComponent == "conversation.html" }) {
                let opacity = try await chat.evaluateJavaScript("getComputedStyle(document.querySelector('.message')).opacity") as? String
                #expect((Double(opacity ?? "0") ?? 0) > 0.9)
            }
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appending(path: "\(name).png"))
        }
    }

    private func descendantWebViews(_ view: NSView) -> [WKWebView] {
        (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(descendantWebViews)
    }
}
