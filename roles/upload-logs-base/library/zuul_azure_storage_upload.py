# Copyright 2014 Rackspace Australia
# Copyright 2018-2019 Red Hat, Inc
# Copyright 2021 Acme Gating, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# Make coding more python3-ish
from __future__ import (absolute_import, division, print_function)
__metaclass__ = type


"""
Utility to upload files to Azure

Run this from the CLI from the zuul-jobs/roles directory with:

  python -m upload-logs-base.library.zuul_azure_storage_upload
"""

import argparse
import logging
import os
try:
    import queue as queuelib
except ImportError:
    import Queue as queuelib
import sys
import threading

from azure.storage.blob import (
    BlobServiceClient, CorsRule, ContentSettings

)
from azure.core.exceptions import ResourceExistsError

from ansible.module_utils.basic import AnsibleModule

try:
    # Ansible context
    from ansible.module_utils.zuul_jobs.upload_utils import (
        FileList,
        GZIPCompressedStream,
        Indexer,
        retry_function,
    )
except ImportError:
    # Test context
    from ..module_utils.zuul_jobs.upload_utils import (
        FileList,
        GZIPCompressedStream,
        Indexer,
        retry_function,
    )

MAX_UPLOAD_THREADS = 24


class Uploader():
    def __init__(self, client, container, prefix=None,
                 public=True, dry_run=False):

        self.dry_run = dry_run
        if dry_run:
            self.url = 'https://example.com/a/path/'
            return

        self.client = client
        self.prefix = prefix or ''
        self.container = container

        if public:
            public = 'container'
        else:
            public = None
        try:
            cc = client.create_container(container, public_access=public)
        except ResourceExistsError:
            cc = client.get_container_client(container)

        cors_rule = CorsRule(['*'], ['GET', 'HEAD'])
        cors = [cors_rule]

        client.set_service_properties(cors=cors)

        self.url = os.path.join(cc.url, self.prefix)

    def upload(self, file_list):
        """Spin up thread pool to upload to storage"""

        if self.dry_run:
            return

        num_threads = min(len(file_list), MAX_UPLOAD_THREADS)
        threads = []
        queue = queuelib.Queue()
        # add items to queue
        for f in file_list:
            queue.put(f)

        for x in range(num_threads):
            t = threading.Thread(target=self.post_thread, args=(queue,))
            threads.append(t)
            t.start()

        for t in threads:
            t.join()

    def post_thread(self, queue):
        while True:
            try:
                file_detail = queue.get_nowait()
                logging.debug("%s: processing job %s",
                              threading.current_thread(),
                              file_detail)
                retry_function(lambda: self._post_file(file_detail))
            except IOError:
                # Do our best to attempt to upload all the files
                logging.exception("Error opening file")
                continue
            except queuelib.Empty:
                # No more work to do
                return

    @staticmethod
    def _is_text_type(mimetype):
        # We want to compress all text types.
        if mimetype.startswith('text/'):
            return True

        # Further compress types that typically contain text but are no
        # text sub type.
        compress_types = [
            'application/json',
            'image/svg+xml',
        ]
        if mimetype in compress_types:
            return True
        return False

    def _post_file(self, file_detail):
        relative_path = os.path.join(self.prefix, file_detail.relative_path)
        content_encoding = None

        if file_detail.folder:
            # We don't need to upload folders to Azure
            return

        if (file_detail.encoding is None and
            self._is_text_type(file_detail.mimetype)):
            content_encoding = 'gzip'
            data = GZIPCompressedStream(open(file_detail.full_path, 'rb'))
        else:
            if (not file_detail.filename.endswith(".gz") and
                file_detail.encoding):
                # Don't apply gzip encoding to files that we receive as
                # already gzipped. The reason for this is storage will
                # serve this back to users as an uncompressed file if they
                # don't set an accept-encoding that includes gzip. This
                # can cause problems when the desired file state is
                # compressed as with .tar.gz tarballs.
                content_encoding = file_detail.encoding
            data = open(file_detail.full_path, 'rb')

        blob = self.client.get_blob_client(container=self.container,
                                           blob=relative_path)
        content_settings = ContentSettings(
            content_type=file_detail.mimetype,
            content_encoding=content_encoding)
        blob.upload_blob(data)
        blob.set_http_headers(content_settings)


