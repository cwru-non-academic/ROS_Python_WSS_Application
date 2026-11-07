"""Trusted test-only staging and full-inventory runner. Never imports selected build controls."""
import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import unittest

FILES = ['tests/test_payload_verification.py', 'tests/test_ros_contract.py', 'tests/test_runtime_selection.py']

def contract(root):
    value = json.loads((root / 'conformance/test-contract.json').read_text(encoding='utf-8-sig'))
    if set(value) != {'schema', 'adapter', 'fixtures', 'test_files', 'expected_cases'} or value['schema'] != 'wss-ros-tests/v1':
        raise ValueError('Invalid versioned ROS test-only manifest')
    if value['adapter'] != 'conformance/RosConformanceAdapter.cs' or value['fixtures'] != ['tests/ros_stubs.py'] or value['test_files'] != FILES:
        raise ValueError('Only explicit ROS test files and adapter are allowed')
    cases = value['expected_cases']
    if not isinstance(cases, list) or not cases or any(not isinstance(c, str) for c in cases) or len(cases) != len(set(cases)):
        raise ValueError('Expected full unique nonempty test inventory')
    # Reject selected symlinks as well as files escaping the frozen tree.
    for relative in ['conformance/test-contract.json', value['adapter'], *value['fixtures'], *FILES]:
        path = root / relative
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('Selected test source must be a regular file inside its checkout')
    return value

def archive(root, destination, *paths):
    raw = subprocess.check_output(['git', '-C', str(root), 'archive', 'HEAD', '--', *paths])
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(raw)) as bundle:
        for member in bundle.getmembers():
            if not (member.isfile() or member.isdir()) or not (destination / member.name).resolve().is_relative_to(destination.resolve()):
                raise ValueError('Non-regular or escaping archive entry')
        bundle.extractall(destination, filter='data')

def flatten(suite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from flatten(item)
        else:
            yield item

def run(application, expected, output):
    os.chdir(application)
    sys.path[:0] = [str(application / 'tests'), str(application)]
    suite = unittest.TestSuite(unittest.defaultTestLoader.discover(str(application / 'tests'), pattern=Path(f).name) for f in FILES)
    discovered = [case.id() for case in flatten(suite)]
    if sorted(discovered) != sorted(expected) or len(discovered) != len(set(discovered)):
        raise ValueError(f'Selected discovered inventory differs: {discovered}')
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful() or result.skipped or result.expectedFailures or result.testsRun != len(expected):
        raise ValueError('Every listed selected test must execute and pass, without skips/expected failures')
    output.write_text(json.dumps({'schema': 'wss-ros-own-tests/v1', 'discovered': discovered, 'executed': result.testsRun, 'passed': result.testsRun, 'skipped': 0}, indent=2) + '\n')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['validate', 'run'])
    parser.add_argument('--tests', type=Path, required=True)
    parser.add_argument('--ros', type=Path)
    parser.add_argument('--wrapper', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    value = contract(args.tests)
    if args.operation == 'validate':
        print(json.dumps(value))
        return
    if not args.ros or not args.wrapper or not args.output or args.output.exists():
        raise ValueError('Explicit products and new output root required')
    args.output.mkdir(parents=True)
    app = args.output / 'application'
    archive(args.ros, app, 'hfi_ros_wss_driver', 'scripts', 'package.xml')
    archive(args.wrapper, app / 'HFI_WSS_Python_Interface', 'src')
    (app / 'tests').mkdir()
    for relative in [*value['fixtures'], *value['test_files']]:
        (app / relative).write_bytes((args.tests / relative).read_bytes())
    run(app.resolve(), value['expected_cases'], (args.output / 'results.json').resolve())

if __name__ == '__main__':
    main()
