# ROS compatibility work and pipeline handoff

Baseline commit `0cb18e0` captures ten passing contract tests before changes at
wrapper `60f29a8cf4c777bcc85d2f8d90da1abde46079ea`. The complete pin now selects
Python integration `b527733d0c3fb213a515cd5a3e7b4a0d66b461c0`, containing Core
`5ec22900587587e9e9465ffa53d04d7d1ce13545`. Its candidate manifest binds producer
run `39092192696`, artifact `12123267360`, archive SHA256
`3bc303096594978fa77e95cd80901a8fb72d26c42a7408c38c8668563b6f1a7e`.
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

This repository owns `ros-ci.yml` and acceptance job **ROS compatibility**.
Endpoints are `wss-preflight.yml` with inputs `candidate_json`,
`wrapper_sha`, `ros_sha`, `correlation_id`, and `promote-integration.yml` with
`wrapper_sha`, `wrapper_pr`, `approval_json`. The gitlink remains
`HFI_WSS_Python_Interface`; the repository is
`cwru-non-academic/ROS_Python_WSS_Application`.

The implementation follows the [published v2 contract](https://github.com/cwru-non-academic/Python_WSS_Integration_Lib/blob/bb3bb0c3bb2caf5c1e0f6a9924d651b49c6467a6/.github/PYTHON_FANOUT_CONTRACT.md).
Normal CI and candidate preflight pin their validators to that exact commit.
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
target-specific idempotency and human-reviewed gitlink-only PRs. No merge/release
or final Core propagation experiment is authorized by these checks.

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

Deployment remains separate: publish these workflows to default `main` and the
routine `dev` branch through reviewed human merges, and provide existing App
capabilities. A genuine changed Core candidate must pass wrapper, CLI and ROS
preflights and all v2 validators before any full fan-out success can be claimed.
Authored endpoints or normal green CI do not establish that end-to-end proof.
