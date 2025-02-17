# Copyright (C) 2018-2019 Red Hat, Inc.
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
import testtools
try:
    from unittest import mock
except ImportError:
    import mock

from .zuul_azure_storage_upload import Uploader
from ..module_utils.zuul_jobs.upload_utils import FileDetail


FIXTURE_DIR = os.path.join(os.path.dirname(__file__),
                           'test-fixtures')


class FakeContainerClient:
    def __init__(self, url):
        self.url = url


class TestUpload(testtools.TestCase):

    def test_upload_result(self):
        client = mock.Mock()
        client.create_container.return_value = FakeContainerClient(
            'http://blob.example.com')
        uploader = Uploader(client=client, container="container",
                            prefix="123")

        # Get some test files to upload
        files = [
            FileDetail(
                os.path.join(FIXTURE_DIR, "logs/job-output.json"),
                "job-output.json",
            ),
            FileDetail(
                os.path.join(FIXTURE_DIR, "logs/zuul-info/inventory.yaml"),
                "inventory.yaml",
            ),
        ]

        uploader.upload(files)
        client.create_container.assert_called_with(
            'container', public_access='container')

        upload_calls = uploader.client.get_blob_client.mock_calls
        self.assertIn(
            mock.call(container='container', blob='123/job-output.json'),
            upload_calls)
        self.assertIn(
            mock.call(container='container', blob='123/inventory.yaml'),
            upload_calls)
        self.assertEqual(uploader.url, 'http://blob.example.com/123')
