ARG ROS_DISTRO=noetic
FROM ros:${ROS_DISTRO}-ros-base
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-lc"]

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    python3-pip \
    python3-colcon-common-extensions \
    nlohmann-json3-dev \
    libpcl-dev \
    libyaml-cpp-dev \
    libtbb-dev \
    ros-${ROS_DISTRO}-pcl-ros \
    ros-${ROS_DISTRO}-eigen-conversions \
    ros-${ROS_DISTRO}-tf2-eigen \
    ros-${ROS_DISTRO}-rosbag
RUN pip3 install rosbags
RUN mkdir -p /test_ws/src
COPY src/ /test_ws/src

# faster-lio submodule may be empty if not initialized on host.
# Clone it directly if the package.xml is missing.
RUN if [ ! -f /test_ws/src/faster-lio/package.xml ]; then \
      rm -rf /test_ws/src/faster-lio && \
      git clone --depth 1 https://github.com/gaoxiang12/faster-lio.git /test_ws/src/faster-lio; \
    fi

# Ensure LASzip submodule is present for the converter
RUN if [ ! -f /test_ws/src/faster-lio-to-hdmapping/src/3rdparty/LASzip/CMakeLists.txt ]; then \
      mkdir -p /test_ws/src/faster-lio-to-hdmapping/src/3rdparty && \
      rm -rf /test_ws/src/faster-lio-to-hdmapping/src/3rdparty/LASzip && \
      git clone --depth 1 --branch 3.4.3 https://github.com/LASzip/LASzip.git /test_ws/src/faster-lio-to-hdmapping/src/3rdparty/LASzip; \
    fi

RUN if [ ! -f /test_ws/src/livox_ros_driver/package.xml ]; then rm -rf /test_ws/src/livox_ros_driver && git clone https://github.com/Livox-SDK/livox_ros_driver.git /test_ws/src/livox_ros_driver; fi
RUN cd /test_ws && \
    source /opt/ros/${ROS_DISTRO}/setup.bash && \
    rosdep update && \
    rosdep install --from-paths src --ignore-src -r -y || true && \
    source /opt/ros/${ROS_DISTRO}/setup.bash && \
    colcon build
