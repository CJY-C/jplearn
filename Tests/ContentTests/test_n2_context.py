import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / 'content/staging'))
from build_content import make_pack
from word_links import lexical_words
from check_n2_context import check as source_check
from check_n2_prior_links import check as prior_check


class N2ContextChapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.items = {w['id']: w for w in cls.pack['items']}

    def test_complete_sources_rebuild_without_phantom_words_or_future_prerequisites(self):
        result = source_check()
        self.assertEqual((result['wordRoots'], result['wordTargets'], result['wordContexts']), (119, 128, 256))
        self.assertEqual((result['n2WordRoots'], result['n3FoundationRoots'], result['n4FoundationRoots']), (101, 12, 6))
        self.assertEqual((result['draftGrammarFunctions'], result['draftOriginalContexts']), (13, 78))
        self.assertTrue(result['earlierOwnContextsHaveNoLaterLevelLinkedTargets'])
        self.assertTrue(result['completeDraftPackValidated'])
        self.assertEqual(result['wordExampleGaps'], {})
        self.assertEqual(result['gaps'], {})
        self.assertEqual(result['readingGaps'], {})
        self.assertEqual((result['readings'], result['assessmentReadings'], result['heldoutLeaks']), (5, 1, 0))

    def test_old_records_preserve_every_field_except_reviewed_associations(self):
        result = prior_check()
        self.assertEqual((result['reviewedOccurrences'], result['changedSentences'], result['changedReadings']), (139, 45, 2))
        self.assertEqual(result['changedSentenceAssociations'], 46)

    def test_restricted_depiction_pitch_and_degree_have_separate_meanings(self):
        narrative, trace = self.items['vn3p002'], self.items['vn3p005']
        self.assertEqual((narrative['level'], narrative['reading'], narrative['lexemeID']), ('N3', 'えがく', 'vn5035'))
        self.assertNotIn('readingOwnerID', narrative)
        self.assertEqual(set([trace['reading']] + trace['acceptedReadings']), {'えがく', 'かく'})
        self.assertEqual(trace['readingOwnerID'], 'vn5035')
        for identifier in ['vn4s006', 'vn4s007']:
            self.assertEqual((self.items[identifier]['level'], self.items[identifier]['readingOwnerID']), ('N4', 'v0041'))
        self.assertNotEqual(self.items['vn4s006']['meaning'], self.items['vn4s007']['meaning'])
        self.assertEqual(self.items['vn3p016']['jmdictEntryID'], 1555710)
        self.assertNotIn('りん', [self.items['vn3p016']['reading']] + self.items['vn3p016'].get('acceptedReadings', []))

    def test_dates_use_existing_units_and_verified_exception_instead_of_new_roots(self):
        reading = next(r for r in self.pack['readings'] if r['id'] == 'rn2002')
        self.assertEqual(reading['rulePrerequisites'], [dict(ruleID='rulemonth', questionIDs=['rulemonths1q3'])])
        self.assertFalse({'四月三日', '四月七日', '登録者'} & {w['text'] for w in lexical_words(self.pack['items'])})
        self.assertEqual({w['itemID'] for w in reading['vocabulary'] if w['text'] in ['三日', '七日']}, {'vn5529', 'vn5533'})
