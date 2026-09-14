# 个人 LeetCode + AI Agent 刷题方案调研报告

> 调研日期：2026-09-07；结论针对当前机器 macOS 15.7.7 / Apple Silicon，并兼顾跨平台备选。

## 结论

**当前环境的最佳总方案：LeetLens v2.2.0。**

它是已核验候选中唯一真正把以下链条放在同一个产品里的方案：

`做题/提问/提交 → 形成学习证据 → 识别知识缺口 → 知识图谱 → FSRS 到期队列 → 主动回忆练习 → 评分写回下一次复习`

**跨平台或 IDE 优先的最佳备选：NikkyAmresh/lcex（Marketplace 名 LeetCode Practice）+ IDE Agent。** 它的编辑体验、源码可迁移性和工程状态更好，但长期学习层明显浅于 LeetLens：只对失败样例按固定 3/7/30/90 天复习，没有从对话和提交持续提炼知识缺口。

不要把 LeetHub、LeetPilot、AlgorithmAce、LeetCoach 或 cody-ai 当作主系统。它们分别只解决归档、单次提示或模拟面试中的一小段。

## 评分方法

总分 100：功能闭环 25%、UI 15%、Agent 教学/防剧透 25%、轨迹与抗遗忘 15%、工程成熟与维护性 20%。其中“教学效果”是源码与交互设计审计，不是长期学习效果实验证明。

| 方案 | 总分 | 功能闭环 | UI | Agent 教学 | 轨迹/复习 | 工程/维护 | 定位 |
|---|---:|---:|---:|---:|---:|---:|---|
| **LeetLens** | **87** | 5.0/5 | 4.8 | 5.0 | 5.0 | 2.0 | **当前机器最佳** |
| **lcex / LeetCode Practice** | **81** | 4.2 | 4.6 | 4.4 | 3.0 | 3.7 | **跨平台/IDE 最佳** |
| leetmate + leetgo | 73 | 4.0 | 2.8 | 4.5 | 2.8 | 3.5 | 终端用户最佳 |
| LeetCode Ask Leet（闭源基线） | 70 | 4.0 | 5.0 | 2.0 | 1.5 | 5.0 | 官方功能强，但不满足开源/抗遗忘 |
| EasyRepeat | 64 | 4.0 | 3.7 | 2.2 | 4.2 | 2.2 | 浏览器内复习最强，但会给修复代码 |
| cody-ai | 51 | 2.5 | 3.5 | 4.0 | 1.0 | 1.2 | 一次性模拟面试 |
| LeetPilot | 49 | 2.3 | 3.4 | 3.4 | 1.0 | 1.8 | 单题提示/补全插件 |
| AlgorithmAce | 45 | 2.5 | 3.5 | 2.6 | 1.3 | 1.3 | 统计 + AI 聊天面板 |
| LeetCoach | 43 | 1.8 | 3.0 | 3.5 | 1.0 | 1.2 | 极简概念提示器 |
| LeetHub / LeetHub-3.0 | 34 | 1.5 | 2.5 | 0 | 1.5 | 3.5 | 仅 GitHub 归档层 |

## 重点方案分析

### 1. LeetLens：为什么它赢

