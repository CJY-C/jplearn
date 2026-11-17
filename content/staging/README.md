# 后续课程编写与核对记录

本目录中的草稿不计入应用内容；只有移入 `authoring/`、加入 `manuscripts.json` 并生成批次的记录才进入课程。JSON 核对记录保留原始候选及来源事实，不把候选数计作完成量，也不以结构检查代替语言审校。

相似、倾向与动作结构一章现已移入注册源，准备版本 0.20.0 / build 26，尚未生成新 IPA。完整范围见[章节核对](../source-checks/n3-similarity-chapter.json)，实际发布状态见[课程实施表](../../docs/CURRICULUM.md)。

| 编写源 | 词汇根 / 词义目标 / 原创语境 | 核对 |
| --- | --- | --- |
| [N4 整理信息基础义](../authoring/n4-similarity-sense-prerequisites.tsv) | 1 / 2 / 4 | [词义边界](n4-similarity-sense-word-review.json) |
| [主题词](../authoring/n3-similarity-theme-words.tsv) | 120 / 124 / 248 | [字形、别读与意义](n3-similarity-theme-word-review.json) |
| [句型前置词](../authoring/n3-similarity-prerequisite-words.tsv) | 65 / 67 / 134 | [来源与义项](n3-similarity-prerequisite-word-review.json) |
| [阅读前置词](../authoring/n3-similarity-reading-prerequisite-words.tsv) | 92 / 93 / 186 | [当前词典核对](n3-similarity-reading-word-review.json) |

四份合计 278 个新词汇根（N3 277、N4 1）、286 个词义目标、572 个原创双语语境、36 个词汇单元。嫁、当たる、方向、場、まとめる的不同所教意义分开掌握，追加义项不重复计根。同形同读才共用认读；付ける、掛ける、録る三个先前注册的 N4 物理义项仍保留独立字形认读。

句型共 33 个实际功能、198 个原创语境，对应此前缺少的 22 项参考模式：

- [相似、性质与强烈感受](../authoring/n3-similarity-and-tendencies.tsv)：13 个功能。
- [时间与表现、适合性](../authoring/n3-similarity-extensions.tsv)、[目标对象和倾向](../authoring/n3-tendency-and-coverage.tsv)、[状态与遍布](../authoring/n3-state-and-surface.tsv)：9 个功能；[来源核对](n3-similarity-extension-source-checks.json)。
- [完成与临近](../authoring/n3-completion-and-inception.tsv)、[重做与困难](../authoring/n3-retrial-and-difficulty.tsv)、[边界与险些发生](../authoring/n3-boundaries-and-near-misses.tsv)、[范本与信息对应](../authoring/n3-models-and-correspondence.tsv)：11 个功能；[来源及复用范围](n3-action-structures-research.json)。

20 篇阅读各有两个连续段落、六个句文记录和两道证据题，共 120 个句文、40 道题，每篇 459–559 个日语字符。16 篇练习使用全部 33 个新功能；4 篇独立检测占本章 20%，其正文不用于例句。[结构与隔离报告](n3-similarity-reading-review.json)检查检测正文的连续 20 字没有进入普通材料；它不证明日语语言质量。

[98 处旧句关联](n3-similarity-prior-link-candidates.json)已逐项审查并随本章应用：94 处新增关联，4 处行政市し保留原词，10 处改用符合上下文的独立义项。原目标、正文、注音、中文、答案、阅读及相对顺序保留。[补充义项记录](n3-similarity-additional-sense-review.json)解释了空间方向与发展方向、碰撞与猜中／受光、物品归拢与归纳信息／集中处理等边界。

幻想叙事中的ミオ以 `P rn3130 ミオ みお` 声明，四次出现继续计为未知，不增加词根；同形普通词不会自动变专名。N3／N2 未教学实词不能借用这一例外。普通长文仍需实际独立词义回忆达到 95%，泛读 98%，每段最多三个不同未知词；收录不等于掌握。

可运行 `python3 content/staging/check_n3_similarity.py` 复查四份词汇源、词典记录、句型功能、前置依赖、阅读结构及隔离；它会先排除本章批次，再从当前注册源重建本章，避免借用残留生成数据。`python3 content/staging/check_n3_prior_links.py` 则只读比较本地 Git 基线 `964b1e1` 与当前运行时记录，确认仅 94 个旧句的所选 itemID 改变。修改稿件并核对后才使用 `--update-report` 更新结构报告。

