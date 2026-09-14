# LeetCode AI 刷题生态调研：内部研究底稿

- 日期：2026-09-07
- 受众：希望建立长期个人 LeetCode 学习系统的开发者
- 决策：选择一个日常主工具，并确定跨平台备选及可选归档层
- 当前环境：macOS 15.7.7、Apple Silicon（arm64）
- 范围：开源桌面端、浏览器插件、IDE/TUI + Agent、LeetCode 官方闭源基线

## 直接结论

在当前机器和 `leetcode.cn` 使用场景下，选择 **LeetLens v2.2.0** 作为唯一学习主系统。它是已核验候选中唯一同时实现题目/提交闭环、用户证据驱动的学习档案、知识图谱、FSRS 调度、分级防剧透提示和复习评分回写的产品。

如果必须使用 `leetcode.com`、Windows/Linux，或必须在 IDE 内保留普通源码文件，选择 **NikkyAmresh/lcex（Marketplace 名 LeetCode Practice）+ IDE Agent**。它的 UI、工程状态和 Agent 约束都好于大部分专用插件，但复习只有失败样例的固定 3/7/30/90 天队列，不能替代 LeetLens 的知识缺口 + FSRS 闭环。

不要把 LeetHub、LeetPilot、AlgorithmAce、LeetCoach 或 cody-ai 当主系统：它们分别只是归档层、单次提示层或模拟面试层。

## 关键分析

### LeetLens

- 功能吻合度最高：内置浏览器、题目、编辑器、运行/提交、提交轨迹、知识图谱、FSRS 今日队列、学习计划、练习评分回写。
- 教学约束最完整：三级提示（方向、卡点、下一步）之外，还有确定性的代码/完整解法泄漏拦截；学习分析明确规定模型回答不能算作用户掌握证据。
- 风险：项目创建于 2026-08，社区和维护者冗余很低；只支持 Apple Silicon/macOS 15+ 与 `leetcode.cn`；发布包 ad-hoc 签名且未公证。
- 实测：v2.2.0 ZIP 中 app 为 arm64、最低 macOS 15.0、签名在磁盘上有效但 Gatekeeper 拒绝（与 README 的未公证说明一致）。当前机器只有 Command Line Tools、没有 README 要求的完整 Xcode，因此原生源码构建失败不能作为支持完整 Xcode 环境下的失败结论。旧 Electron 测试在未安装 npm 依赖时 98/102 通过，不能代表原生发布目标。

### lcex / LeetCode Practice

- 最佳 IDE 备选：VS Code/Cursor 内题库、运行、进度、统计、面试、Agent action、模式识别 drill、失败用例复习。
- 内置的 `lcex-dsa-hint` skill 默认口头提示、每轮一个问题、不写代码，教学约束清晰。
- 弱点：固定复习间隔且只覆盖失败样例；不从多轮对话和提交归纳知识缺口；Agent 与 Cursor/IDE chat 的集成仍依赖宿主命令。
- 实测：0.12.1 可 typecheck 和 bundle；测试 61 通过、1 个访问真实 LeetCode 的集成用例失败、5 跳过。

### EasyRepeat

- 浏览器插件中复习最强：自动捕获 Accepted/Wrong Answer、FSRS v4.5、笔记、热图、drill、多个模型提供商。
- 与需求的关键冲突：AI 主提示会建议 fix，可选后端明确生成并验证完整修复代码，不是严格的防剧透教练。
- 实测：46/57 suites 通过，11 suites 失败；517/544 tests 通过。失败覆盖评分 UI、提交序号、知识图谱和后台模块。生产依赖 audit 为 0，开发依赖有告警。

### leetmate + leetgo

- 终端路线中最好：四级 Hint/Nudge/Review/Answer、前三层不泄答案、SQLite、本地记录、题单、轻量复习；底座 leetgo 活跃且成熟。
- 实测 `go test ./...` 全部通过。
- 弱点：明确标注 Alpha；完整 FSRS 尚未接入；无图形 UI。

### 其他指定候选

- LeetPilot：四级渐进 hint 和输出过滤不错，但同时提供代码补全/修复，且没有长期轨迹/复习。测试通过，但 README 指定的构建命令在当前主分支因 TypeScript 无输入失败。
- AlgorithmAce：有统计、好友对比、问题搜索和本地聊天记录，但只有单句“不要给代码”的默认 prompt，没有复习；4 个提交、无测试，AI/好友功能还要求 GitHub star + 外部 Cloudflare Worker；生产依赖 audit 有 4 个告警。
- cody-ai：Ollama 本地模拟面试 prompt 很严格，但聊天历史仅进程内全局变量、无长期档案/复习，题目依赖非官方第三方 API。
- LeetCoach：同名项目至少两个；代表性 Flask 版只是按题名给概念 hint 的小应用，无提交接入、长期轨迹和复习。
- LeetHub：原版默认分支最后提交为 2022-10，只做 AC 后推 GitHub；新 LeetHub-3.0 仍然只是归档层。它不能提供教学和抗遗忘。
- LeetCode Ask Leet：官方、UI 与判题稳定性最高，但闭源，定位是 brainstorm/优化/生成测试/调试和 autocomplete，没有严格防剧透与长期复习闭环。