LeetLens 的优势不只是“功能多”，而是数据闭环正确：模型回答不算你的能力证据；系统从用户提问、实际作答和提交历史判断薄弱点，同一知识点跨对话合并，再交给 FSRS 和遗忘曲线进入今日队列。应用还集成题目、编辑器、运行/提交、题解/视频、知识图谱与学习计划。[LeetLens README](https://github.com/huaxx-lab/LeetLens/blob/main/README.en.md)

教学约束也是目前最强的：提示分为“方向 → 当前卡点 → 下一步”三级；每次只升级一级。更重要的是，源码不只相信 prompt，还会拒绝代码围栏、完整解法标记和程序形态明显的回复，这是比“请不要给答案”更可靠的工程保护。[分级提示与防泄漏实现](https://github.com/huaxx-lab/LeetLens/blob/main/native/Sources/LeetCodeAssistant/Services/ChatService.swift)

UI 方面，它是完整的原生桌面工作台，而不是 500px 宽的浏览器 popup：题面/提交轨迹、学习中心、今日复习、知识图谱、学习洞察、算法模板和浏览器都在统一导航内。视觉上克制、信息层级清楚，明显优于 EasyRepeat 的高密度赛博风格和 LeetPilot 的窄面板。

它的短板也必须正视：

- 只面向 `leetcode.cn`；只发布 Apple Silicon、macOS 15+ 版本。
- 项目在 2026-08 才创建，当前规模约 29 个提交、2 位代码作者、13 stars；活跃，但还不能叫成熟社区项目。
- v2.2.0 发布包是 ad-hoc 签名、没有 Apple notarization。我的本地检查确认 app 为 arm64、最低系统 15.0、签名本身有效，但 Gatekeeper 会拒绝它；这与 README 的安装警告一致。
- 源码构建要求完整 Xcode。当前机器只有 Command Line Tools，所以本轮不能完成有效的原生 build/test 认证；不应把这次失败误判为完整 Xcode 环境下一定构建失败。
- 仓库没有 GitHub Actions CI；中文 README 的版本徽章仍为 v2.1.0，已与 v2.2.0 package/release 不一致，现有版本同步测试会因此失败。

结论：**需求适配第一，工程成熟度只是中低。适合现在使用，不适合把你的数据和流程锁死在它独有格式里。**

### 2. lcex：最好的 IDE + Agent 路线

`NikkyAmresh/lcex` 在 VS Code/Cursor 里提供题库、模板、运行、统计、面试报告、模式识别 drill、失败用例复习，以及直接唤起 Agent 的 Hint/Analyze 操作。它会把约束推导出的复杂度预算、热点和当前 verdict 写入 sidecar，让 Agent 的提示基于真实代码状态，而不是只看题名。[GitHub](https://github.com/NikkyAmresh/lcex) · [Marketplace 功能说明](https://marketplace.visualstudio.com/items?itemName=NikkyAmresh.leetcode-practice)

它附带的 `lcex-dsa-hint` skill 默认不写代码，每轮只指出一个问题、问一个问题，并重新读取当前代码；这是相当好的苏格拉底式 Agent 约束。[Agent skill 源码](https://github.com/NikkyAmresh/lcex/blob/main/src/modules/CursorLcexPluginInstall.ts)

工程上，0.12.1 在本机通过 TypeScript typecheck 和 bundle；测试为 61 通过、1 个访问真实 LeetCode 的集成测试失败、5 跳过。Marketplace/Open VSX 有约 10K 下载，更新到 2026-09-01，维护信号强于多数专用 AI 插件。

它输给 LeetLens 的地方是长期学习模型：复习只保存失败样例，使用固定 3/7/30/90 天阶梯；不会把“不会定义循环不变量”“总在窗口左边界犯错”这样的跨题知识缺口持续合并成学习项。[复习与 DSA loop](https://marketplace.visualstudio.com/items?itemName=NikkyAmresh.leetcode-practice)

适用场景：使用 `leetcode.com`、Windows/Linux、偏好 VS Code/Cursor、希望源码天然留在普通 Git 仓库，或不能接受未公证桌面应用。

### 3. leetmate + leetgo：最稳的终端备选

leetmate 把 Hint、Nudge、Review、Answer 分为四层，前三层禁止完整代码，第四层要二次确认；题单、进度、对话和复习保存在本地 SQLite。它把抓题、测试、提交交给维护更成熟的 leetgo。[leetmate](https://github.com/DuckInAShirt/leetmate) · [leetgo](https://github.com/j178/leetgo)

本机 `go test ./...` 全部通过；leetgo 有约 772 个提交，持续更新，底座可信度高。问题是 leetmate 自己明确标注 Alpha，所谓 FSRS 目前只是轻量 “FSRS-style”，没有完整参数化，而且没有图形 UI。

### 4. EasyRepeat：复习强，教学方向不匹配

EasyRepeat 能自动捕获 Accepted 和 Wrong Answer，维护 FSRS v4.5 状态、今日队列、热图、上下文笔记和个性化 drill，是浏览器插件里最接近“长期复习系统”的项目。[EasyRepeat README](https://github.com/yc1838/LeetCode-EasyRepeat)

但它的 AI 主路径会给出 fix；可选后端甚至要求模型生成“正确可工作的 Python 解法”并沙箱验证。因此，它更像错题分析/自动修复器，不是“只启发、不剧透”的教练。[自动修复实现](https://github.com/yc1838/LeetCode-EasyRepeat/blob/main/mcp-server/api.py)

本轮从干净依赖安装运行测试：46/57 suites 通过、11 suites 失败；517/544 tests 通过。失败涉及评分弹窗、轨迹序号、知识图谱和后台模块。优点是生产依赖审计没有漏洞；缺点是集成稳定性仍然不够。

适用场景：跨平台、坚持在 LeetCode 网页做题、把“到期提醒”置于“严格不剧透”之上。

## 其他点名项目

- **LeetPilot**：有四级渐进提示和完整解法过滤，但同时提供自动补全、错误修复与优化；没有长期轨迹和复习。测试通过，但 README 所写的 `npm run build:extension` 在当前主分支会因 TypeScript 找不到输入文件失败。[LeetPilot](https://github.com/hareesh08/LeetPilot)
- **AlgorithmAce**：UI 有 POTD、统计、好友雷达图、问题搜索和 AI chat，但没有复习调度；默认只用一句 prompt 要求“解释逻辑但不写代码”。仓库只有 4 个提交、无测试，AI/好友功能要求 GitHub star，并依赖外部 Cloudflare Worker；生产依赖审计还有 4 个已知告警。[AlgorithmAce](https://github.com/0xarchit/AlgorithmAce)
- **cody-ai**：45 分钟本地 Ollama 面试模拟器，prompt 的反剧透规则不错，Monaco + chat UI 也完整；但聊天历史只是后端进程内的全局数组，没有长期档案/复习，取题依赖第三方非官方 API。[cody-ai](https://github.com/anandpaithankar/cody-ai)
- **LeetCoach**：同名仓库不止一个。代表性的 Flask/Gemini 版只是按题名和用户描述给一两句概念 hint；没有读取真实提交、长期轨迹或复习。仓库自己称其为一次约五小时的小项目，不应当作长期基础设施。[kotinos/leetcoach](https://github.com/kotinos/leetcoach)
- **LeetHub**：原版最有知名度，但默认分支最后提交停在 2022-10，并且只在 AC 后把题和代码推到 GitHub。当前如需归档，应使用仍有 release 的 [LeetHub-3.0](https://github.com/raphaelheinz/LeetHub-3.0/releases) 或其他 Manifest V3 重写；无论哪个版本，它都不是教练或复习系统。[原版 LeetHub](https://github.com/QasimWani/LeetHub)
- **LeetCode Ask Leet**：官方闭源基线，判题、题库、云同步和 UI 最稳；但定位包括 brainstorm、优化、生成测试、debug 和 autocomplete，本质上鼓励更快得到答案，没有严格的渐进提示和复习调度。[LeetCode Premium / Ask Leet](https://leetcode.com/subscribe/)

## 为什么必须是“主动回忆 + 间隔”，不能只是 AI 聊天

研究表明，主动测试不仅测量记忆，也能增强延迟保持；重复阅读在短时测验中可能占优，但延迟两天或一周时，先前测试带来的保持更好。[Roediger & Karpicke, 2006](https://www.psychologicalscience.org/journals/psychological-science/j.1467-9280.2006.01693.x/)

分散练习的元分析也表明，复习间隔与目标保持时长应共同决定，而不是永远使用固定 1/3/7/14 天表。[Cepeda et al., 2006](https://pubmed.ncbi.nlm.nih.gov/16719566/)

FSRS 用 difficulty、stability、retrievability 建模并在本地调度，比手写固定日期表更适合作为长期队列底座。[Open Spaced Repetition / FSRS](https://github.com/open-spaced-repetition/free-spaced-repetition-scheduler)

但对算法题，正确的“复习卡”不是背代码。每次到期应先从空白回答：

1. 识别模式的触发条件是什么？
2. 核心不变量/状态含义是什么？
3. 为什么复杂度成立？
4. 哪个边界最容易错？
5. 能否在不看旧代码的情况下重写骨架？

这也是 LeetLens 比单纯 LeetHub、聊天插件或题解生成器更贴合需求的根本原因。

## 推荐落地方案

### 第 0 天：最小安装

1. 只从 [LeetLens 官方 Releases](https://github.com/huaxx-lab/LeetLens/releases/latest) 下载 v2.2.0 的 arm64 DMG/ZIP。
2. 先尝试 Finder 右键“打开”。它未经过 Apple 公证；只有在你确认来源并接受风险后，才按上游说明移除 quarantine。不要从第三方网盘下载。
3. 设置里只配一个模型提供商。先让主聊天、提示、学习分析和评分都用同一模型；用量或成本真的成为问题后，再拆成不同模型。
4. 在内置浏览器登录 `leetcode.cn`，只导入一个题单，例如热题 100 或面试经典 150。
5. 设定每天 **2 道新题、最多 5 个到期复习**。队列积压时先减少新题，不提高复习上限。
6. 不部署 Redis、PostgreSQL/pgvector、远程 JDT LS；单机本地文件已经覆盖核心需求。

### 每日 60 分钟流程

- **15 分钟复习**：先看今日到期项；隐藏旧代码，口述模式、不变量、复杂度和一个边界，再编码或回答检测题。
- **35 分钟新题**：前 15–20 分钟不请求提示；卡住后只点“方向”。写出一次真实尝试后才看“卡点”；再次尝试后才允许“下一步”。
- **10 分钟复盘**：AC 后先自己写出复杂度、失败根因和可迁移模式，再让 AI 评审。不要把 AI 的解释直接当成自己的笔记。
- **评分**：严格按“能否无提示重建”评分，而不是按“看懂答案后的熟悉感”评分。

### 每周流程

- 做一次 45 分钟、全程禁用提示的模拟面试。
- 从学习洞察里只选前三个重复薄弱点，各做一道迁移题；不要按已刷题数量追 KPI。
- 使用 macOS Time Machine 备份 `~/Library/Application Support/leetcode-ai-helper/`。该目录可能含账号、代码和配置，不要整体提交到 GitHub。

### 两周验收指标

只看四项：

- 无提示完成率；
- 平均使用到第几级提示；
- 到期复习第一次主动回忆的成功率；
- 相同错误类型是否重复出现。

连续两周复习完成率低于 70% 时，先把新题降到每天 1 道。提示层级越来越高时，说明题单难度超过当前最近发展区，应回退一个难度，而不是换更强模型直接给答案。

## 跨平台/IDE 回退方案

如果你改用 `leetcode.com`、Windows/Linux，或不能接受未公证应用，直接切到 lcex：

```bash
code --install-extension NikkyAmresh.leetcode-practice
printf '{}\n' > .leetcode
```

然后在设置中打开 `leetcodePractice.bugReview.enabled`。Cursor 可安装并使用它附带的 `lcex-dsa-hint` skill；普通 VS Code 需要把同等的“口头提示、每轮一个问题、默认不写代码”规则交给现有 Agent。模拟面试时关闭 IDE 的通用代码自动补全。除本报告外，当前 `lc-master` 目录没有项目文件且还不是 Git 仓库，很适合成为这一工作区，但没有必要先造数据库、Web Dashboard 或自定义同步服务。

终端优先则使用：

```bash
brew install j178/tap/leetgo
brew install DuckInAShirt/tap/leetmate
```

## 明确不建议做的事

- 不要同时安装 LeetLens、EasyRepeat、LeetPilot、AlgorithmAce 和 LeetHub：它们会形成多个互不一致的“进度真相”。
- 不要为个人刷题先自建 RAG、向量库或多 Agent 编排；本地记录 + 一个强模型 + FSRS 已足够。
- 不要把 star 数当成熟度。除了 LeetHub、vscode-leetcode、leetgo 等老工具，多数“AI LeetCode 教练”仍是 1–3 位作者、数周开发周期的早期项目。
- 不要让 AI 自动补全首次解题代码。真正值得优化的是无提示完成率和延迟回忆，不是当天 AC 的速度。

## 局限

没有公开的独立长期实验直接比较这些具体产品的学习效果。项目功能主要以 README、源码、发布物和本地测试核验；评分是工程判断。浏览器插件和桌面客户端都依赖 LeetCode 未承诺稳定的网页/GraphQL 行为，后续可能因登录或 DOM/API 变化失效。
