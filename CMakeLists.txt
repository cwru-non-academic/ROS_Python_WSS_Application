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

# Install wrapper code and the complete pinned payload together. Neither a
# separately pip-installed wrapper nor the source checkout is needed at launch.
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/HFI_WSS_Python_Interface/src/wss_py_wrapper/__init__.py")
  message(FATAL_ERROR "Initialize the pinned HFI_WSS_Python_Interface submodule before building")
endif()
install(DIRECTORY HFI_WSS_Python_Interface/src/wss_py_wrapper
  DESTINATION share/${PROJECT_NAME}/HFI_WSS_Python_Interface/src
  FILES_MATCHING PATTERN "*.py"
  PATTERN "__pycache__" EXCLUDE
)
install(DIRECTORY HFI_WSS_Python_Interface/Cs_Libraries/
  DESTINATION share/${PROJECT_NAME}/HFI_WSS_Python_Interface/Cs_Libraries
)

ament_package()
