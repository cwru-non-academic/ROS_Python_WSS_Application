# ROS compatibility baseline

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
count. This change does not repair it. Regression checks should identify that
limitation explicitly rather than describe zero model magnitude as desired
channel behavior. Existing topic-count-based device selection is also retained.
