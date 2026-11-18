import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_content import make_pack, validate


class LearningRuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.rules = {r['id']: r for r in cls.pack['learningRules']}

    def test_independent_rules_and_rotating_contexts_have_no_fake_words(self):
        self.assertEqual(len(self.rules), 5)
        questions = [q for r in self.rules.values() for s in r['practiceSets'] for q in s['questions']]
        self.assertEqual(len(questions), 60)
        self.assertEqual(len({q['id'] for q in questions}), 60)
        self.assertTrue(all(s['questions'] for r in self.rules.values() for s in r['practiceSets']))
        self.assertEqual(len({q['prompt'] for q in questions}), 60)

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
