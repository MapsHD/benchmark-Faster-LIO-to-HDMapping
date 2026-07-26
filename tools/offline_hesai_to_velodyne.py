"""
Offline, no-C++-changes bag conversion for Faster-LIO (pure upstream,
gaoxiang12/faster-lio, no native Hesai support -- AviaHandler consumes
livox_ros_driver::CustomMsg directly, no PointCloud2 path for Livox).

Rewrites the native ROS1 bag's /hesai/pandar PointCloud2 (Hesai layout:
x,y,z f32 @0/4/8, intensity f32 @16, timestamp f64 @24 ABSOLUTE epoch
seconds, ring u16 @32, point_step=48) into a PointCloud2 matching
faster-lio's velodyne_ros::Point (x,y,z,intensity f32, time f32, ring u16,
point_step=22), published on /velodyne_points.

VelodyneHandler (lidar_type=VELO32=2) reads `.time` as MICROSECONDS
relative to the first point in the scan and does
`curvature = time * time_scale_` (time_scale defaults to 1e-3 in
config/velodyne.yaml) to get milliseconds -- see
src/faster-lio/src/pointcloud_preprocess.cc:154. Since the converted
`.time` is always > 0 for the last point in a non-trivial scan,
given_offset_time_ is true and the ring-indexed num_scans_ bucket code
(sized for 16/32-beam Velodynes) is never exercised, so Hesai QT64's wider
ring range (up to 63) is not a problem.

/alphasense_driver_ros/imu is passed through unchanged (same msgtype) onto
/imu_data.
"""
import sys
import numpy as np
from pathlib import Path
from rosbags.rosbag1 import Reader, Writer
from rosbags.typesys import Stores, get_typestore

SRC = Path(sys.argv[1])
DST = Path(sys.argv[2])

LIDAR_TOPIC_IN = '/hesai/pandar'
IMU_TOPIC_IN = '/alphasense_driver_ros/imu'
LIDAR_TOPIC_OUT = '/velodyne_points'
IMU_TOPIC_OUT = '/imu_data'

ts = get_typestore(Stores.ROS1_NOETIC)
PointCloud2 = ts.types['sensor_msgs/msg/PointCloud2']
PointField = ts.types['sensor_msgs/msg/PointField']
Header = ts.types['std_msgs/msg/Header']
Time = ts.types['builtin_interfaces/msg/Time']

DTYPE_IN = np.dtype({
    'names': ['x', 'y', 'z', 'intensity', 'timestamp', 'ring'],
    'formats': ['<f4', '<f4', '<f4', '<f4', '<f8', '<u2'],
    'offsets': [0, 4, 8, 16, 24, 32],
    'itemsize': 48,
})

DTYPE_OUT = np.dtype({
    'names': ['x', 'y', 'z', 'intensity', 'time', 'ring'],
    'formats': ['<f4', '<f4', '<f4', '<f4', '<f4', '<u2'],
    'offsets': [0, 4, 8, 12, 16, 20],
    'itemsize': 22,
})

FIELDS_OUT = [
    PointField(name='x', offset=0, datatype=PointField.FLOAT32, count=1),
    PointField(name='y', offset=4, datatype=PointField.FLOAT32, count=1),
    PointField(name='z', offset=8, datatype=PointField.FLOAT32, count=1),
    PointField(name='intensity', offset=12, datatype=PointField.FLOAT32, count=1),
    PointField(name='time', offset=16, datatype=PointField.FLOAT32, count=1),
    PointField(name='ring', offset=20, datatype=PointField.UINT16, count=1),
]


def convert_cloud(msg):
    raw = np.frombuffer(bytes(msg.data), dtype=DTYPE_IN, count=msg.width * msg.height)
    if raw.size == 0:
        rel_time_us = np.zeros(0, dtype='<f4')
    else:
        t0 = raw['timestamp'][0]
        rel_time_us = ((raw['timestamp'] - t0) * 1e6).astype('<f4')

    out = np.zeros(raw.size, dtype=DTYPE_OUT)
    out['x'] = raw['x']
    out['y'] = raw['y']
    out['z'] = raw['z']
    out['intensity'] = raw['intensity']
    out['time'] = rel_time_us
    out['ring'] = raw['ring']

    data_bytes = np.frombuffer(out.tobytes(), dtype=np.uint8)

    return PointCloud2(
        header=msg.header,
        height=1,
        width=raw.size,
        fields=FIELDS_OUT,
        is_bigendian=False,
        point_step=22,
        row_step=22 * raw.size,
        data=data_bytes,
        is_dense=msg.is_dense,
    )


def main():
    n_cloud = 0
    n_imu = 0
    with Reader(SRC) as reader, Writer(DST) as writer:
        conns = [c for c in reader.connections if c.topic in (LIDAR_TOPIC_IN, IMU_TOPIC_IN)]
        by_topic = {c.topic: c for c in conns}
        if LIDAR_TOPIC_IN not in by_topic:
            sys.exit(f'ERROR: topic {LIDAR_TOPIC_IN} not found in {SRC}')
        if IMU_TOPIC_IN not in by_topic:
            sys.exit(f'ERROR: topic {IMU_TOPIC_IN} not found in {SRC}')

        imu_msgtype = by_topic[IMU_TOPIC_IN].msgtype
        out_lidar_conn = writer.add_connection(LIDAR_TOPIC_OUT, PointCloud2.__msgtype__, typestore=ts)
        out_imu_conn = writer.add_connection(IMU_TOPIC_OUT, imu_msgtype, typestore=ts)

        for conn, timestamp, rawdata in reader.messages(connections=conns):
            if conn.topic == IMU_TOPIC_IN:
                writer.write(out_imu_conn, timestamp, rawdata)
                n_imu += 1
            else:
                msg = ts.deserialize_ros1(rawdata, conn.msgtype)
                out_msg = convert_cloud(msg)
                out_data = ts.serialize_ros1(out_msg, PointCloud2.__msgtype__)
                writer.write(out_lidar_conn, timestamp, out_data)
                n_cloud += 1
                if n_cloud % 200 == 0:
                    print(f'... {n_cloud} lidar scans, {n_imu} imu msgs', flush=True)

    print(f'DONE: {n_cloud} lidar scans, {n_imu} imu msgs -> {DST}')


if __name__ == '__main__':
    main()