def run(container, files,
        indexes=True, parent_links=True, topdir_parent_link=False,
        partition=False, footer='index_footer.html',
        prefix=None, public=True, dry_run=False, connection_string=None):

    client = BlobServiceClient.from_connection_string(connection_string)

    if prefix:
        prefix = prefix.lstrip('/')
    if partition and prefix:
        parts = prefix.split('/')
        if len(parts) > 1:
            container += '_' + parts[0]
            prefix = '/'.join(parts[1:])

    # Create the objects to make sure the arguments are sound.
    with FileList() as file_list:
        # Scan the files.
        for file_path in files:
            file_list.add(file_path)

        indexer = Indexer(file_list)

        # (Possibly) make indexes.
        if indexes:
            indexer.make_indexes(create_parent_links=parent_links,
                                 create_topdir_parent_link=topdir_parent_link,
                                 append_footer=footer)

        logging.debug("List of files prepared to upload:")
        for x in file_list:
            logging.debug(x)

        # Upload.
        uploader = Uploader(client, container, prefix, public, dry_run)
        uploader.upload(file_list)
        return uploader.url


def ansible_main():
    module = AnsibleModule(
        argument_spec=dict(
            container=dict(required=True, type='str'),
            files=dict(required=True, type='list'),
            partition=dict(type='bool', default=False),
            indexes=dict(type='bool', default=True),
            parent_links=dict(type='bool', default=True),
            topdir_parent_link=dict(type='bool', default=False),
            public=dict(type='bool', default=True),
            footer=dict(type='str'),
            prefix=dict(type='str'),
            connection_string=dict(type='str'),
        )
    )

    p = module.params
    url = run(p.get('container'), p.get('files'),
              indexes=p.get('indexes'),
              parent_links=p.get('parent_links'),
              topdir_parent_link=p.get('topdir_parent_link'),
              partition=p.get('partition'),
              footer=p.get('footer'),
              prefix=p.get('prefix'),
              public=p.get('public'),
              connection_string=p.get('connection_string'))
    module.exit_json(changed=True,
                     url=url)


def cli_main():
    parser = argparse.ArgumentParser(
        description="Upload files to Azure Storage"
    )
    parser.add_argument('--verbose', action='store_true',
                        help='show debug information')
    parser.add_argument('--no-indexes', action='store_true',
                        help='do not generate any indexes at all')
    parser.add_argument('--no-parent-links', action='store_true',
                        help='do not include links back to a parent dir')
    parser.add_argument('--create-topdir-parent-link', action='store_true',
                        help='include a link in the root directory of the '
                             'files to the parent directory which may be the '
                             'index of all results')
    parser.add_argument('--no-public', action='store_true',
                        help='do not create the container as public')
    parser.add_argument('--partition', action='store_true',
                        help='partition the prefix into multiple containers')
    parser.add_argument('--append-footer', default='index_footer.html',
                        help='when generating an index, if the given file is '
                             'present in a directory, append it to the index '
                             '(set to "none" to disable)')
    parser.add_argument('--prefix',
                        help='Prepend this path to the object names when '
                             'uploading')
    parser.add_argument('--dry-run', action='store_true',
                        help='do not attempt to create containers or upload, '
                             'useful with --verbose for debugging')
    parser.add_argument('--connection-string',
                        help='An Azure access key connection string')
    parser.add_argument('container',
                        help='Name of the container to use when uploading')
    parser.add_argument('files', nargs='+',
                        help='the file(s) to upload with recursive glob '
                        'matching when supplied as a string')

    args = parser.parse_args()

    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)
        logging.captureWarnings(True)

    append_footer = args.append_footer
    if append_footer.lower() == 'none':
        append_footer = None

    url = run(args.container, args.files,
              indexes=not args.no_indexes,
              parent_links=not args.no_parent_links,
              topdir_parent_link=args.create_topdir_parent_link,
              partition=args.partition,
              footer=append_footer,
              prefix=args.prefix,
              public=not args.no_public,
              dry_run=args.dry_run,
              connection_string=args.connection_string)
    print(url)


if __name__ == '__main__':
    # The zip/ansible/modules check is required for Ansible 5 because
    # stdin may be a tty, but does not work in ansible 2.8.  The tty
    # check works on versions 2.8, 2.9, and 6.
    if ('.zip/ansible/modules' in sys.argv[0] or not sys.stdin.isatty()):
        ansible_main()
    else:
        cli_main()
