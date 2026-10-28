#!/usr/bin/env python3

import rclpy

from hfi_ros_wss_driver.ros_wss_driver_node import RosWssDriverNode


def main(args=None):
    rclpy.init(args=args)

    node = None
    try:
        node = RosWssDriverNode()
        try:
            rclpy.spin(node)
        except Exception as e:
            print(e)
    finally:
        if node is not None:
            node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
