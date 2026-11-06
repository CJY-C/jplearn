# 课程源文件

`catalog.json` 保存课程版本、来源与阶段预算；`legacy/` 保留已发布内容的固定编号；`batches/` 保存新增的显式记录。`scripts/build_content.py` 仅合并并校验这些记录，不根据顺序重新分配编号。`scripts/author_batch.py` 是早期可选的编写辅助。新结构课程以 `authoring/n5-structures.tsv` 的显式语境键为编写源，使用 `scripts/compile_grammar.py` 编译为批次 JSON；CI 会检查二者一致。

0.12.0：1,856 个词、固定搭配与常用数量表达，另 6 个已有词的新义项；166 个知识点、2,687 道词句题、180 篇阅读、6 个入门模块。38 篇阅读标记为 assessment；其余进入日常推荐或轻松阅读。实际覆盖与剩余门槛由 `scripts/audit_curriculum.py` 报告。

新增记录须提供具体出处或明确标记为项目原创。`reference` 是核对入口，`translated` 是项目翻译，`adapted` 是改编，`sourceChecked` 仅表示已与出处对齐；这些状态均不能替代独立语言审校。本批没有独立专业审校记录。

教材原文对照引用 Tae Kim《A Japanese Guide to Japanese Grammar》，原作者按 CC BY-NC-SA 授权；版本和 PDF SHA-256 保存在 `manifest.json`。中文翻译与新增练习为本项目整理，改动已明确标记。项目原创与译编文本按 CC BY-NC-SA 3.0 US 提供。来自不同许可的材料保留其独立署名和条件，不能改成一个统一的更宽松许可。

部分新增例句注音使用 UniDic 2.1.2（unidic-lite 1.0.8）辅助分词后整理，许可见 `licenses/UniDic-BSD.txt`。词干链接和歧义读音仍需核对。应用运行和 GitHub 构建不依赖分词工具，也不下载词典。

PDX、いろどり、JMdict、たどくのひろば在本批作为核对或后续制作入口，未打包这些来源的教材全文、图片、音频或完整词典。不会因为免费可下载而默认其内容可任意改编。

编辑后执行 `python3 scripts/build_content.py`，再执行 `python3 scripts/build_content.py --check` 和 `python3 -m unittest discover -s Tests/ContentTests -v`。旧学习目标的编号不复用；新增义项、读音或实质不同的材料分配新编号。

`reference/openjlpt-grammar.json` 固定 403 项 N5–N2 参考模式；`syllabus.json` 保留四级实际目标、覆盖映射和六项原版衔接要求。`scripts/audit_curriculum.py --require-complete` 只有所有阶段满足门槛才通过，当前会如实失败。规划清单、对应编号、实际编写和独立审校是不同状态。

OpenJLPT 覆盖清单与新增 `002-n5-structures.json` 按 CC BY-SA 4.0 分别署名；后者的例句、规则和问题为项目原创。早期 Tae Kim 译编及项目内容保留 CC BY-NC-SA 3.0 US，不将不同许可合并为统一授权。OpenJLPT 的源版本、许可证与上游署名见 `manifest.json` 和 `licenses/OpenJLPT-*`；此批没有打包其词汇或 Tatoeba 例句。

`authoring/n5-readings.tsv` 保存 56 篇 N5 阅读、2 篇替换旧版已曝光材料的 N4 检测和 6 个修复例句，由 `scripts/compile_readings.py` 编译。每个标记包含词形、注音和可选原形，未收录的原形保留空 itemID。`-` 专用于有注音的语法部分，`?` 专用于不能直接套用同形词义的专名；助词和辅助词尾不作为独立词语重复计数。

`authoring/n5-reading-words.tsv` 保存显式词条、两个语境及辨义干扰项，由 `scripts/compile_words.py` 编译。数量表达用于阅读中的钟点、时长和次数区分，不按数字组合批量造词。A 记录仅列同一义项的其他读音；D 记录为孤立字形提供义项线索，例如「十分」的十分钟读音不与「充分」混用。三个编译器都必须通过 `--check`。

`manuscripts.json` 注册全部编写源。统一运行 `python3 scripts/compile_course.py` 后再生成课程包；编译器先建立所有当前词条的索引，不借用旧生成文件残留的目标。`H` 声明新源的级别，`G` 将新义项关联到已有词。新义项有独立编号、至少两个不同语境和词义历史，不增加总词数；只有可接受读音集合完全相同才共用读音学习。较窄的读音条件仍独立练习。

同形多义的标注必须使用 `[词形|注音|@目标编号]`，例如空间通行和内容遗漏的「抜ける」分别引用不同义项。未声明义项的歧义引用会报错，不能按导入顺序取最后一个词条，也不能为了覆盖率把未教的内容词写成语法 `-`。`?` 保留真实未知义项或专名，不计作已会。

退役检测映射保存在 `syllabus.json` 的 `retiredAssessments`，用于保留历史曝光事实。r036、r039 即使不再被当前例句引用，也不能重新标记为未见检测；替换材料必须使用新编号并保持相同级别。
