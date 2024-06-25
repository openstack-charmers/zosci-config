# Copyright 2022 Canonical Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import copy
import mock
import tempfile
import unittest

import process_func_test_pr

TEST_MESSAGE = """
Update to build using charmcraft

Due to a build problem with the reactive plugin, this change falls back
on overriding the steps and doing a manual build, but it also ensures
the CI system builds the charm using charmcraft.  Changes:

- add a build-requirements.txt
- modify charmcraft.yaml
- modify osci.yaml
    -> indicate build with charmcraft
- modify tox.ini
    -> tox -e build does charmcraft build/rename
    -> tox -e build-reactive does the reactive build
- modify bundles to use the <charm>.charm artifact in tests.
  and fix deprecation warning re: prefix
- tox inception to enable tox -e func-test in the CI
- Unit test fix

Func-test-pr: https://github.com/charmers/zaza-tests/pull/723
Func-test-pr: https://github.com/charmers/zaza/pull/499
Depends-On: https://review.opendev.org/c/openstack/charm-keystone/+/830986
Depends-On: https://review.opendev.org/c/openstack/interface-keystone/+/830988
Change-Id: Iadd11634d1fe44731ecf0a6104561b4aeebff23f
"""
DEFAULT_LOCATIONS_MAIN = """
git+https://github.com/charmers/zaza.git#egg=zaza
git+https://github.com/charmers/zaza-tests.git#egg=zaza.openstack
"""
DEFAULT_LOCATIONS_STABLE_BRANCHES = """
git+https://github.com/charmers/zaza.git@stable/xena#egg=zaza
git+https://github.com/charmers/zaza-tests.git@stable/xena#egg=zaza.openstack
"""
API_GITHUB_RESPONSES = {
    '723': {
        'head': {
            'label': 'gnuoy:bug/1964117',
            'ref': 'bug/1964117',
            'repo': {'name': 'zaza-tests'},
            'sha': '4fcf8d2c7a5b99528806103daffd7eeeac5d161f'}},
    '499': {
        'head': {
            'label': 'gnuoy:bug/some-bug',
            'ref': 'bug/some-bug',
            'repo': {'name': 'zaza'},
            'sha': '4fcf8d2c7a33333333333333333333333333'}}}


