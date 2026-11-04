# HFI_ROS_WSS_Driver
A repository that maps incoming ROS2 stimulation magnitudes to the WSS stimulator.

## Table of Contents

- [Dependencies](#dependencies)
- [Setup Instructions](#setup-instructions)
- [Running the ROS WSS Driver](#running-the-ros-wss-driver)
- [Running Unit Tests](#running-unit-tests)
- [Debugging](#debugging)
- [Device addresses and setup diagnostics](#device-addresses-and-setup-diagnostics)
- [Maintainer reference](#maintainer-reference)
- [Dev beta acceptance receiver](#dev-beta-acceptance-receiver)
- [Test baseline](#test-baseline)

## Dependencies
The table below lists the direct dependencies needed for this repository.

| **Dependency Name** | **Description** |
|---------------------|-----------------|
| `rclpy` | ROS2 Python client library used for subscriptions, launch, and node lifecycle. |
| `std_msgs` | Provides the `Float64` message type used for stimulation magnitudes. |
| `HFI_WSS_Python_Interface` | Git submodule containing the Python WSS interface wrapper and bundled WSS DLLs. |

## Setup Instructions

### Software Setup

1. **Clone the Repository**:
   ```bash
   git clone --recurse-submodules git@github.com:cwru-non-academic/ROS_Python_WSS_Application.git
   cd ROS_Python_WSS_Application
   ```

2. **Install Dependencies**:
   Source your ROS2 environment and ensure `pythonnet` is available to the Python
   interpreter used by ROS. If it is not already installed, install the runtime
   prerequisite with that interpreter:

   ```bash
   python3 -m pip install -r requirements.txt
   ```

   A separate installation of `wss-py-wrapper` is no longer required. The build
   installs the pinned wrapper source and complete DLL payload together. Existing
   ROS/CLR environments can be reused; the CI development host versions below are
   not a new requirement to install a .NET SDK on the application computer.

3. **Review Driver Configuration**:
   Update `config/default_ros_wss_driver_params.yaml` as needed.
   The ROS2 YAML specifies:
   - the app-owned WSS `Config/` directory path
   - the log file path
   - the transport (`serial`, `ble`, `test`, or `conformance`) and serial port
   - explicit BLE selection by device name, device ID, or auto-selection
   - whether to use the wrapper test or conformance transport
   - the WSS setup retry count
   - the WSS tick interval in milliseconds
   - up to nine ROS topic names mapped to `ch1` through `ch9`

4. **Compile the Package**:
   Build the package using `colcon`:
   ```bash
   colcon build --packages-select hfi_ros_wss_driver --symlink-install
   source install/setup.bash
   ```

### Updating an existing checkout

Stop the running node, then use the normal update/rebuild sequence:

```bash
git pull
git submodule sync --recursive
git submodule update --init --recursive
colcon build --packages-select hfi_ros_wss_driver --symlink-install
source install/setup.bash
```

Plain `git pull` does not guarantee the checked-out submodule follows the new
gitlink. The update command selects the exact reviewed pin, not the newest
library branch. Restart the node after rebuilding; replacing WSS assemblies
inside a running process is unsupported. No existing publisher/client code needs
to change. Retain existing YAML and calibration paths; the example YAML's absolute
paths are examples for an existing installation, not portable defaults.

## Running the ROS WSS Driver

1. **Create and Edit Configuration File**:
   Modify `default_ros_wss_driver_params.yaml` as needed to set your desired parameters.

2. **Launch the Driver**:
   Execute the following command, specifying the path to your configuration file:
   ```bash
   ros2 launch hfi_ros_wss_driver launch_ros_wss_driver.launch.py
   ```

3. **Publish a Test Command**:
   For the default channel 2 mapping:
   ```bash
   ros2 topic pub /dom/index/stimulation_value std_msgs/msg/Float64 "{data: 0.5}" --once
   ```

Transport parameters are additive; existing YAML, topic names and publishers
continue to work. `transport` defaults to `serial`. For BLE set `transport: ble`
and one of `ble_device_name`, `ble_device_id`, or `ble_auto: true`. Empty BLE
selectors are rejected rather than silently scanning. BLE cannot be combined
with `serial_port`, `test_mode`, or `conformance_mode`.

`transport: test` and `transport: conformance` select Core's in-memory transports;
`test_mode: true` remains supported and `conformance_mode: true` is an equivalent
explicit flag. Unlike the CLI one-shot diagnostic, the ROS node remains running
with the application's configuration and topics in these modes. Use a suitable
WSS configuration for the emulated firmware. Conflicting simulated modes are
rejected before configuration files are changed or a controller is initialized.

The shared wrapper selects each OS's BLE backend, including the macOS managed
backend and paired native dylib, without a separate ROS BLE implementation.
Use `PYTHONNET_RUNTIME=coreclr` with a compatible installed CLR where needed.
This prepares the application transport path on macOS; native ROS Humble support
is tested only on Ubuntu 22.04. macOS platform checks double the ROS APIs and
exercise actual Core constructors, with no radio discovery or connection.

Incoming values are clamped to the range `[0.0, 1.0]` before being sent to `StimWithMode("chN", value)`.

## Running Unit Tests

Run the hardware-free contract/import/lifecycle tests from the repository root:

```bash
python3 -m unittest discover -s tests -v
```

ROS CI additionally builds with colcon on a **development baseline** of ROS 2
Humble / Ubuntu 22.04 x64, checks symlink and copied installs, resolves the same
launch command, and exercises all nine `Float64` topics through real rclpy/DDS
with a recording managed-layer double. It never opens a serial/BLE transport.
Separate Windows, Ubuntu and x64 macOS CPython 3.12 / pythonnet 3.0.5 / .NET 9
platform jobs test application contracts and the actual wrapper/Core model path
with Core's in-memory emulator, plus runtime/backend loading. Their ROS APIs are
doubled; native ROS coverage remains the separate Ubuntu/Humble job. See
[test baseline](#test-baseline) and [maintainer reference](#maintainer-reference).
These are development checks, not certification of every ROS distro or hardware.

The separate `ROS general conformance` Windows job executes the unchanged ten-case canonical NUnit corpus
through the same controller factory used by ROS node setup, preserving all
eighteen assertions. Its results, the separate model report and both native
layout reports form seven source-bound evidence files. Normal CI evidence is
not candidate approval: automatic promotion additionally requires the reviewed
v2 wrapper/CLI/ROS proof and a fresh preflight of the actual merged wrapper.
The three OS checks are named `ROS platform compatibility (Windows)`,
`ROS platform compatibility (Ubuntu)` and `ROS platform compatibility (macOS)`.
`ROS-specific compatibility (Humble)` retains the real colcon/DDS checks.
The declared macOS BLE payload is checked through the actual wrapper/backend
loading path, including BLE name/ID/auto routing. Missing declared backend files
fail the check; green platform checks do not claim physical BLE or native ROS
support on Windows/macOS. `ROS general conformance`
also verifies all suites and the existing promotion evidence format, so ordinary
PRs have five acceptance checks. `Stage verified ROS inputs` is a staging helper.
The unchanged candidate preflight retains its `ROS compatibility` acceptance name.

## Debugging

- Repo-owned WSS JSON configuration lives under `Config/`.
- The wrapper submodule remains at `HFI_WSS_Python_Interface/` and provides the Python package and `Cs_Libraries/` DLLs.
- `test_mode: true` switches the wrapper to its test transport instead of serial transport.
- `max_retries` defaults to `5` and `tick_interval_ms` defaults to `10`.
- The number of non-empty channel topics updates `Config/stimConfig.json` `maxWSS` automatically: 1-3 topics -> `1`, 4-6 topics -> `2`, 7-9 topics -> `3`.
- Leave a channel topic empty in the YAML to disable that channel subscription.
- The default example maps `/dom/index/stimulation_value` to `ch2`.
- Startup reports the selected wrapper file and DLL directory. Bundled wrapper
  code takes precedence over an unrelated pip installation. A different wrapper
  already imported in the process causes a clear restart error, not a hot swap.
- Deliberate external DLL selection remains possible with `WSS_CS_LIB_DIR=/path/to/Cs_Libraries`
  before launch, or the Python node constructor's optional `cs_lib_dir` keyword.
  The node honors it and warns that compatibility is unverified. It does not
  silently fall back, enforce a version/hash allowlist, alter calibration, or
  select another serial port. Load/initialization errors stop startup.
- The existing Core model-capacity limitation remains: `StimWithMode` sizes model
  state by device count rather than channel count. Existing nested model constants
  also retain their historical fallback behavior because Core looks up bare keys.
  Neither behavior is repaired by this compatibility change. Calibration or Core
  behavior corrections require their own review because output can change.

## Device addresses and setup diagnostics

`Config/stimConfig.json` exposes Core's receiver-address settings:
`broadcastTarget` defaults to `"0x8F"`, and `wssTargets` defaults to
`["0x81", "0x82", "0x83"]` for logical Wss1, Wss2 and Wss3. These are receiver
addresses, not the host sender byte. Set the targets for your actual device
configuration (for example, an installation may need `"0x80"` for Wss1).
Existing configurations without these fields use Core's historical defaults;
these template changes do not rewrite existing user configuration. Core keeps
its existing normalization behavior for invalid address values.
Keep the firmware and calibration values appropriate to your hardware.

After changing receiver addresses, stop and restart the application so Core
constructs a new address map. The CLI `reload-core` command does not rebuild that map.
Setup continues asynchronously after controller initialization. An initialized
application or an advancing tick loop does not establish that a device is ready.
Core setup and tick errors are recorded in the configured log file; check the
reported absolute config and log paths when diagnosing connection failures.

When the retained dependency payload is legacy and does not declare macOS BLE,
the platform probe asserts that explicit BLE selection is rejected and reports
it as unsupported. It does not count that as BLE construction or runtime proof.
A declared macOS backend missing either its managed DLL or native bridge always
fails; file absence alone never establishes legacy capability.

## Maintainer reference

<details>
<summary>CI, compatibility contracts, and historical provenance</summary>

Baseline commit `0cb18e0` captures ten passing contract tests before changes at
wrapper `60f29a8cf4c777bcc85d2f8d90da1abde46079ea`. Historical payload provenance selects
Python integration `94d78c49a622bd4d15587f869c4cd5ac063c13b8`, containing Core
`5ec22900587587e9e9465ffa53d04d7d1ce13545`. Its candidate manifest binds producer
run `39092192696`, artifact `12123267360`, archive SHA256
`3bc303096594978fa77e95cd80901a8fb72d26c42a7408c38c8668563b6f1a7e`.
`Verify-RosPayload.ps1` reuses the pinned library's canonical full-inventory and
digest checks. None of those checks is a runtime external-install allowlist.

The ROS package/executable, launch argument, parameter names/defaults, topic
mapping, Float64 type, depth 10 and clamp behavior are preserved. User JSON/YAML settings remain authoritative. NaN retains its historical clamp to 0, negative infinity to 0,
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
upgrade. These observations do not establish physical transport or hardware behavior.

### Versioned fan-out endpoints

This repository owns `ros-ci.yml` and ordinary acceptance job **ROS general
conformance**. Candidate preflight retains its **ROS compatibility** acceptance
name for the existing versioned promotion contract.
Endpoints are `wss-preflight.yml` with inputs `candidate_json`,
`wrapper_sha`, `ros_sha`, `correlation_id`, and `promote-integration.yml` with
`wrapper_sha`, `wrapper_pr`, `approval_json`. The gitlink remains
`HFI_WSS_Python_Interface`; the repository is
`cwru-non-academic/ROS_Python_WSS_Application`.

The implementation follows the [published v2 contract](https://github.com/cwru-non-academic/Python_WSS_Integration_Lib/blob/bb3bb0c3bb2caf5c1e0f6a9924d651b49c6467a6/.github/PYTHON_FANOUT_CONTRACT.md).
Ordinary CI pins shared receiver tools to
`94d78c49a622bd4d15587f869c4cd5ac063c13b8` (Python wrapper PR #8). Candidate preflight pins its tools to
`733d661baf2d259688fe0623bba0ae9adc1ce9ad`. Both pin the
macOS-aware shared C# fixture to `02172a64c55becd5535204f46f10b4755bf3ee05`
(C# PR #22). The immutable references identify the reviewed tools and fixture, independently of the application wrapper gitlink.
The canonical ten cases and eighteen assertions are unchanged.
Promotion deliberately uses reviewed tools on library `dev`, validates v2 proof
before target-only dispatch/write tokens, re-preflights the actual merged wrapper,
and permits only the `HFI_WSS_Python_Interface` gitlink change. A CLI-only v1
approval is rejected for ROS. No CLI approval is reused as ROS approval.
Evidence binds exact ROS/wrapper source SHAs,
candidate producer/artifact/archive tuple, full payload digest, development host
and runtime, fixture identities, independent model and ROS/layout results, and
result/log hashes. Canonical ten shared cases remain unchanged and separate;
they do not by themselves cover ROS callbacks or StimWithMode. Require successful
non-skipped ROS jobs, fresh post-merge wrapper validation, source race checks,
target-specific idempotency and human-reviewed gitlink-only PRs. Normal compatibility checks do not release or propagate Core.

The Windows job runs the exact ten canonical NUnit cases through
`create_controller`, the same production factory used by node setup. Only the
canonical fixture's controller factory/type alias changes; its eighteen assertion
expressions and all scenario values remain unchanged. ROS dependencies are
doubled in that embedded Python host. It supplements, rather than replaces, the
real-model and native ROS suites. The complete verified payload is transferred
by hash to the Humble job and installed as a fresh directory, never overlaid.

The `python-preflight-evidence` artifact contains exactly `evidence.json`,
`results.xml`, `dotnet.log`, `projection.json`, `ros-model.json`,
`ros-native-symlink.json`, and `ros-native-copy.json`. Shared validators check
report coverage and file hashes. Negative safety checks reject stale/tampered
reports, skipped model cases, incomplete model scenarios, missing DDS channels,
and CLI-only approvals. Ordinary CI produces the same evidence structure under
`ros-compatibility-evidence`, with mode `committed`; it is not a candidate approval.

A changed Core candidate must pass wrapper, CLI and ROS preflights and all v2
validators for end-to-end fan-out evidence. Ordinary green CI alone does not
establish that proof. Default/main and dev workflow deployments are reviewed
separately because closed-event fan-out checks out main.

### Separate conformance and platform checks

Ordinary PR and push CI on main/dev exposes these exact checks:

| Check | Executed scope |
| --- | --- |
| ROS general conformance | Windows embedded Python host; unchanged ten shared Core cases and eighteen assertions through the production ROS controller factory; ROS APIs doubled. Also assembles/verifies the existing seven-file source-bound proof and runs negative evidence checks after every platform/native suite succeeds |
| ROS platform compatibility (Windows) | Actual Python import/layout, public application contracts, lifecycle, five model tests/fifteen device-scenario observations; installed wrapper wheel, actual Ports selection/construction and shared C# Serial/BLE loading tests |
| ROS platform compatibility (Ubuntu) | The same application and wrapper platform checks on Ubuntu |
| ROS platform compatibility (macOS) | The same application and wrapper platform checks on x64 macOS; declared BLE backends are loaded and tested, while legacy payloads explicitly record unsupported BLE |
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
No native ROS test is skipped and relabeled as support on another OS. macOS BLE coverage depends on the selected payload's declared capabilities; legacy
payloads explicitly report it as unsupported while other platform checks execute.
No job opens a physical serial port or connects to a BLE device.

The canonical job no longer runs the model/contracts suite. Windows model evidence
comes from the Windows platform job, and native reports come from the native job;
the seven-file promotion format, source identities and payload hashes are retained
inside general conformance.

### macOS BLE payload validation

The shared validator accepts exactly the legacy 25-file inventory or the declared
27-file macOS BLE inventory; extra files, undeclared backends and missing declared
assets fail. Payload capability is determined from the selected wrapper's attested inventory,
not from historical commit notes. A green ordinary macOS job for a legacy payload
does not claim BLE support for that payload.

Candidate preflight runs ROS platform compatibility on Windows, Ubuntu and
macOS, in addition to the existing canonical/model and real Humble DDS suites.
Each platform resolves the exact canonical Core dev-push artifact independently,
checks producer provenance, and publishes source/run/hash-bound platform and
Python smoke reports. A declared macOS backend must pass ABI, inert context,
managed backend/factory and shared C# tests. No scan, connection or physical I/O
is performed. ROS APIs remain doubled in platform/model checks; real native ROS
coverage remains the separate Ubuntu 22.04/Humble suite.

Both native colcon layouts verify every installed payload byte against the
cross-job attested manifest, including the macOS dylib even on the Ubuntu host.
The existing directory installation rule already copies the complete payload.
Evidence assembly rejects mismatched installed counts, hashes or projection
digests. The legacy seven-file candidate proof format, v2 three-consumer proof
requirement and automatic CLI/ROS fan-out remain intact.

The five ordinary required check names remain:
- ROS general conformance
- ROS platform compatibility (Windows)
- ROS platform compatibility (Ubuntu)
- ROS platform compatibility (macOS)
- ROS-specific compatibility (Humble)

New-payload promotion requires reviewed receivers and a canonical Core dev-push
producer. PR artifacts cannot substitute for that provenance.

</details>

## Dev beta acceptance receiver

<details>
<summary>Read-only release reconciliation and immutable tooling</summary>

Implements the dev-only acceptance interface in WSSCore PR #28 at immutable
`be8546ca46256696bb366925b0094023d7cefc2c`. Main/stable publication remains disabled. All nine downstream targets, including
MATLAB, are required by the shared contract. This tooling never creates dependency PRs, merges them, or releases.

Receipt workflow and validator deployment on main and dev is required before
Core frozen-plan production. Closed-event fan-out checks out main, so a dev-only
workflow change does not update that control path. Reconciliation must use the
caller's actual merge and source rather than replaying an old closed-event run.

The reconciliation workflow accepts only `producer_run_id` and `plan_id`. It
downloads the unique frozen producer plan and exact ZIP, validates the reviewed
policy/digests, checks all producer gates, and requires exact current dev state.
Receipt code, normal CI and scripts must have the frozen Git IDs. A preparation
merge or no-op cannot become a `merged-pr` acceptance receipt.

The emitter is read-only. It invokes the existing v2 approval, source-scope,
archive checksum, strict 25/27-file projection, canonical 10-case/18-assertion,
platform, and ROS native validators. Applications additionally prove their actual
human-merged parent and fresh merged-wrapper preflight. Every original proof
source must match its frozen target snapshot. Latest actual-merge push/dispatch
CI must succeed; synthetic PR checkout CI cannot replace it. Core independently
rechecks the receipt, current branches, Git IDs, CI, dependency pins and emitter.

Successful preflights additionally upload `wss-candidate-provenance` with exactly
one six-string-field `candidate.json`. This is bound to their existing canonical
and projection evidence, and is uploaded only after all existing suites pass.
Rich Python/native/platform artifacts and all v2 validation remain intact.

An old preflight without that additional artifact is not release acceptance.
A fresh producer plan and proofs are required after tooling deployment. Earlier
candidate runs cannot substitute for a missing frozen plan, normalized proof,
no-op equivalence, or acceptance receipt.

Unit checks cover metadata binding, source/marker ambiguity, changed/no-op state,
exact required checks, non-human or wrong-source merges, latest-failed normal CI,
and disallowed transport writes. End-to-end acceptance requires a real frozen
plan and reviewed dependency merges after deployment; unit metadata is not proof.

The receipt workflow pins Python validator tools to
`88bca887cdd015ed439ce71edec9d022ffae460c`. Candidate preflight separately retains
`733d661baf2d259688fe0623bba0ae9adc1ce9ad`; these workflows have distinct tooling
contracts. The earlier seven-target receipt contract pin was
`de631fe4f1b80b5b4e2c6691f444625ef1730499` (WSSCore PR #18), retained here as
historical provenance rather than an active receipt contract.

</details>

## Test baseline

<details>
<summary>Historical baseline and retained model limitations</summary>

Before application changes or a pin upgrade, all ten tests in
`test_ros_contract.py` passed on Windows with CPython 3.12.13 against application
`aeae9b85fd42f37d3601e498c90047f68f40a89c` and wrapper
`60f29a8cf4c777bcc85d2f8d90da1abde46079ea`.

Run from the repository root: `python -m unittest discover -s tests -v`.

These tests use ROS doubles, the actual Python wrapper's `StimWithMode` method,
and a recording managed-layer double. They establish parameter/topic/clamping,
configuration, forwarding, and cleanup behavior; they do not establish DDS,
managed model calculations, CLR loading, physical transport, or hardware safety.
Nonfinite callback inputs retain the existing behavior: NaN and negative infinity
map to 0, positive infinity maps to 1.

The known Core model-capacity issue is a separate compatibility limitation:
`ModelParamsLayer` sizes its model state by device count rather than channel
count. The baseline records this limitation without changing Core behavior. Regression checks should identify that
limitation explicitly rather than describe zero model magnitude as desired
channel behavior. Existing topic-count-based device selection is also retained.

</details>
