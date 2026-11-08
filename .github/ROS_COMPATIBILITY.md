# ROS compatibility work and pipeline handoff

Baseline commit `0cb18e0` captures ten passing contract tests before changes at
wrapper `60f29a8cf4c777bcc85d2f8d90da1abde46079ea`. That initial receiver rollout
selected Python integration `94d78c49a622bd4d15587f869c4cd5ac063c13b8`, containing Core
`5ec22900587587e9e9465ffa53d04d7d1ce13545`. Its candidate manifest binds producer
run `39092192696`, artifact `12123267360`, archive SHA256
`3bc303096594978fa77e95cd80901a8fb72d26c42a7408c38c8668563b6f1a7e`.
Those identities record the initial rollout, not current acceptance. The current
product comes from the committed `HFI_WSS_Python_Interface` gitlink and its
candidate manifest; workflow-owned tooling pins are separate.
`Verify-RosPayload.ps1` reuses the pinned library's canonical full-inventory and
digest checks. None of those checks is a runtime external-install allowlist.

The ROS package/executable, launch argument, parameter names/defaults, topic
mapping, Float64 type, depth 10 and clamp behavior are preserved. JSON/YAML files
are not changed. NaN retains its historical clamp to 0, negative infinity to 0,
positive infinity to 1. User-selected config/calibration paths remain authoritative.

Internal behavior changes:

- Select bundled Python source before import, rather than silently accepting a
  copied pip installation. Reject already-imported conflicting Python modules or
  WSS assemblies; require a fresh process rather than attempting replacement.
- Install wrapper code and the entire pinned payload into the ROS share tree;
  resolve copied installs through the ament index, symlink installs through the
  source tree. Missing source submodules fail explicitly.
- Honor deliberate external DLL selection with a warning and no fallback.
- Clean up partially initialized controllers and ROS context on startup failure,
  and propagate initialization failure as a process error.
- Keep application subscription references in `_channel_subscriptions`, avoiding
  collision with rclpy's own `_subscriptions` collection and double registration.

The real-model suite runs production node callbacks, production Python wrapper
and managed Core using **only EmulatedWssTransport**. H03 uses Core's legacy
emulator profile; J03 uses the query-capable profile. P/PD and PW/PA fixtures cover
1/2/3 devices and all configured channels, calibration persistence, nonfinite
inputs, successful Core initialization conformance, and tick-thread shutdown.
The ROS layer is doubled in this suite. DDS/colcon/layout checks are separate.

Known model limitations are observations, not desired output or hidden xfails:
channels outside the historical model array can yield zero normalized magnitude.
The suite accepts the intended calibrated result, or explicitly records only
that characterized capacity limitation. Other output deviations fail. A future
reviewed Core correction can remove the limitation without rewriting the desired
output assertions. The current Core also queries bare model constant keys while
the app example nests constants; deterministic PD fixtures include explicit root
overrides without changing production configuration. Both issues predate this pin
upgrade. No Core fix, hardware configuration change, or physical safety claim is
included here.

## Versioned fan-out endpoints

This repository owns `ros-ci.yml` and ordinary acceptance job **ROS general
conformance**. Candidate preflight retains its **ROS compatibility** acceptance
name for the existing versioned promotion contract.
Endpoints are `wss-preflight.yml` with inputs `candidate_json`,
`wrapper_sha`, `ros_sha`, `correlation_id`, and `promote-integration.yml` with
`wrapper_sha`, `wrapper_pr`, `approval_json`. The gitlink remains
`HFI_WSS_Python_Interface`; the repository is
`cwru-non-academic/ROS_Python_WSS_Application`.