class TestProcessFuncTestPR(unittest.TestCase):

    def test_parser(self):
        args = process_func_test_pr.parse_args([
            '-f', 'file1',
            '-f', 'file2',
            'My Message'])
        self.assertEqual(args.file, ['file1', 'file2'])
        self.assertEqual(args.commit_message, 'My Message')

    def test_extract_lines(self):
        self.assertEqual(
            process_func_test_pr.extract_lines(TEST_MESSAGE, 'Im not there'),
            [])
        self.assertEqual(
            process_func_test_pr.extract_lines(TEST_MESSAGE, 'Change-Id'),
            ["Change-Id: Iadd11634d1fe44731ecf0a6104561b4aeebff23f"])
        self.assertEqual(
            process_func_test_pr.extract_lines(
                TEST_MESSAGE,
                r'.*(Unit test fi|add a build).*'),
            ['- add a build-requirements.txt',
             '- Unit test fix'])

    def test_apply_updates(self):
        with tempfile.TemporaryDirectory() as tmpdirname:
            file1 = '{}/file1.txt'.format(tmpdirname)
            with open(file1, 'w') as f:
                f.write("Yo, hit me with some biscuits and gravy")
            process_func_test_pr.apply_updates(
                [
                    ('Im not there', 'foo'),
                    ('Yo,', 'Good morning,'),
                    (r'hit.*with', 'please may I have'),
                    ('some ', ''),
                    (r'bis.*vy', 'a savoury scone with Béchamel sauce')],
                [file1])
            with open(file1, 'r') as f:
                contents = f.read()
            self.assertEqual(
                contents,
                ('Good morning, please may I have a savoury scone with '
                 'Béchamel sauce'))

    def test_apply_updates_globbed(self):
        with tempfile.TemporaryDirectory() as tmpdirname:
            file1 = '{}/file.txt'.format(tmpdirname)
            file2 = '{}/file2.txt'.format(tmpdirname)
            globbed_name = '{}/file*.txt'.format(tmpdirname)
            with open(file1, 'w') as f:
                f.write("Yo, hit me with some biscuits and gravy")
            with open(file2, 'w') as f:
                f.write("Yo, hit me with some biscuits and gravy")
            process_func_test_pr.apply_updates(
                [
                    ('Im not there', 'foo'),
                    ('Yo,', 'Good morning,'),
                    (r'hit.*with', 'please may I have'),
                    ('some ', ''),
                    (r'bis.*vy', 'a savoury scone with Béchamel sauce')],
                [globbed_name])
            with open(file1, 'r') as f:
                contents = f.read()
            self.assertEqual(
                contents,
                ('Good morning, please may I have a savoury scone with '
                 'Béchamel sauce'))
            with open(file2, 'r') as f:
                contents = f.read()
            self.assertEqual(
                contents,
                ('Good morning, please may I have a savoury scone with '
                 'Béchamel sauce'))

    @mock.patch.object(process_func_test_pr.requests, 'get')
    def _test_process_func_test_pr(self, locations, mock_get):
        with tempfile.TemporaryDirectory() as tmpdirname:
            def fake_get(url):
                key = url.split('/')[-1]
                rq_mock = mock.MagicMock()
                rq_mock.json.return_value = API_GITHUB_RESPONSES[key]
                return rq_mock
            mock_get.side_effect = fake_get
            file1 = '{}/file1.txt'.format(tmpdirname)
            with open(file1, 'w') as f:
                f.write(locations)
            process_func_test_pr.process_func_test_pr(
                TEST_MESSAGE,
                [file1])
            with open(file1, 'r') as f:
                contents = f.readlines()
            contents = [c.strip() for c in contents if c != '\n']
            self.assertEqual(
                contents,
                ['git+https://github.com/gnuoy/zaza.git@bug/some-bug#egg=zaza',  # noqa: E501
                 'git+https://github.com/gnuoy/zaza-tests.git@bug/1964117#egg=zaza.openstack'])  # noqa: E501

    def test_process_func_test_pr_main_branch(self):
        self._test_process_func_test_pr(DEFAULT_LOCATIONS_MAIN)

    def test_process_func_test_pr_stable_branches(self):
        self._test_process_func_test_pr(DEFAULT_LOCATIONS_STABLE_BRANCHES)

    @mock.patch.object(process_func_test_pr.requests, 'get')
    def _test_process_func_test_pr_different_fork_name(
        self, locations, api_response, mock_get
    ):
        with tempfile.TemporaryDirectory() as tmpdirname:
            def fake_get(url):
                key = url.split('/')[-1]
                rq_mock = mock.MagicMock()
                rq_mock.json.return_value = api_response[key]
                return rq_mock
            mock_get.side_effect = fake_get
            file1 = '{}/file1.txt'.format(tmpdirname)
            with open(file1, 'w') as f:
                f.write(locations)
            process_func_test_pr.process_func_test_pr(
                TEST_MESSAGE,
                [file1])
            with open(file1, 'r') as f:
                contents = f.readlines()
            contents = [c.strip() for c in contents if c != '\n']
            self.assertEqual(
                contents,
                ['git+https://github.com/gnuoy/zaza-1.git@bug/some-bug#egg=zaza',  # noqa: E501
                 'git+https://github.com/gnuoy/zaza-tests-1.git@bug/1964117#egg=zaza.openstack'])  # noqa: E501

    def test_process_func_test_pr_main_branch_different_fork_name(self):
        github_responses = copy.deepcopy(API_GITHUB_RESPONSES)
        github_responses['723']['head']['repo']['name'] = 'zaza-tests-1'
        github_responses['499']['head']['repo']['name'] = 'zaza-1'
        self._test_process_func_test_pr_different_fork_name(
            DEFAULT_LOCATIONS_MAIN, github_responses
        )

    def test_process_func_test_pr_stable_branches_different_fork_name(self):
        github_responses = copy.deepcopy(API_GITHUB_RESPONSES)
        github_responses['723']['head']['repo']['name'] = 'zaza-tests-1'
        github_responses['499']['head']['repo']['name'] = 'zaza-1'
        self._test_process_func_test_pr_different_fork_name(
            DEFAULT_LOCATIONS_STABLE_BRANCHES, github_responses
        )
