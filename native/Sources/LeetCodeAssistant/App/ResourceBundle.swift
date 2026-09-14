import Foundation

extension Bundle {
    /// SwiftPM 生成的 `Bundle.module` 只找两个地方：可执行文件同级目录（打成 .app 之后是
    /// `Xxx.app/` 根目录）和构建时的绝对 scratch 路径。资源包按签名要求必须放在
    /// `Contents/Resources`（放根目录 codesign 会报 unsealed contents），而 scratch 路径在
    /// $TMPDIR 下会被系统清掉——两条路都断了就是 fatalError，表现为一开会话窗口就闪退。
    /// 这里统一走 `Bundle.main.resourceURL`，.app 和 `swift run` 两种形态都能命中。
    static let appResources: Bundle = {
        let bundleName = "LeetCodeAssistant_LeetCodeAssistant.bundle"
        if let url = Bundle.main.resourceURL,
           let bundle = Bundle(url: url.appendingPathComponent(bundleName)) {
            return bundle
        }
        return .module
    }()
}
