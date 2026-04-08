cmake_minimum_required(VERSION 3.5)
project(hfi_ros_wss_driver)

find_package(ament_cmake REQUIRED)
find_package(rclpy REQUIRED)
find_package(std_msgs REQUIRED)
find_package(ament_cmake_python REQUIRED)

ament_python_install_package(${PROJECT_NAME})

file(GLOB SCRIPT_FILES hfi_ros_wss_driver/*.py)
install(PROGRAMS ${SCRIPT_FILES}
  DESTINATION lib/${PROJECT_NAME}
)

file(GLOB SCRIPT_FILES scripts/*.py)
install(PROGRAMS ${SCRIPT_FILES}
  DESTINATION lib/${PROJECT_NAME}
)

file(GLOB LAUNCH_SCRIPTS launch/*.py)
install(PROGRAMS ${LAUNCH_SCRIPTS}
  DESTINATION share/${PROJECT_NAME}/launch
)

install(DIRECTORY launch/
  DESTINATION share/${PROJECT_NAME}/launch
  FILES_MATCHING PATTERN "*.launch" PATTERN "*.launch.py"
)

install(DIRECTORY config/
  DESTINATION share/${PROJECT_NAME}/config
  FILES_MATCHING PATTERN "*.yaml"
)

install(DIRECTORY Config/
  DESTINATION share/${PROJECT_NAME}/Config
  FILES_MATCHING PATTERN "*.json"
)

ament_package()