The implementation follows the [published v2 contract](https://github.com/cwru-non-academic/Python_WSS_Integration_Lib/blob/bb3bb0c3bb2caf5c1e0f6a9924d651b49c6467a6/.github/PYTHON_FANOUT_CONTRACT.md).
The initial v2 receiver pinned shared tools to
`94d78c49a622bd4d15587f869c4cd5ac063c13b8` (Python wrapper PR #8), and the
macOS-aware shared C# fixture to `02172a64c55becd5535204f46f10b4755bf3ee05`
(C# PR #22), retaining the legacy ten cases and eighteen assertions. Those
identities are historical. Current candidate and ordinary workflows declare
their reviewed tooling pins explicitly. Ordinary CI resolves canonical fixtures
and required coverage from the verified payload capability profile; the product
gitlink does not select tooling.
Promotion deliberately uses reviewed tools on library `dev`, validates v2 proof
before target-only dispatch/write tokens, re-preflights the actual merged wrapper,
and permits only the `HFI_WSS_Python_Interface` gitlink change. A CLI-only v1
approval is rejected for ROS. No CLI approval is reused as ROS approval.
Evidence binds exact ROS/wrapper source SHAs,
candidate producer/artifact/archive tuple, full payload digest, development host
and runtime, fixture identities, independent model and ROS/layout results, and
result/log hashes. Canonical profile cases remain unchanged and separate;
they do not by themselves cover ROS callbacks or StimWithMode. Require successful
non-skipped ROS jobs, fresh post-merge wrapper validation, source race checks,
target-specific idempotency and human-reviewed gitlink-only PRs. No merge/release
or final Core propagation experiment is authorized by these checks.

The canonical Windows runners execute the verified profile's NUnit corpus through
`create_controller`, the same production factory used by node setup. Only the
fixture's controller factory/type alias changes; its canonical cases, assertion
expressions and scenario values remain preserved. The retained legacy runner has
its original single-device corpus; layered coverage requires both single-device
and multi-device stages. ROS dependencies are doubled in that embedded Python
host. It supplements, rather than replaces, the real-model and native ROS suites.
The complete verified payload is transferred by hash to the Humble job and
installed as a fresh directory, never overlaid.

The retained legacy evidence schema contains `evidence.json`, `results.xml`,
`dotnet.log`, `projection.json`, `ros-model.json`, `ros-native-symlink.json`, and
`ros-native-copy.json`. Layered evidence additionally requires the canonical
evidence/result/log/projection files under `multi/`. Current candidate preflight
runs `Invoke-LayeredRosConformance.ps1` and `Complete-LayeredRosEvidence.ps1`;
ordinary CI runs `Invoke-ProfiledRosConformance.ps1` and
`Complete-ProfiledRosEvidence.ps1` and requires the verified profile's complete
inventory. Shared validators check report coverage and file hashes; negative
checks reject stale/tampered reports, skipped model cases, incomplete model
scenarios, missing DDS channels and CLI-only approvals. Candidate and ordinary
artifacts remain `python-preflight-evidence` and `ros-compatibility-evidence`
respectively; ordinary `committed` evidence is not candidate approval.

Deployment remains separate: publish these workflows to default `main` and the
routine `dev` branch through reviewed human merges, and provide existing App
capabilities. A genuine changed Core candidate must pass wrapper, CLI and ROS
preflights and all v2 validators before any full fan-out success can be claimed.
Authored endpoints or normal green CI do not establish that end-to-end proof.

## Separate conformance and platform checks

Ordinary PR and push CI on main/dev exposes these exact checks:

| Check | Executed scope |
| --- | --- |
| ROS general conformance | Windows embedded Python host; profile-selected canonical corpus preserving cases and assertions through the production ROS controller factory; ROS APIs doubled. Also assembles/verifies the complete profile-specific source-bound evidence and runs negative checks after every platform/native suite succeeds |
| ROS platform compatibility (Windows) | Actual Python import/layout, public application contracts, lifecycle, five model tests/fifteen device-scenario observations; installed wrapper wheel, actual Ports selection/construction and shared C# Serial/BLE loading tests |
| ROS platform compatibility (Ubuntu) | The same application and wrapper platform checks on Ubuntu |
| ROS platform compatibility (macOS) | Aggregate of native Intel (x64) and Apple Silicon (arm64) consumer lanes, with actual wrapper/backend checks for the verified payload; no physical BLE or native ROS claim |
| ROS-specific compatibility (Humble) | Actual colcon symlink/copy installs, launch resolution and all nine Float64 topics through native rclpy/DDS on Ubuntu 22.04/Humble; recording managed-layer double, no CLR or transport |

These are the five checks intended for the ordinary PR ruleset. `Stage verified
ROS inputs` is a helper job that verifies the committed wrapper/source and full
payload, then transfers the hashed payload to the native job. Platform/native
jobs depend on that helper; general conformance waits for their success and
executes both the canonical tests and evidence validation. This avoids a cycle
without adding a sixth ordinary acceptance context. Failure/skip of any required
dependency makes general conformance fail. Ordinary CI has no separate
`ROS compatibility` job; that name remains only in the unchanged candidate
preflight workflow.

The platform jobs execute real application/Core model logic with ROS API doubles;
they do not install or certify native ROS on Windows or macOS. The separate native
Ubuntu/Humble check is required to establish the existing ROS development baseline.
No native ROS test is skipped and relabeled as support on another OS. Declared
macOS BLE payloads must pass backend/runtime checks on both native architectures;
a verified legacy payload reports explicit unsupported BLE selection rather than
implying support. No job opens a physical serial port or connects to a BLE device.

The canonical job no longer runs the model/contracts suite. Windows model evidence
comes from the Windows platform job, and native reports come from the native job;
the profile-specific complete evidence inventory, source identities and payload
hashes are retained inside general conformance.
The candidate-preflight workflow, dispatch/fan-out endpoints, public application
interface, configuration and Core behavior remain unchanged.

## macOS BLE receiver preparation

The shared validator accepts exactly the legacy 25-file inventory or the declared
27-file macOS BLE inventory; extra files, undeclared backends and missing declared
assets fail. A verified legacy payload must report explicit unsupported BLE
selection. A payload declaring macOS BLE must include and validate its managed
backend and native bridge; missing declared files are failures, never evidence
of legacy capability.

Candidate preflight now runs ROS platform compatibility on Windows, Ubuntu and
macOS, in addition to the existing canonical/model and real Humble DDS suites.
Each platform independently resolves the exact canonical Core push artifact for
the configured channel, checks producer provenance, and publishes source/run/hash-bound platform and
Python smoke reports. A declared macOS backend must pass ABI, inert context,
managed backend/factory and shared C# tests. No scan, connection or physical I/O
is performed. ROS APIs remain doubled in platform/model checks; real native ROS
coverage remains the separate Ubuntu 22.04/Humble suite.

Both native colcon layouts verify every installed payload byte against the
cross-job attested manifest, including the macOS dylib even on the Ubuntu host.
The existing directory installation rule already copies the complete payload.
Evidence assembly rejects mismatched installed counts, hashes or projection
digests. The retained legacy evidence schema, v2 three-consumer proof requirement
and automatic CLI/ROS fan-out remain intact; current layered candidate preflight
additionally requires its complete multi-device evidence.

The five ordinary required check names remain:
- ROS general conformance
- ROS platform compatibility (Windows)
- ROS platform compatibility (Ubuntu)
- ROS platform compatibility (macOS)
- ROS-specific compatibility (Humble)

New-payload promotion waits for reviewed receivers and a canonical Core producer
for the configured channel. PR artifacts cannot substitute for that provenance.
