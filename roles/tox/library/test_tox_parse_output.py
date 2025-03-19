# Copyright (C) 2020 VEXXHOST, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.

import os

import testtools

from tests import generate_dynamic_comments_tests
from .tox_parse_output import extract_file_comments

TESTS_DIR = os.path.join(os.path.dirname(__file__),
                         'test-cases')


class TestToxParseOutput(testtools.TestCase):
    pass


generate_dynamic_comments_tests(TestToxParseOutput, TESTS_DIR,
                                extract_file_comments)
