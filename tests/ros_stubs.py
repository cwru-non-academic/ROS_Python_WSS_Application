"""Small ROS test doubles; these tests do not claim DDS or launch coverage."""
import sys
import types
from types import SimpleNamespace


class Logger:
    def __init__(self):
        self.messages = []

    def __getattr__(self, level):
        return lambda message: self.messages.append((level, message))


class Node:
    overrides = {}

    def __init__(self, name):
        self.name = name
        self.parameters = {}
        self.subscriptions = []
        self.logger = Logger()

    def declare_parameter(self, name, default):
        self.parameters[name] = self.overrides.get(name, default)

    def get_parameter(self, name):
        return SimpleNamespace(value=self.parameters[name])

    def get_name(self):
        return self.name

    def get_logger(self):
        return self.logger

    def create_subscription(self, message_type, topic, callback, depth):
        subscription = (message_type, topic, callback, depth)
        self.subscriptions.append(subscription)
        return subscription

    def destroy_node(self):
        return True


class Float64:
    def __init__(self, data=0.0):
        self.data = data


def install():
    for name in ("rclpy", "rclpy.node", "std_msgs", "std_msgs.msg"):
        sys.modules[name] = types.ModuleType(name)
    sys.modules["rclpy.node"].Node = Node
    sys.modules["std_msgs.msg"].Float64 = Float64