## 证据边界

没有找到对上述具体产品进行长期、随机对照的学习成效研究。“Agent 教学效果”评分是基于提示策略、是否读取真实用户代码/提交、是否有渐进披露和确定性防泄漏、是否要求主动回忆、以及测试/源码核验做出的工程推断，不是已证实的学习增益。

认知科学只支持设计原则：练习测试有助于延迟保持，分散练习优于集中学习；它不直接证明某个软件的实现有效。FSRS 本身适合调度，但对于算法题，复习任务必须要求从空白重建不变量/思路，而不是翻看旧代码。

## 建议

先使用 LeetLens 两周，只配置一个模型提供商、一个题单和本地数据；不部署 Redis、PostgreSQL/pgvector、远程 JDT LS，也不叠加 EasyRepeat/LeetHub。用 Time Machine 备份 `~/Library/Application Support/leetcode-ai-helper/`，不要把整个目录提交到 Git。

两周后只看四个指标：无提示完成率、平均提示层级、到期复习首次回忆成功率、重复错误类型。若 LeetLens 的平台限制或发布安全边界不可接受，切换到 lcex，而不是为 LeetLens 补造跨平台层。

## Claim-to-source ledger

| Claim | Source | Publisher/date/access | URL |
|---|---|---|---|
| LeetLens 功能、平台、安装、数据位置、未公证 | LeetLens README | huaxx-lab，访问 2026-09-07 | https://github.com/huaxx-lab/LeetLens/blob/main/README.en.md |
| LeetLens 三级 hint 与防泄漏 | ChatService.swift | huaxx-lab，访问 2026-09-07 | https://github.com/huaxx-lab/LeetLens/blob/main/native/Sources/LeetCodeAssistant/Services/ChatService.swift |
| lcex 功能与固定复习间隔 | LeetCode Practice README/Marketplace | NikkyAmresh/Microsoft Marketplace，访问 2026-09-07 | https://marketplace.visualstudio.com/items?itemName=NikkyAmresh.leetcode-practice |
| lcex Agent skill | CursorLcexPluginInstall.ts | NikkyAmresh，访问 2026-09-07 | https://github.com/NikkyAmresh/lcex/blob/main/src/modules/CursorLcexPluginInstall.ts |
| EasyRepeat FSRS、AI 与安装 | README | yc1838，访问 2026-09-07 | https://github.com/yc1838/LeetCode-EasyRepeat |
| EasyRepeat 自动修复 prompt | llm_sidecar.js/api.py | yc1838，访问 2026-09-07 | https://github.com/yc1838/LeetCode-EasyRepeat/blob/main/mcp-server/api.py |
| leetmate Alpha/轻量复习/分级 coach | README | DuckInAShirt，访问 2026-09-07 | https://github.com/DuckInAShirt/leetmate |
| leetgo 功能与维护规模 | README | j178，访问 2026-09-07 | https://github.com/j178/leetgo |
| LeetPilot 功能 | README | hareesh08，访问 2026-09-07 | https://github.com/hareesh08/LeetPilot |
| AlgorithmAce 功能与 star gate | README | 0xarchit，访问 2026-09-07 | https://github.com/0xarchit/AlgorithmAce |
| cody-ai 功能与第三方 API | README/source | anandpaithankar，访问 2026-09-07 | https://github.com/anandpaithankar/cody-ai |
| LeetCoach 功能 | README/source | kotinos，访问 2026-09-07 | https://github.com/kotinos/leetcoach |
| LeetHub 原版功能 | README | QasimWani，访问 2026-09-07 | https://github.com/QasimWani/LeetHub |
| LeetHub-3.0 当前 release | Releases | raphaelheinz，2026-03-01/访问 2026-09-07 | https://github.com/raphaelheinz/LeetHub-3.0/releases |
| Ask Leet 官方功能 | Premium page | LeetCode，访问 2026-09-07 | https://leetcode.com/subscribe/ |
| 测试效应 | Test-Enhanced Learning | Roediger & Karpicke, 2006 | https://www.psychologicalscience.org/journals/psychological-science/j.1467-9280.2006.01693.x/ |
| 分散练习元分析 | Distributed practice in verbal recall tasks | Cepeda et al., 2006 | https://pubmed.ncbi.nlm.nih.gov/16719566/ |
| FSRS 模型变量与实现生态 | Free Spaced Repetition Scheduler | Open Spaced Repetition，访问 2026-09-07 | https://github.com/open-spaced-repetition/free-spaced-repetition-scheduler |

## 停止条件

已覆盖全部点名候选、一个更强的新 IDE 候选、官方闭源基线与学习科学；最高影响结论均有 README、源码或本地构建/测试交叉核验。继续搜索只会增加同类早期项目，不太可能改变 LeetLens（当前环境）与 lcex（跨平台 IDE）的排序。
