FROM ubuntu:20.04

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg2 lsb-release software-properties-common sudo \
    build-essential git cmake \
    python3-pip \
    libceres-dev libeigen3-dev \
    libpcl-dev \
    nlohmann-json3-dev \
    libusb-1.0-0-dev \
    tmux \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros/ubuntu $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/ros1.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-noetic-desktop-full \
    python3-rosdep \
    python3-catkin-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone https://github.com/Livox-SDK/Livox-SDK.git && \
    cd Livox-SDK && \
    rm -rf build && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make -j$(nproc) && \
    make install

WORKDIR /ws_livox

RUN mkdir -p src

WORKDIR /ws_livox/src

RUN git clone https://github.com/Livox-SDK/livox_ros_driver.git

WORKDIR /ws_livox

RUN source /opt/ros/noetic/setup.bash && \
    catkin_make

WORKDIR /ros_ws

COPY ./src ./src
COPY ./tools ./tools

# Oxford Spires (Hesai Pandar + Alphasense IMU): no native Hesai handler
# upstream (AviaHandler reads livox_ros_driver::CustomMsg directly, no PC2
# path). The dataset is pre-converted offline (see
# tools/offline_hesai_to_velodyne.py, runnable inside this image) into a
# PointCloud2 layout matching velodyne_ros::Point
# (x,y,z,intensity,time[us],ring), played on /velodyne_points + /imu_data.
# lidar_type is already 2 (VELO32, the ring/time-aware handler) in
# config/velodyne.yaml -- only the topic names need to change.
RUN sed -i \
    -e 's|lid_topic:.*|lid_topic:  "/velodyne_points"|' \
    -e 's|imu_topic:.*|imu_topic:  "/imu_data"|' \
    src/faster-lio/config/velodyne.yaml

RUN python3 -m pip install --no-cache-dir rosbags numpy

RUN source /opt/ros/noetic/setup.bash && \
    source /ws_livox/devel/setup.bash && \
    catkin_make
    
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID ros && \
    useradd -m -u $UID -g $GID -s /bin/bash ros
    
WORKDIR /ros_ws

RUN echo "source /opt/ros/noetic/setup.bash" >> ~/.bashrc && \
    echo "source /ws_livox/devel/setup.bash" && >> ~/.bashrc \
    echo "source /ros_ws/devel/setup.bash" >> ~/.bashrc

CMD ["bash"]
