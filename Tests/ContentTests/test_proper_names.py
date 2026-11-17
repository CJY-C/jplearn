import copy
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_content import make_pack, validate
from compile_readings import compile_manuscript


class ProperNameTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.grammar = next(i['id'] for i in cls.pack['items'] if i['kind'] == 'grammar')

    def manuscript(self, declaration='P\trn3names\tミオ\tみお\n', level='N3'):
        return (f'R\trn3names\t名前の確認\t测试\t{level}\tpractice\t{self.grammar}\n' + declaration +
            'S\trn3names\ta\ta\t[ミオ|みお|?]はここにいます。\t美绪在这里。\n'
            'S\trn3names\tb\ta\t[ミオ|みお|?]はそとをみています。\t美绪正在往外看。\n'
            'S\trn3names\tc\tb\t[ミオ|みお|?]は、なまえを「[ミオ|みお|?]」とかきました。\t美绪把名字写作“ミオ”。\n'
            'Q\trn3names\ta\tだれがいますか。\tミオ\tだれもいない\tわからない\ta\tinformation\t最初の記述を確認します。\n')

    def compile(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'names.tsv'
            path.write_text(text)
            return compile_manuscript(path, self.pack)

    def merged(self, batch):
        pack = copy.deepcopy(self.pack)
        for key, values in batch.items():
            pack[key].extend(values)
        return pack

    def test_declared_names_remain_four_unknown_occurrences(self):
        batch = self.compile(self.manuscript())
        reading = batch['readings'][0]
        self.assertEqual(reading['properNames'], ['ミオ'])
        self.assertEqual(len(reading['vocabulary']), 4)
        self.assertTrue(all(w['properName'] is True and w['itemID'] is None for w in reading['vocabulary']))
        self.assertEqual([w for p in reading['paragraphs'] for w in p['vocabulary']], reading['vocabulary'])
        validate(self.merged(batch))

    def test_undeclared_unknown_is_not_promoted_to_a_name(self):
        batch = self.compile(self.manuscript(declaration=''))
        self.assertNotIn('properNames', batch['readings'][0])
        self.assertTrue(all('properName' not in w for w in batch['readings'][0]['vocabulary']))
        with self.assertRaisesRegex(AssertionError, 'untaught content word'):
            validate(self.merged(batch))

    def test_unused_wrong_reading_duplicate_and_orphan_declarations_fail(self):
        for declaration in ['P\trn3names\tミオ\tみう\n', 'P\trn3names\tカナ\tかな\n',
                'P\trn3names\tミオ\tみお\nP\trn3names\tミオ\tみお\n', 'P\tmissing\tミオ\tみお\n',
                'P\trn3names\t \tみお\n']:
            with self.subTest(declaration=declaration), self.assertRaises((AssertionError, ValueError)):
                self.compile(self.manuscript(declaration=declaration))

    def test_name_flags_need_a_declaration_and_cannot_hide_a_linked_word(self):
        batch = self.compile(self.manuscript())
        for changes in ['missing', 'duplicate', 'unused', 'linked', 'wrong_type']:
            pack = self.merged(batch)
            reading = pack['readings'][-1]
            if changes == 'missing': reading.pop('properNames')
            if changes == 'duplicate': reading['properNames'] = ['ミオ', 'ミオ']
            if changes == 'unused': reading['properNames'].append('カナ')
            if changes == 'linked': reading['vocabulary'][0]['itemID'] = 'v0001'
            if changes == 'wrong_type': reading['vocabulary'][0]['properName'] = 1
            with self.subTest(changes=changes), self.assertRaises(AssertionError):
                validate(pack)

    def test_legacy_beginner_unknowns_keep_their_existing_behavior(self):
        batch = self.compile(self.manuscript(declaration='', level='N5'))
        validate(self.merged(batch))
        self.assertNotIn('properNames', batch['readings'][0])

    def test_same_spelling_can_be_a_name_and_an_explicit_common_word(self):
        word = next(i for i in self.pack['items'] if i['kind'] == 'word' and i['text'] == '春')
        text = self.manuscript().replace('ミオ', word['text']).replace('みお', word['reading'])
        text = text.replace(f'[{word["text"]}|{word["reading"]}|?]」',
                            f'[{word["text"]}|{word["reading"]}|@{word["id"]}]」')
        reading = self.compile(text)['readings'][0]
        self.assertEqual(sum(w.get('properName') is True for w in reading['vocabulary']), 3)
        self.assertEqual(sum(w['itemID'] == word['id'] for w in reading['vocabulary']), 1)


if __name__ == '__main__':
    unittest.main()
