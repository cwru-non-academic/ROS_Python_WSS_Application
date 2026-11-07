# Ordinary ROS tooling separation

Ordinary ROS CI binds a separate immutable Python tooling checkout and its common
`.github/python-ci.json`; actual ROS and wrapper checkouts remain untouched.
The expected tooling SHA is read from all five literal `path: tools` checkouts in
`ros-ci.yml`, which remain owned by the existing Core adapter-pin refresh. A
mutable ref, differing pins, missing checkouts, dirty/wrong tooling SHA or a
configuration path from any other checkout fails closed. No new independent pin
or test-selection setting is introduced.

The actual ROS `HFI_WSS_Python_Interface` gitlink must equal the wrapper SHA.
Ordinary tests cannot silently substitute a modern wrapper for a legacy product.
Payload inventory and hashes are verified before metadata selects the reviewed
legacy 10-case/18-assertion baseline or modern single16 + multi16/20-assertion
baseline. Modern ordinary execution always runs both stages. Canonical fixture
bytes and profile classification come from reviewed tooling, not selected tests.
The ROS production factory, application and runtime modules come from actual ROS
and wrapper sources. Disposable staging does not rewrite those sources.

The ordinary profile evidence schema is distinct from candidate-promotion
acceptance. It binds source, immutable tooling/config, producer, fixture and result
hashes. Independent model, native symlink/copy ROS, full installed payload and all
OS/native-architecture jobs remain mandatory. Projection JSON is copied byte for
byte so native cross-job record hashes remain valid. Existing candidate workflow,
selected isolated children/baseline snapshots and release-receipt gates are not
changed. No selection is activated by this change.

## Local validation

- Actual ROS main cdae5bbb with its6073e38 wrapper and Core76803: complete legacy10.
- Actual dev/#40 ROS5d2a888 with its1d50e745 wrapper and Core50af: complete legacy10.
- Same independently bound Python tooling4c398a5 and common config for both.
- Windows installed-wheel/native-loader/full-payload,23 ROS contracts, five model
  tests/fifteen observations and actual Core transport constructor checks.
- Wrong tooling root/config/SHA, mutable/divergent pins, and substituted product
  wrapper rejected. Existing selected source/isolation tests retained.
- Modern16+16 is a local synthetic paired-product fixture proof only, not evidence
  that actual dev/main have adopted a new wrapper. Synthetic fixture is not pushed.

Native Humble colcon/DDS, Linux, macOS Intel/ARM and complete source/run-bound
native acceptance must still pass hosted CI after the supported tooling refresh.
The old literal7df83 pin intentionally remains until the reviewed shared bootstrap
has matching dev/main identity and an immutable published anchor. Do not publish
this workflow as ready or replace the pin merely to turn a check green.