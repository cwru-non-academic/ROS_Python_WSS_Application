# Inactive selected ROS test integration

This fragment is documentation, not an active workflow. Do not enable it until the
reviewed full WSSCore tooling checkout includes durable run-context recovery and
the declared ROS canonical fixture agrees with the authenticated payload profile.
The current wss-ci.lock.json deliberately remains unchanged.

## Immutable boundaries

The trusted source workflow checks out the complete locked Core repository, never a
flat copy of ci-test-selection.mjs. The selected repository has no authority over
workflow YAML, build scripts, product configuration, ROS source, wrapper source,
canonical fixture source, or payload choice. Only conformance/test-contract.json,
its explicit C# adapter, ROS stub and three Python test modules enter selected runs.
Selected gitlinks stay uninitialized. Every initialized product submodule must have
its own exact declaration in roots.json, matching its parent gitlink SHA.

Invoke-SelectedRosTestsWithContext.ps1 authenticates python-ros via Core inspect,
starts a separate credential-free PowerShell process, and requests Core evidence
only after all tests pass. The child receives neither parent PowerShell variables,
authentication-token environment variables nor GitHub command-file handles. Core
rechecks all exact product/test identities after execution. Syntax-valid IDs alone
are not authorization. Direct local child runs are diagnostics, not authenticated
selection acceptance evidence.

The child runs mandatory canonical ROS conformance, then repeats it with the
selected adapter/stub, then executes the entire 23-case selected Python inventory.
Legacy fixture contracts run 10 canonical cases; modern contracts run 16 single-
and 16 multi-device cases. The trusted metadata-only capability checker first verifies the complete projection,
recognizes only the reviewed legacy producer or complete modern capabilities, and
requires the actual canonical fixture contract to match. Selection-enabled campaign
contexts require modern 16+16 coverage. Unknown legacy producers, partial modern
APIs and fixture/profile mismatches fail closed; no suite downgrade is allowed.

The trusted preparers preserve exact canonical fixture digest and assertion checks.
They do not execute selected Prepare*.ps1 files. The Python runner archives exact
actual ROS product modules/scripts/package.xml and exact wrapper src into a fresh
mirror, then adds only the listed test files. Selected .github, product source,
configuration and build controls are never copied or executed. The original roots
are not changed. Every listed test must be discovered, executed and passed, with
zero skips or expected failures. All generated output stays outside source roots.

Existing native Humble/colcon, installed-layout DDS, transport/model, macOS and
platform gates remain unchanged and mandatory. These local tests do not demonstrate
native ROS CI. Selection evidence alone is not release authority.

## Durable prerequisite wiring

Use the adjacent inactive fragment after supplying the existing workflow's verified
source, wrapper, fixture, product candidate and full locked Core checkouts. The
prepare step calls `select`, uploads the context with overwrite disabled, then the
load step authenticates the stored artifact before publishing selection outputs.
Only load outputs may select the test checkout or be passed to downstream jobs.
On a rerun Core recovers the original context, never silently resolves latest again.
No failed prerequisite, absent context or authentication error may fall back to a
fresh selection. Candidate mode uses the existing authenticated candidate JSON;
ordinary PR mode can use `-` as already defined by Core.

Construct roots.json outside sources with selection_id, test_root and products
(repository, commit, path). Products include the exact actual ROS run SHA, wrapper
SHA, canonical fixture SHA and every initialized product gitlink. ToolsRoot currently
must equal the declared wrapper product root, so no undeclared tooling is accepted.
Call the trusted source's bridge with CoreRoot, ContextPath, RootsPath, WorkRoot,
ToolsRoot, and the unchanged committed/candidate resolver options. Publish selection
and test results as additional artifacts, never as replacements for existing proofs.

## Local checks

- `python -I -B .github/scripts/tests/test_selected_ros_runner.py`
- `pwsh -NoProfile -File .github/scripts/tests/Test-RosSelectedContext.ps1`
- Local child: Invoke-SelectedRosTests.ps1 with explicit actual products, fixture,
  selected TestRoot, pinned Python 3.12/pythonnet 3.0.5 and .NET SDK 9.0.316.
- Full authenticated bridge testing waits for the reviewed published Core lock.
