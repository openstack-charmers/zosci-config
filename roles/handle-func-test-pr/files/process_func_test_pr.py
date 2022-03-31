#!/usr/bin/env python3

import argparse
import base64
import os
import re
import requests
import sys
from urllib.parse import urlparse


def parse_args(args):
    """Parse command line arguments.

    :param args: Command arguments
    :type list: [str1, str2,...] List of command line arguments
    :returns: Parsed arguments
    :rtype: Namespace
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--file', action='append',
                        help='File to update',
                        required=True)
    parser.add_argument('commit_message', type=str,
                        help='Commit message to process')
    return parser.parse_args(args)


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


def main():
    args = parse_args(sys.argv[1:])
    process_commit(args.commit_message, args.file)


if __name__ == '__main__':
    sys.exit(main())
