# Copyright (C) 2019 VEXXHOST, Inc.
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

# Make coding more python3-ish
from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import os
import sys
import testtools

from .tox_install_sibling_packages import get_installed_packages
from .tox_install_sibling_packages import write_new_constraints_file


class TestToxInstallSiblingPackages(testtools.TestCase):
    def test_get_installed_packages(self):
        # NOTE(mnaser): Given that we run our tests inside Tox, we can
        #               leverage the tox virtual environment we use in
        #               unit tests instead of mocking up everything.
        pkgs = get_installed_packages(sys.executable)

        # NOTE(mnaser): requests should be installed in this virtualenv
        #               but this might fail later if we stop adding requests
        #               in the unit tests.
        self.assertIn("requests", pkgs)

    def test_write_new_constraints_file(self):
        # NOTE(mnaser): Given that we run our tests inside Tox, we can
        #               leverage the tox virtual environment we use in
        #               unit tests instead of mocking up everything.
        pkgs = get_installed_packages(sys.executable)

        # NOTE(mnaser): requests should be installed in this virtualenv
        #               but this might fail later if we stop adding requests
        #               in the unit tests.
        test_constraints = os.path.join(os.path.dirname(__file__),
                                        'test-constraints.txt')
        constraints = write_new_constraints_file(test_constraints, pkgs)

        def cleanup_constraints_file():
            if os.path.exists(constraints):
                os.unlink(constraints)
        self.addCleanup(cleanup_constraints_file)

        self.assertTrue(os.path.exists(constraints))
        with open(constraints) as f:
            s = f.read()
            self.assertNotIn("requests", s)
            self.assertIn("doesnotexistonpypi", s)
