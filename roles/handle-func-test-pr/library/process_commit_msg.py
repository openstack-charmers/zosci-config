#!/usr/bin/env python3

import base64
import os
import hashlib
import pathlib
import re
import requests
from urllib.parse import urlparse

from ansible.module_utils.basic import AnsibleModule

__metaclass__ = type

DOCUMENTATION = r'''
---
module: process_commit_msg

short_description: Read commit message and perform any actions
'''

EXAMPLES = r'''
# Update requrements files based on commit message
- name: Process commit message
  process_commit_msg:
    commit_message: "{{ zm.content }}"
    files:
      - /home/ubuntu/charm-mycharm/test-requirements.txt
      - /home/ubuntu/charm-mycharm/src/test-requirements.txt
'''

RETURN = r'''
# Example of possible return value
message:
    description: The output message that the test module generates.
    type: str
    returned: always
    sample: 'Updated Files: /home/ubuntu/charm-mycharm/test-requirements.txt'
'''


def extract_lines(commit_message, match_pattern):
    """Extract lines for commit message matching pattern

    :param commit_message: Commit Message
    :type commit_message: str
    :param match_pattern: Pattern to search for
    :type match_pattern: str
    :returns: Matching lines
    :rtype: List[str]"""
    lines = []
    for line in commit_message.split('\n'):
        if re.match(match_pattern, line, flags=re.IGNORECASE):
            lines.append(line)
    return lines


def apply_updates(updates, files):
    """Update contents of files with supplied replacements.

    :param updates: List of replacement tuples (pattern, repl)
    :type updates: List[(str, str)]
    :param files: List of file names.
    :type files: List[str]
    """
    for file_name in files:
        if not os.path.exists(file_name):
            print("{} not found".format(file_name))
            continue
        with open(file_name, "r+") as f:
            contents = f.read()
            for update in updates:
                print("Applying update {} {} to {}".format(
                    update[0],
                    update[1],
                    file_name))
                contents = re.sub(
                    update[0],
                    update[1],
                    contents,
                    flags=re.MULTILINE)
            f.seek(0)
            f.write(contents)
            f.truncate()


def process_func_test_pr(commit_message, files):
    """Apply any func-test-pr directives to files.

    :param commit_message: Commit Message
    :type commit_message: str
    :param files: List of file names.
    :type files: List[str]
    """
    lines = extract_lines(commit_message, 'func-test-pr')
    # regex to check stable branches in the git url
    # eg: @stable/xena#egg=zaza.openstack, @stable/xena
    stable_branch_regex = r'[@\S]*?(?=[#\n])'
    updates = []
    for line in lines:
        pr_url = urlparse(line.split()[-1])
        _r = re.sub('/pull/.*', '', pr_url.path)
        _r = re.sub('^/', '', _r)
        pr_org, pr_repo = _r.split('/')
        pr_number = re.sub('.*/pull/', '', pr_url.path)
        api_url = "https://api.github.com/repos/{}/{}/pulls/{}".format(
            pr_org,
            pr_repo,
            pr_number)
        request = requests.get(api_url)
        pr_label = request.json()['head']['label']
        pr_login, pr_branch = pr_label.split(':')
        updates.append((
            "{}/{}.git{}".format(pr_org, pr_repo, stable_branch_regex),
            "{}/{}.git@{}".format(pr_login, pr_repo, pr_branch)))
    apply_updates(updates, files)


def process_commit(encoded_commit_message, files):
    """Apply all update functions to files.

    :param encoded_commit_message: Base64 encoded commit message
    :type encoded_commit_message: str
    :param files: List of file names.
    :type files: List[str]
    """
    process_funcs = [process_func_test_pr]
    commit_message = base64.b64decode(encoded_commit_message).decode()
    for func in process_funcs:
        func(commit_message, files)


def get_file_hash(file_loc):
    """Calculate a hash for the file contents.

    :param files: File path
    :type files: pathlib.Path
    :returns: File hash
    :rtype: str
    """
    return hashlib.md5(file_loc.read_bytes()).hexdigest()


def get_files_hashes(files):
    """Calculate a has for the contents of each file.

    :param files: List of file names.
    :type files: List[str]
    :returns: File hashes
    :rtype: Dict[str]
    """
    hashes = {}
    for f in files:
        file_loc = pathlib.Path(f)
        if file_loc.exists():
            hashes[f] = get_file_hash(file_loc)
    return hashes


def run_module():
    module_args = dict(
        files=dict(type='list', required=True),
        commit_message=dict(type='str', required=True)
    )

    result = dict(
        changed=False,
        message=''
    )

    module = AnsibleModule(
        argument_spec=module_args,
        supports_check_mode=True
    )

    if module.check_mode:
        module.exit_json(**result)

    old_hashes = get_files_hashes(module.params['files'])

    process_commit(
        module.params['commit_message'],
        module.params['files'])

    new_hashes = get_files_hashes(module.params['files'])
    changed_files = [f for f, h in old_hashes.items() if h != new_hashes[f]]

    if changed_files:
        result['changed'] = True
        result['message'] = 'Updated Files: {}'.format(','.join(changed_files))
    else:
        result['changed'] = False
        result['message'] = 'No files updated'

    module.exit_json(**result)


def main():
    run_module()


if __name__ == '__main__':
    main()
