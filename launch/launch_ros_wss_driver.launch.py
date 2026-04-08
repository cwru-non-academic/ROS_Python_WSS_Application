import os

import yaml
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def load_yaml_file(file_path):
    print(f"Loading configuration from: {file_path}")

    with open(file_path, "r") as file:
        return yaml.safe_load(file)


def launch_setup(context, *args, **kwargs):
    config_file_name = LaunchConfiguration("config_file").perform(context)

    config_directory = os.path.join(
        get_package_share_directory("hfi_ros_wss_driver"),
        "config",
    )
    config_file_path = os.path.join(config_directory, config_file_name)

    config_params = load_yaml_file(config_file_path)

    node_name = config_params.get("node_name", "ros_wss_driver_node")

    return [
        Node(
            package="hfi_ros_wss_driver",
            executable="ros_wss_driver.py",
            name=node_name,
            output="screen",
            emulate_tty=True,
            parameters=[config_params],
        ),
    ]


def generate_launch_description():
    config_file_arg = DeclareLaunchArgument(
        "config_file",
        default_value="default_ros_wss_driver_params.yaml",
        description="Name of the YAML config file (located in the /config directory)",
    )

    return LaunchDescription(
        [
            config_file_arg,
            OpaqueFunction(function=launch_setup),
        ]
    )


if __name__ == "__main__":
    generate_launch_description()