所选来源事实核对、中文和题目均保留出处及授权范围，独立语言审校仍为 0。[初始句型前置候选](n3-similarity-prerequisite-roster.json)与[初始阅读前置候选](n3-similarity-reading-prerequisite-roster.json)保留历史发现状态；实际选择以注册源与逐项核对为准。语法后缀ばん不变成版的全局独立读音，光照的当たる不借用碰撞义，所有新词的重音均未猜填。

N5、N4、N3 注册源码已达各级数量与结构门槛；完整 N2 仍需额外 2,500 个词汇根、140 个知识点、140 篇阅读和 100 个单元，其中至少 28 篇检测，另有六项原版阅读衔接，每项至少三篇 N2 阅读。提前出现在 N3 的社区 N2／N1 参考词不抵扣这些要求。

[重音教学与声音选择](../../docs/PRONUNCIATION.md)包含三个入门模块和八个已核对参考词，未核对词不默认平板型。iOS 编译、SE3 布局、设备试听与新 IPA 仍待完成。2026-11-14 用户确认 Actions 本期额度用尽、18 天后刷新；本地制作继续，发布门槛保留。

N2 首章仍在编写，当前没有进入应用。三份词汇稿共 **83 个新词汇根、6 个追加义项、89 个词义目标、178 个原创语境、12 个词汇单元**：

| 编写源 | 词汇根 / 词义目标 / 语境 | 核对记录 |
| --- | --- | --- |
| [信息与文献主题词](n2-information-and-documents.tsv) | 64 / 64 / 128 | [所教词义、读音及出处](n2-information-and-documents-review.json) |
| [语境前置词与追加义项](n2-context-prerequisite-words.tsv) | 14 / 20 / 40 | [所教词义与认读条件](n2-context-prerequisite-words-review.json) |
| [N4 日常基础补缺](n4-context-foundation-words.tsv) | 5 / 5 / 10 | [词典核对](n4-context-foundation-words-review.json) |

新根中 N2 为 78 个，N4 为 5 个；不以 N4 补缺抵扣额外 2,500 个 N2 根。主题涵盖概念、定义、论据、检验、统计、比例、规则、企划、程序、传播、文献、译文、注释及观点。受理与认可是不同目标，销售额不等于利润；表題／標題不拆成两个根，手続不重复已有手続き，具体不重复已有具体的。

描く的文字描写限定えがく，保留与原绘画义不同的认读条件；触れる的接触体验、高い的评价水平、交換的意见互换、達する的达成结论、指す的指代分别练词义。这些是既有词的教学范围扩充，部分对应词典的不同义，部分是较宽词典意义内的具体教学范围；不声称它们是六个新词。所有新目标均未猜填重音。

[场景范围与媒介句型稿](n2-context-and-mediation.tsv)为 **6 个功能、36 个原创语境**，对应において的场所／时代／领域、を通じて・を通して的媒介／期间，以及とは限らない的非必然判断，共 3 项参考模式。[来源记录](n2-context-and-mediation-source-checks.json)核对国際交流基金的原始教学页及固定 JMdict。お知らせします复用知らせる的敬语构式，申し込み复用申込；数词、时间单位和好意＋的等构词不批量增加词根。

[五篇两段阅读初稿](n2-context-readings.tsv)包括说明通知、史料阅读、制作报告、文学讨论和调查简报，每篇 489–515 个日语字符、六个句文记录、两道证据题。4 篇普通练习使用全部 6 个新功能，1 篇检测占 20%，共 10 题。正文与题目原创；检测没有转作例句，也未复用已注册材料或本章普通材料的连续 20 字。

[结构、来源及隔离报告](n2-context-and-mediation-review.json)目前显示句型前置词形缺口为 0，阅读仍有 **20 个待核对词形**；这些是候选，不是 20 个新根。还需补教 Vたところ的尝试结果、に向けた的指向对象、Vるうえで的活动范围，并复核阅读与词语例句中的全部词义关联。`python3 content/staging/check_n2_context.py` 可只读重建三份词汇源、句型与阅读，检查词典读音限制、编号、前置图、语境、实际普通阅读关联及检测隔离；修改并复核后使用 `--update-report`。

独立日语审校仍为 0。旧句关联审查、阅读准备、章节登记和完整验证尚未完成；N2 已注册数量仍为 0，当前运行时资源保持 0.20.0 不变。完整 N2 与六项衔接的原定要求不缩减。

[阅读前置候选](n2-context-reading-prerequisite-roster.json)保留 20 个未决词形的具体句文位置与当前词典条目；日期、登録者等透明构词先核对原教学，不直接新增词根。さらに已复用更に，観察会拆为已知観察与会，百年按数词和时间单位组合处理。
