# Copyright (C) 2018-2019 Red Hat, Inc.
# Copyright (C) 2021-2022 Acme Gating, LLC
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

from .zuul_ibm_upload import Uploader
from ..module_utils.zuul_jobs.upload_utils import FileDetail


FIXTURE_DIR = os.path.join(os.path.dirname(__file__),
                           'test-fixtures')


class TestUpload(testtools.TestCase):

    def test_upload_result(self):
        client = mock.Mock()
        uploader = Uploader(client=client, bucket="bucket",
                            endpoint_url='http://example.com')

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
        client.put_bucket_cors.assert_called_with(
            Bucket='bucket',
            CORSConfiguration={
                'CORSRules': [{
                    'AllowedMethods': ['GET', 'HEAD'],
                    'AllowedOrigins': ['*']}]
            })

        upload_calls = uploader.client.upload_fileobj.mock_calls
        upload_call_filenames = [x[1][2] for x in upload_calls]
        self.assertIn('job-output.json', upload_call_filenames)
        self.assertIn('inventory.yaml', upload_call_filenames)
