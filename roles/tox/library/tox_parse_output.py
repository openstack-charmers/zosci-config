# Copyright (c) 2018 Red Hat
#
# This module is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this software.  If not, see <http://www.gnu.org/licenses/>.
from __future__ import absolute_import, division, print_function
__metaclass__ = type

DOCUMENTATION = '''
---
module: tox_parse_output
short_description: Parses the output of tox looking for per-line comments
author: Monty Taylor (@mordred)
description:
  - Looks for output from the tox command to find content that could be
    returned as inline comments.
requirements:
  - "python >= 3.5"
options:
  tox_output:
    description:
      - Output from the tox command run
    required: true
    type: str
'''

import os
import re

from ansible.module_utils.basic import AnsibleModule

ANSI_RE = re.compile(r'(?:\x1B[@-_]|[\x80-\x9F])[0-?]*[ -/]*[@-~]')
PEP8_RE = re.compile(r"^(.*):(\d+):(\d+): (.*)$")
SPHINX_RE = re.compile(r"^([^:]*):([\d]+):(\w.+)$")


def simple_matcher(line, regex, file_path_group, start_line_group,
                   message_group):
    m = regex.match(line)
    file_path = None
    start_line = None
    message = None
    if m:
        file_path = m.group(file_path_group)
        start_line = m.group(start_line_group)
        message = m.group(message_group)
    return file_path, start_line, message


def pep8_matcher(line):
    return simple_matcher(line, PEP8_RE, 1, 2, 4)


def sphinx_matcher(line):
    return simple_matcher(line, SPHINX_RE, 1, 2, 3)


matchers = [
    pep8_matcher,
    sphinx_matcher,
]


def extract_line_comment(line):
    """
    Extracts line comment data from a line using multiple matchers.
    """
    file_path = None
    start_line = None
    message = None

    for matcher in matchers:
        file_path, start_line, message = matcher(line)
        if file_path:
            message = ANSI_RE.sub('', message)
            break

    return file_path, start_line, message


def extract_file_comments(tox_output, workdir, tox_envlist=None):
    os.chdir(workdir)
    ret = {}
    for line in tox_output.split('\n'):
        if not line:
            continue
        if line[0].isspace():
            continue
        file_path, start_line, message = extract_line_comment(line)
        if not file_path:
            continue
        # Clean up the file path if it has a leading ./
        if file_path.startswith('./'):
            file_path = file_path[2:]
        # Don't report if the file path isn't valid
        if not os.path.isfile(file_path):
            continue

        # Strip current working dir to make absolute paths relative
        cwd = os.getcwd() + '/'
        if file_path.startswith(cwd):
            file_path = file_path[len(cwd):]

        # After stripping we don't allow absolute paths anymore since they
        # cannot be linked to a file in the repo in zuul.
        if file_path.startswith('/'):
            continue

        # We should only handle files that are in under version control.
        # For now, skip .tox directory, we can enhance later.
        if file_path.startswith('.tox'):
            continue
        # This library is shared with the nox role.
        if file_path.startswith('.nox'):
            continue

        ret.setdefault(file_path, [])
        if tox_envlist:
            message = "{envlist}: {message}".format(
                envlist=tox_envlist,
                message=message,
            )
        ret[file_path].append(dict(
            line=int(start_line),
            message=message,
        ))
    return ret


def main():
    module = AnsibleModule(
        argument_spec=dict(
            tox_output=dict(required=True, type='str', no_log=True),
            tox_envlist=dict(required=True, type='str'),
            workdir=dict(required=True, type='str'),
        )
    )
    tox_output = module.params['tox_output']
    tox_envlist = module.params['tox_envlist']

    file_comments = extract_file_comments(
        tox_output, module.params['workdir'], tox_envlist)
    module.exit_json(changed=False, file_comments=file_comments)


if __name__ == '__main__':
    main()
