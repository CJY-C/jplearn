# 课程源文件

`catalog.json` 保存课程版本、来源与阶段预算；`legacy/` 保留已发布内容的固定编号；`batches/` 保存新增的显式记录。`scripts/build_content.py` 仅合并并校验这些记录，不根据顺序重新分配编号。`scripts/author_batch.py` 是早期可选的编写辅助。新结构课程以 `authoring/n5-structures.tsv` 的显式语境键为编写源，使用 `scripts/compile_grammar.py` 编译为批次 JSON；CI 会检查二者一致。

当前：323 个词、72 个知识点、571 道词句题、40 篇阅读、6 个入门模块。补充批含 42 个 N5 知识点，每项六个显式、不同正文的语境。阅读中 8 篇标记为 assessment，其余进入日常推荐或轻松阅读。

新增记录须提供具体出处或明确标记为项目原创。`reference` 是核对入口，`translated` 是项目翻译，`adapted` 是改编，`sourceChecked` 仅表示已与出处对齐；这些状态均不能替代独立语言审校。本批没有独立专业审校记录。

教材原文对照引用 Tae Kim《A Japanese Guide to Japanese Grammar》，原作者按 CC BY-NC-SA 授权；版本和 PDF SHA-256 保存在 `manifest.json`。中文翻译与新增练习为本项目整理，改动已明确标记。项目原创与译编文本按 CC BY-NC-SA 3.0 US 提供。来自不同许可的材料保留其独立署名和条件，不能改成一个统一的更宽松许可。

部分新增例句注音使用 UniDic 2.1.2（unidic-lite 1.0.8）辅助分词后整理，许可见 `licenses/UniDic-BSD.txt`。词干链接和歧义读音仍需核对。应用运行和 GitHub 构建不依赖分词工具，也不下载词典。

PDX、いろどり、JMdict、たどくのひろば在本批作为核对或后续制作入口，未打包这些来源的教材全文、图片、音频或完整词典。不会因为免费可下载而默认其内容可任意改编。

编辑后执行 `python3 scripts/build_content.py`，再执行 `python3 scripts/build_content.py --check` 和 `python3 -m unittest discover -s Tests/ContentTests -v`。旧学习目标的编号不复用；新增义项、读音或实质不同的材料分配新编号。

`reference/openjlpt-grammar.json` 固定 403 项 N5–N2 参考模式；`syllabus.json` 保留四级实际目标、覆盖映射和六项原版衔接要求。`scripts/audit_curriculum.py --require-complete` 只有所有阶段满足门槛才通过，当前会如实失败。规划清单、对应编号、实际编写和独立审校是不同状态。

OpenJLPT 覆盖清单与新增 `002-n5-structures.json` 按 CC BY-SA 4.0 分别署名；后者的例句、规则和问题为项目原创。早期 Tae Kim 译编及项目内容保留 CC BY-NC-SA 3.0 US，不将不同许可合并为统一授权。OpenJLPT 的源版本、许可证与上游署名见 `manifest.json` 和 `licenses/OpenJLPT-*`；此批没有打包其词汇或 Tatoeba 例句。
