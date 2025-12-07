# faster-lio-converter

## Example Dataset: 

Download the dataset from [Bunker DVI Dataset](https://charleshamesse.github.io/bunker-dvi-dataset/)  

## Intended use 

This small toolset allows to integrate SLAM solution provided by [faster-lio](https://github.com/gaoxiang12/faster-lio) with [HDMapping](https://github.com/MapsHD/HDMapping).
This repository contains ROS 1 workspace that :
  - submodule to tested revision of faster-lio
  - a converter that listens to topics advertised from odometry node and save data in format compatible with HDMapping.

## Dependecies
```shell
sudo apt install nlohmann-json3-dev
sudo apt install libgoogle-glog-dev
```

## livox_ros_driver

```shell
git clone https://github.com/Livox-SDK/livox_ros_driver.git ws_livox/src
cd ws_livox
catkin_make

Use the following command to update the current ROS package environment :

source ./devel/setup.sh
```
## Building

Clone the repo
```shell
mkdir -p /test_ws/src
cd /test_ws/src
git clone https://github.com/marcinmatecki/Faster-LIO-to-hdmapping.git --recursive
cd ..
catkin_make
```

## Usage - data SLAM:

Prepare recorded bag with estimated odometry:

In first terminal record bag:
```shell
rosbag record /cloud_registered /Odometry
```

and start odometry:
```shell 
cd /test_ws/
source ./devel/setup.sh # adjust to used shell
roslaunch faster_lio mapping_avia.launch
rosbag play your bag file
```

## Usage - conversion:

```shell
cd /test_ws/
source ./devel/setup.sh # adjust to used shell
rosrun faster-lio-to-hdmapping listener <recorded_bag> <output_dir>
```

## Modify
```shell
src/Faster-LIO-to-HDMapping/src/faster-lio/config/ouster64.yaml

lid_topic: "/os_cloud_node/points"
imu_topic: "/os_cloud_node/imu"

to

lid_topic: "/os1_cloud_node1/points"
imu_topic: "/os1_cloud_node1/imu"
```

## Record the bag file:

```shell
rosbag record /cloud_registered /Odometry
```

## Faster LIO Launch:

```shell
cd /test_ws/
source ./devel/setup.sh # adjust to used shell
roslaunch faster_lio mapping_ouster64.launch
rosbag play {path_to_bag}
```

## During the record (if you want to stop recording earlier) / after finishing the bag:

```shell
In the terminal where the ros record is, interrupt the recording by CTRL+C
Do it also in ros launch terminal by CTRL+C.
```

## Usage - Conversion (ROS bag to HDMapping, after recording stops):

```shell
cd /test_ws/
source ./devel/setup.sh # adjust to used shell
rosrun faster-lio-to-hdmapping listener <recorded_bag> <output_dir>
```
