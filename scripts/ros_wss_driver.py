#!/usr/bin/env python3

import rclpy
from rclpy.executors import ExternalShutdownException

from hfi_ros_wss_driver.ros_wss_driver_node import RosWssDriverNode


def main(args=None):
    rclpy.init(args=args)

    node = None
    try:
        node = RosWssDriverNode()
        try:
            rclpy.spin(node)
        except (KeyboardInterrupt, ExternalShutdownException):
            pass
        except Exception as e:
            print(e)
    finally:
        try:
            if node is not None:
                node.destroy_node()
        finally:
            rclpy.try_shutdown()


if __name__ == "__main__":
    main()
