import CryptoKit
import Foundation
import Observation

/// One editor session, owned by the data store so navigation cannot discard pending writes.
@MainActor @Observable
final class LeetCodeDraftStore {
    struct Key: Hashable {
        let titleSlug: String
        let language: String
    }

    private(set) var key: Key?
    private(set) var code = ""
    private(set) var errorMessage: String?
    private(set) var canEdit = false
    private var hasContent = false
    private var pending: [Key: String] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private let directory: URL

    init(dataDirectory: URL) {
        directory = dataDirectory.appending(path: "leetcode-drafts", directoryHint: .isDirectory)
    }

    func select(titleSlug: String?, language: String, snippet: String?) {
        let nextKey = titleSlug.map { Key(titleSlug: $0, language: language) }
        if key != nextKey || (!canEdit && nextKey != nil) {
            flush()
            if pending.isEmpty { errorMessage = nil }
            key = nextKey
            code = ""
            hasContent = false
            canEdit = nextKey != nil
            if let nextKey {
                do {
                    if let restored = try pending[nextKey] ?? read(nextKey) {
                        code = restored
                        hasContent = true
                    }
                } catch {
                    // A damaged/unreadable draft must never be replaced by an empty editor.
                    canEdit = false
                    errorMessage = "无法恢复代码草稿：\(error.localizedDescription)"
                }
            }
        }
        // A delayed workspace response may supply the first snippet, but never replace
        // restored code, an intentional empty draft, or an edit made while loading.
        if canEdit, !hasContent, let snippet {
            code = snippet
            hasContent = true
        }
    }

    func edit(_ value: String, for editedKey: Key?) {
        guard canEdit, let key, editedKey == key else { return }
        code = value
        hasContent = true
        pending[key] = value
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            self?.flush()
        }
    }

    /// Synchronous for question/language switches and willTerminate (an async task
    /// created at termination may never run). Failed writes stay in memory for retry.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard !pending.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (key, value) in pending {
                let url = fileURL(key)
                try Data(value.utf8).write(to: url, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                pending[key] = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = "代码草稿尚未保存：\(error.localizedDescription)"
        }
    }

    private func read(_ key: Key) throws -> String? {
        do {
            return try String(contentsOf: fileURL(key), encoding: .utf8)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    private func fileURL(_ key: Key) -> URL {
        let hash = SHA256.hash(data: Data("\(key.titleSlug)\u{0}\(key.language)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(hash).txt")
    }
}
