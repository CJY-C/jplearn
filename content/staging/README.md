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

N2 首章现已登记为试用内容，仍未生成新 IPA。五份词汇源合计 **119 个新词汇根、9 个追加义项、128 个词义目标、256 个原创语境、22 个词汇单元**：

| 编写源 | 词汇根 / 目标 / 语境 | 核对记录 |
| --- | --- | --- |
| [N4 前置补缺](../authoring/n4-context-foundation-words.tsv) | 6 / 8 / 16 | [词义与读音](n4-context-foundation-words-review.json) |
| [N3 阅读补缺](../authoring/n3-context-foundation-words.tsv) | 12 / 16 / 32 | [词义与读音](n3-context-foundation-words-review.json) |
| [信息与文献](../authoring/n2-information-and-documents.tsv) | 62 / 62 / 124 | [来源事实](n2-information-and-documents-review.json) |
| [语境前置与追加义](../authoring/n2-context-prerequisite-words.tsv) | 11 / 14 / 28 | [词义边界](n2-context-prerequisite-words-review.json) |
| [阅读与结构词](../authoring/n2-context-reading-words.tsv) | 28 / 28 / 56 | [来源事实](n2-context-reading-words-review.json) |

本批N2为101个新根，前级补缺18个不抵扣N2的额外2500词要求。已有N4语境中的技术／湿度程度高、声音音高，以及N3中的文字描写、形状轨迹、接触思想、交换意见先补教；它们分别记录词义。描写义描く仅接受えがく，不能借用绘画义的かく答案；形状轨迹义允许えがく／かく。音高与词语重音型不混同，未核对词不猜填重音。

[句型源](../authoring/n2-context-and-mediation.tsv)含13个实际功能、78个原创语境，对应6项参考模式：において、を通じて／通して、とは限らない、Vたところ、に向けて、うえで。うえで分开训练活动中的要点、依据先行动结果、资料所示信息及评价方面。每个功能保留普通阅读中的真实片段证据；[来源范围](n2-context-and-mediation-source-checks.json)说明实际读过的JPF／NINJAL资料，不复制来源例句。

[五篇阅读](../authoring/n2-context-readings.tsv)各两段、六个句文记录、两道证据题，每篇495–535个日语字符。四篇练习覆盖13个功能，一篇独立检测占20%。检测正文未转作词语或句型例句，连续20字隔离校验通过，独立日语审校仍为0。

二百字、一枚、一文、年数、Vます形＋方、読み直す复用单位和构词，不重复造根。四月三日／七日复用数字、月份规则与既有日期；自动阅读需要月份迁移和四月特殊读法的完整独立题组证据。登録者改写为登録した人，不借用未教的者接辞。

[139处旧语料选择](n2-context-old-sense-decisions.json)已应用；其中46处实际关联改动分布在45个句文，两篇阅读的词汇投影同步更新，其他歧义明确指向原义项。原目标、正文、注音、翻译、答案、重音标注及相对顺序由[登记证明](../source-checks/n2-context-chapter.json)逐字段核对。

可运行`python3 content/staging/check_n2_context.py`独立排除生成批次后重建本章，核对词典事实、根去重、前置、语境、普通阅读使用和检测隔离。`python3 content/staging/check_n2_prior_links.py`验证当前完整资源相对b39c257仅有批准的旧关联变化。N3原登记审计保留其历史检查点，并先验证N2后续变化，避免把后续修改当作N3原交付内容。历史候选可用`preflight_n2_context.py`重建，不把候选数当新增词数。

当前全包3766词汇根、另33义项、325知识点、5578词句题、315阅读（65检测）、719单元、9入门模块；另有五组规则60题。N2仍缺2399词、127功能、135阅读、71单元、27检测和117项参考模式；六项原版衔接均未达到三篇。iOS编译、SE3、声音试听与设备验收继续保留门槛，完整N5–N2尚未完成。
