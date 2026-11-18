import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_content import make_pack, validate
from compile_readings import compile_manuscript
from check_rule_transfer import check as check_transfer


class LearningRuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.rules = {r['id']: r for r in cls.pack['learningRules']}

    def test_independent_rules_and_rotating_contexts_have_no_fake_words(self):
        self.assertEqual(len(self.rules), 7)
        questions = [q for r in self.rules.values() for s in r['practiceSets'] for q in s['questions']]
        self.assertEqual(len(questions), 84)
        self.assertEqual(len({q['id'] for q in questions}), 84)
        self.assertTrue(all(s['questions'] for r in self.rules.values() for s in r['practiceSets']))
        self.assertEqual(len({q['prompt'] for q in questions}), 84)

    def test_productive_forms_reuse_lemmas_and_keep_meanings_independent(self):
        for identifier in ['ruleverbforms', 'ruleadjectiveforms']:
            rule = self.rules[identifier]
            self.assertEqual(rule['regularItemIDs'], [])
            self.assertTrue(rule['prerequisiteIDs'])
            self.assertEqual(rule['prerequisiteRuleIDs'], [])
        proof = check_transfer(self.pack)
        self.assertEqual((proof['newRules'], proof['newQuestions']), (2, 24))
        self.assertEqual((proof['newLexicalRoots'], proof['newGrammarFunctions']), (0, 0))
        self.assertTrue(proof['oldCollectionsPreserved'])

    def test_rule_extension_cannot_silently_rewrite_prior_course_or_rules(self):
        for collection, field in [('items', 'meaning'), ('learningRules', 'explanation')]:
            pack = copy.deepcopy(self.pack)
            pack[collection][0][field] = 'unreviewed change'
            with self.assertRaises(AssertionError): check_transfer(pack)
        pack = copy.deepcopy(self.pack)
        next(r for r in pack['learningRules'] if r['id'] == 'ruleverbforms')['regularItemIDs'] = ['v0025']
        with self.assertRaises(AssertionError): check_transfer(pack)

    def test_exceptions_durations_and_lexicalized_words_cannot_be_consolidated(self):
        covered = {i for r in self.rules.values() for i in r['regularItemIDs']}
        self.assertEqual(covered, {'v0158', 'v0160', 'vn5007', 'v0161', 'vn5013'})
        self.assertTrue(covered.isdisjoint({'vn5006', 'vn5527', 'vn5537', 'vn6503', 'v0159', 'vn5726', 'vn5172'}))
        self.assertEqual(self.rules['ruledate']['regularItemIDs'], [])
        self.assertIn('ついたち', self.rules['ruledate']['explanation'] + ''.join(self.rules['ruledate']['examples']))

    def test_invalid_regular_word_or_duplicate_owner_fails_build(self):
        pack = copy.deepcopy(self.pack)
        pack['learningRules'][0]['regularItemIDs'] = ['g030']
        with self.assertRaises(AssertionError): validate(pack)

    def test_rule_cycle_and_cross_module_question_collision_fail_build(self):
        pack = copy.deepcopy(self.pack)
        pack['learningRules'][0]['prerequisiteRuleIDs'] = ['rulemonth']
        with self.assertRaises(ValueError): validate(pack)
        pack = copy.deepcopy(self.pack)
        pack['learningRules'][0]['practiceSets'][0]['questions'][0]['id'] = pack['introModules'][0]['questions'][0]['id']
        with self.assertRaises(AssertionError): validate(pack)
        pack = copy.deepcopy(self.pack)
        pack['learningRules'][0]['regularItemIDs'] = ['v0161']
        with self.assertRaises(AssertionError): validate(pack)

    def test_reading_rule_references_check_exceptions_and_duplicate_rules(self):
        prerequisite = dict(ruleID='rulemonth', questionIDs=['rulemonths1q3'])
        pack = copy.deepcopy(self.pack)
        pack['readings'][0]['rulePrerequisites'] = [prerequisite]
        validate(pack)
        for invalid in [[dict(ruleID='rulemonth', questionIDs=['rulebooks1q1'])],
                        [prerequisite, prerequisite],
                        [dict(ruleID='rulemonth', questionIDs=['rulemonths1q3'] * 2)]]:
            pack['readings'][0]['rulePrerequisites'] = invalid
            with self.assertRaises(AssertionError): validate(pack)

    def test_reading_compiler_requires_declared_rule_and_its_own_questions(self):
        # No source sentence is needed to reject an invalid D declaration.
        for declaration in ['D\trtest\tmissing\t', 'D\trtest\trulemonth\trulebooks1q1',
                            'D\trtest\trulemonth\trulemonths1q3,rulemonths1q3']:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'invalid.tsv'
                path.write_text(declaration + '\n')
                with self.assertRaises(ValueError): compile_manuscript(path, self.pack)

    def test_reading_compiler_emits_rule_prerequisites_only_when_declared(self):
        source = '\n'.join(['R\trtest\t日期\t通知\tN5\tpractice\tg001',
            'S\trtest\ta\t1\t[本|ほん]です。\t是书。',
            'S\trtest\tb\t1\t[本|ほん]でした。\t曾是书。',
            'S\trtest\tc\t1\t[本|ほん]ではありません。\t不是书。',
            'Q\trtest\t1\t是什么？\t书\t笔\t纸\ta\tinformation\t第一句说明是书。'])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'reading.tsv'
            path.write_text(source)
            self.assertNotIn('rulePrerequisites', compile_manuscript(path, self.pack)['readings'][0])
            path.write_text(source + '\nD\trtest\trulemonth\trulemonths1q3\n')
            self.assertEqual(compile_manuscript(path, self.pack)['readings'][0]['rulePrerequisites'],
                [dict(ruleID='rulemonth', questionIDs=['rulemonths1q3'])])
