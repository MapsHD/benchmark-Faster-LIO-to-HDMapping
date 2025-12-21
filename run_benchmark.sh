#!/bin/bash

# run_benchmark.sh - Reusable benchmark runner for Faster-LIO (ROS1)
# Usage: ./run_benchmark.sh <config_name> <input_ros1_bag_file>
#
# Example:
#   ./run_benchmark.sh avia /path/to/data/Pipes/AVIA/ros1bag/mandeye.bag

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
CONFIG_NAME="${1:-}"
INPUT_BAG_FILE="${2:-}"

# Function to show usage
usage() {
    echo "Usage: $0 <config_name> <input_ros1_bag_file>"
    echo ""
    echo "Arguments:"
    echo "  config_name         Name of config file in configs/ (e.g., 'avia')"
    echo "  input_ros1_bag_file Path to ROS1 .bag file"
    echo ""
    echo "Available configs:"
    ls -1 "${SCRIPT_DIR}/configs/" 2>/dev/null | grep "\.env$" | sed 's/\.env$//' | sed 's/^/  - /' || echo "  (none)"
    exit 1
}

# Validate arguments
if [ -z "$CONFIG_NAME" ] || [ -z "$INPUT_BAG_FILE" ]; then
    usage
fi

# Check if config file exists
CONFIG_FILE="${SCRIPT_DIR}/configs/${CONFIG_NAME}.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    echo ""
    echo "Available configs:"
    ls -1 "${SCRIPT_DIR}/configs/" 2>/dev/null | grep "\.env$" | sed 's/\.env$//' | sed 's/^/  - /' || echo "  (none)"
    exit 1
fi

# Check if input bag exists
INPUT_BAG_FILE="$(realpath -m "$INPUT_BAG_FILE")"
if [ ! -f "$INPUT_BAG_FILE" ]; then
    echo "Error: Input bag file not found: $INPUT_BAG_FILE"
    exit 1
fi

# Load config and export variables
echo "Loading config: $CONFIG_FILE"
set -a
source "$CONFIG_FILE"
set +a

INPUT_BAG_DIR="$(dirname "$INPUT_BAG_FILE")"
INPUT_BAG_NAME="$(basename "$INPUT_BAG_FILE")"
EXP_DIR="$(realpath "$(dirname "$INPUT_BAG_DIR")")"
OUTPUT_DIR_ABS="${EXP_DIR}/results/${OUTPUT_DIR}"

echo "=========================================="
echo "Running Faster-LIO benchmark (ROS1)"
echo "Config: $CONFIG_NAME"
echo "Input bag: $INPUT_BAG_FILE"
echo "Input lidar topic: $INPUT_LIDAR_TOPIC"
echo "Input imu topic: $INPUT_IMU_TOPIC"
echo "Output directory: $OUTPUT_DIR_ABS"
echo "=========================================="

mkdir -p "$OUTPUT_DIR_ABS"

# Image expected to contain Faster-LIO + converter.
# Override with FASTERLIO_IMAGE env var for local builds.
IMAGE="${FASTERLIO_IMAGE:-ghcr.io/mapshd/fasterlio2hdmapping:latest}"

docker run --rm -t \
    -u $(id -u):$(id -g) \
    -e HOME=/tmp \
    -e ROS_HOME=/tmp/.ros \
    -v "${INPUT_BAG_DIR}:/data:ro" \
    -v "${EXP_DIR}:/exp:rw" \
    "${IMAGE}" \
    bash -lc "
      set -e
      mkdir -p /tmp/.ros
      source /opt/ros/noetic/setup.bash
      # Prefer catkin devel-space (rosrun-friendly), fall back to install-space.
      if [ -f /test_ws/devel/setup.bash ]; then
        source /test_ws/devel/setup.bash
      elif [ -f /test_ws/install/setup.bash ]; then
        source /test_ws/install/setup.bash
      fi

      BAG=\"/data/${INPUT_BAG_NAME}\"
      OUT_DIR=\"/exp/results/${OUTPUT_DIR}\"
      REC_BAG=\"\${OUT_DIR}/recorded.bag\"

      mkdir -p \"\${OUT_DIR}\"
      rm -rf \"\${OUT_DIR}/hdmapping\"

      # Start roscore
      roscore >/tmp/roscore.log 2>&1 &
      ROSCORE_PID=\$!
      cleanup() {
        set +e
        if [ -n \"\${REC_PID:-}\" ]; then kill \"\${REC_PID}\" 2>/dev/null || true; fi
        if [ -n \"\${LAUNCH_PID:-}\" ]; then kill \"\${LAUNCH_PID}\" 2>/dev/null || true; fi
        if [ -n \"\${ROSCORE_PID:-}\" ]; then kill \"\${ROSCORE_PID}\" 2>/dev/null || true; fi
      }
      trap cleanup EXIT

      # Wait for roscore
      for i in \$(seq 1 50); do
        rostopic list >/dev/null 2>&1 && break
        sleep 0.2
      done

      # Ensure nodes use simulated time when playing bags with --clock
      rosparam set use_sim_time true

      # Launch Faster-LIO (best-effort topic overrides; depends on launch accepting these args)
      roslaunch ${FASTERLIO_LAUNCH} imu_topic:=${INPUT_IMU_TOPIC} lidar_topic:=${INPUT_LIDAR_TOPIC} >/tmp/fasterlio.log 2>&1 &
      LAUNCH_PID=\$!

      # Start recording outputs
      rosbag record ${RECORD_TOPICS} -O \"\${REC_BAG}\" >/tmp/record.log 2>&1 &
      REC_PID=\$!

      # Give nodes time to connect
      sleep 2

      # Play input bag
      rosbag play \"\${BAG}\" ${ROSPLAY_ARGS}

      # Stop recorder and launch
      sleep 2
      kill \"\${REC_PID}\" 2>/dev/null || true
      wait \"\${REC_PID}\" 2>/dev/null || true
      kill \"\${LAUNCH_PID}\" 2>/dev/null || true
      wait \"\${LAUNCH_PID}\" 2>/dev/null || true

      # Convert recorded outputs to HDMapping
      mkdir -p \"\${OUT_DIR}/hdmapping\"
      rosrun faster-lio-to-hdmapping listener \"\${REC_BAG}\" \"\${OUT_DIR}/hdmapping\"
    "

echo ""
echo "=========================================="
echo "Benchmark completed successfully!"
echo "=========================================="
echo "Results location: ${OUTPUT_DIR_ABS}"
echo "  - Recorded ROS1 bag: ${OUTPUT_DIR_ABS}/recorded.bag"
echo "  - HDMapping output:  ${OUTPUT_DIR_ABS}/hdmapping"
echo "=========================================="

