# XGC2 ROS1 Camera Calibration

Public ROS Noetic calibration tools for cameras that publish
`sensor_msgs/Image` and `sensor_msgs/CameraInfo`. Camera capture and ROS driver
adaptation deliberately live in separate products; this repository consumes
their ROS interfaces without depending on a particular camera driver.

## Calibration capabilities

### General intrinsic calibration

The intrinsic calibrator works with fixed, onboard, and vehicle-mounted
cameras. It auto-collects geometrically diverse chessboard views, tracks
X/Y/size/skew coverage, solves directly with OpenCV, and atomically writes a
standard camera calibration YAML. It does not assume that the camera is fixed
in a world frame.

```bash
roslaunch xgc_camera_calibration intrinsic_calibrator.launch \
  image_topic:=/usb_cam/image_raw \
  board_cols:=7 board_rows:=5 square_size:=0.20 \
  bind_address:=127.0.0.1 http_port:=8766
```

Open `http://127.0.0.1:8766/`. The optional `camera_control:=true` adapter can
move a named Gazebo camera through the sample guide, but simulation control is
not required by the intrinsic algorithm.

### Fixed-world-camera extrinsic calibration

The extrinsic calibrator is for a camera fixed in an experiment site's world
frame. It associates world-frame marker poses with pixels in a frozen image,
then solves and persists `parent_T_camera_optical` using robust PnP.

```bash
roslaunch xgc_camera_calibration extrinsic_calibrator.launch \
  image_topic:=/usb_cam/image_raw \
  camera_info_topic:=/usb_cam/camera_info \
  pose_prefix:=/vrpn_client_node \
  bind_address:=127.0.0.1 http_port:=8765
```

Open `http://127.0.0.1:8765/`. The solver requires valid intrinsic values, but
those values are an input contract rather than a package dependency. They may
come from the intrinsic tool above, a vendor calibration, or an existing
calibration asset.

Publish a solved fixed-camera transform with:

```bash
roslaunch xgc_camera_calibration extrinsic_tf.launch \
  extrinsic_file:=/var/lib/xgc2/camera/calibrations/usb_cam/extrinsics.yaml
```

The stable REP-103 chain is:

```text
map -> usb_cam_link -> usb_cam_optical_frame
```

## Independence and release boundary

Intrinsic calibration and fixed-camera extrinsic calibration are separate
logical workflows. Neither declares a build or release dependency on the
other. XGC2 Automation may run intrinsic calibration first when no usable
intrinsic asset exists, but an existing valid intrinsic asset lets the
extrinsic workflow start directly.

This repository releases `ros-noetic-xgc2-camera-calibration` independently
from both `libxgc2-camera-dev` and `ros-noetic-xgc-camera-driver`.

## Automation

`/usr/share/xgc2/process-definitions/xgc2-camera-calibration-ros1.json`
registers three independent process definitions:

- `xgc2-camera-intrinsic-calibrator-ros1`
- `xgc2-camera-extrinsic-calibrator-ros1`
- `xgc2-camera-extrinsic-tf-ros1`

Both WebUIs bind to loopback by default and require no desktop session or
`DISPLAY`. Runtime calibration assets are written outside the package share
directory under `/var/lib/xgc2/camera/calibrations` by default.

## Build and test

CI tests the Python solvers and Web services, builds the standalone Debian
package for Focal `amd64` and `arm64`, installs it in a clean container, and
checks its ROS launch files, process definitions, Python imports, and local
HTTP endpoints without installing or launching a camera driver.
