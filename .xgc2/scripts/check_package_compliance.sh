#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

for script in .xgc2/scripts/*.sh; do
  bash -n "${script}"
done

PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/xgc2-camera-pycache" python3 -m py_compile \
  xgc_camera_calibration/scripts/*.py \
  xgc_camera_calibration/src/xgc_camera_calibration/*.py \
  xgc_camera_calibration/test/*.py \
  .xgc2/scripts/xgc2_artifact_manifest.py

MANIFEST_TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${MANIFEST_TEST_ROOT}"' EXIT
MANIFEST_TEST_ARCH="$(dpkg --print-architecture)"
mkdir -p \
  "${MANIFEST_TEST_ROOT}/package/DEBIAN" \
  "${MANIFEST_TEST_ROOT}/debs" \
  "${MANIFEST_TEST_ROOT}/manifests"
printf '%s\n' \
  'Package: xgc2-camera-calibration-manifest-contract' \
  'Version: 0.3.0-2' \
  'Section: misc' \
  'Priority: optional' \
  "Architecture: ${MANIFEST_TEST_ARCH}" \
  'Maintainer: XGC2 <dev@xiaokang.ink>' \
  'Description: XGC2 camera calibration build-manifest contract test' \
  >"${MANIFEST_TEST_ROOT}/package/DEBIAN/control"
dpkg-deb --build \
  "${MANIFEST_TEST_ROOT}/package" \
  "${MANIFEST_TEST_ROOT}/debs/xgc2-camera-calibration-manifest-contract_0.3.0-2_${MANIFEST_TEST_ARCH}.deb" \
  >/dev/null
python3 .xgc2/scripts/xgc2_artifact_manifest.py build \
  --deb-dir "${MANIFEST_TEST_ROOT}/debs" \
  --output-dir "${MANIFEST_TEST_ROOT}/manifests" \
  --product xgc2-camera-calibration-ros1 \
  --product-version 0.3.0-2 \
  --distribution focal \
  --architecture "${MANIFEST_TEST_ARCH}" \
  --source-sha 0000000000000000000000000000000000000000 \
  --ci-run-id compliance \
  --ci-workflow ci \
  --ci-workflow-ref refs/heads/main

MANIFEST_TEST_ROOT="${MANIFEST_TEST_ROOT}" python3 - <<'PY'
import json
import os
import pathlib
import xml.etree.ElementTree as ET

root = pathlib.Path(".")
for path in sorted(root.glob("xgc_camera_*/package.xml")):
    ET.parse(path)
for path in sorted(root.glob("xgc_camera_*/*/*.launch")):
    ET.parse(path)

plugin_path = root / "process-definitions/xgc2-camera-calibration-ros1.json"
plugin = json.loads(plugin_path.read_text(encoding="utf-8"))
assert plugin["apiVersion"] == "xgc.execution.process/v1"
definitions = plugin["definitions"]
keys = [(definition["id"], definition["version"]) for definition in definitions]
ids = {definition["id"] for definition in definitions}
assert len(keys) == len(set(keys)) == 7
assert len(ids) == 3
assert "xgc2-camera-v4l2-ros1" not in ids
intrinsic_versions = {
    item["version"]: item for item in definitions
    if item["id"] == "xgc2-camera-intrinsic-calibrator-ros1"
}
assert set(intrinsic_versions) == {"2.0.0", "2.1.0"}
intrinsic_legacy = intrinsic_versions["2.0.0"]
intrinsic = intrinsic_versions["2.1.0"]
extrinsic_versions = {
    item["version"]: item for item in definitions
    if item["id"] == "xgc2-camera-extrinsic-calibrator-ros1"
}
assert set(extrinsic_versions) == {"2.0.0", "2.0.1", "2.0.2"}
extrinsic = extrinsic_versions["2.0.2"]
tf_versions = {
    item["version"]: item for item in definitions
    if item["id"] == "xgc2-camera-extrinsic-tf-ros1"
}
assert set(tf_versions) == {"1.0.0", "1.1.0"}
tf_publisher = tf_versions["1.1.0"]
assert tf_publisher["parameters"]["properties"]["waitForFile"]["default"] is False
assert tf_publisher["parameters"]["properties"]["watchFile"]["default"] is False
assert "_require_file_update:=${requireFileUpdate}" in tf_publisher["command"]["args"]
assert extrinsic["command"]["executable"] == (
    "/opt/ros/noetic/lib/xgc_camera_calibration/extrinsic_calibrator_web.py"
)
assert extrinsic["parameters"]["properties"]["bindAddress"]["default"] == "127.0.0.1"
assert extrinsic["parameters"]["properties"]["httpPort"]["default"] == 18082
assert "DISPLAY" not in extrinsic["command"]["env"]
assert intrinsic_legacy["parameters"]["properties"]["httpPort"]["default"] == 8766
assert intrinsic_legacy["parameters"]["properties"]["outputFile"]["default"] == (
    "/var/lib/xgc2/camera/calibrations/usb_cam/intrinsics.yaml"
)
assert intrinsic["command"]["executable"] == (
    "/opt/ros/noetic/lib/xgc_camera_calibration/intrinsic_calibrator_web.py"
)
intrinsic_properties = intrinsic["parameters"]["properties"]
assert intrinsic_properties["httpPort"]["default"] == 18083
assert intrinsic_properties["outputFile"]["default"] == (
    "/tmp/xgc2/camera/calibrations/usb_cam/intrinsics.yaml"
)
assert intrinsic_properties["referencesDir"]["default"] == (
    "/tmp/xgc2/camera/calibrations/usb_cam/intrinsic_refs"
)
assert intrinsic_properties["rosLogDir"]["default"] == (
    "/tmp/xgc2/ros/log/camera-calibration"
)
assert intrinsic["parameters"]["properties"]["cameraControl"]["default"] is False
assert "DISPLAY" not in intrinsic["command"]["env"]
intrinsic_claims = {
    claim["bindingKey"]: claim for claim in intrinsic["resourceClaims"]
}
assert intrinsic_claims["http"]["kind"] == "tcp-listener"
assert intrinsic_claims["http"]["address"] == "127.0.0.1"
assert intrinsic_claims["http"]["portParameter"] == "httpPort"
assert intrinsic_claims["ros-node"]["namespace"] == "ros1-node"
assert intrinsic_claims["ros-node"]["identityParts"] == [
    {"parameter": "rosMasterUri"},
    {"literal": "/xgc_camera_intrinsic_calibrator_web"},
]
assert intrinsic["readiness"]["kind"] == "tcp"
assert intrinsic["readiness"]["address"] == "127.0.0.1:${httpPort}"
assert intrinsic["readiness"]["successThreshold"] == 1
assert intrinsic["readiness"]["failureThreshold"] == 30

manifest_paths = list(
    (pathlib.Path(os.environ["MANIFEST_TEST_ROOT"]) / "manifests").glob("*.json")
)
assert len(manifest_paths) == 1
manifest = json.loads(manifest_paths[0].read_text(encoding="utf-8"))
assert set(manifest) == {
    "schema", "product", "source_sha", "version", "distribution",
    "architecture", "ci", "created_at", "debs",
}
assert manifest["schema"] == "xgc2.build-artifact.v1"
assert manifest["product"] == "xgc2-camera-calibration-ros1"
assert manifest["version"] == "0.3.0-2"
assert set(manifest["ci"]) == {"run_id", "workflow", "workflow_ref"}
assert len(manifest["debs"]) == 1
deb = manifest["debs"][0]
assert set(deb) == {
    "file", "package", "version", "architecture", "sha256", "size",
}
assert deb["package"] == "xgc2-camera-calibration-manifest-contract"
assert deb["version"] == "0.3.0-2"
assert len(deb["sha256"]) == 64
assert deb["size"] > 0
PY

grep -q '^id: xgc2-camera-calibration-ros1$' .xgc2/product.yml
grep -q '^version: 0.3.0-11$' .xgc2/product.yml
grep -q '^    focal: 0.3.0-11$' .xgc2/product.yml
if grep -q '^    focal: .*~focal' .xgc2/product.yml; then
  echo "single-distribution ROS1 package version must not retain a focal suffix" >&2
  exit 1
fi
grep -q '/usr/share/xgc2/process-definitions' xgc_camera_calibration/CMakeLists.txt
grep -q '/workspace/repo/process-definitions/' .xgc2/scripts/build_debs_in_docker.sh
grep -q '/workspace/work/src/process-definitions/' .xgc2/scripts/build_debs_in_docker.sh
grep -q '<exec_depend>gazebo_msgs</exec_depend>' xgc_camera_calibration/package.xml
grep -q '<exec_depend>tf</exec_depend>' xgc_camera_calibration/package.xml
grep -q 'ros-noetic-gazebo-msgs' .xgc2/product.yml
grep -q 'ros-noetic-tf$' .xgc2/product.yml
grep -q 'ros-noetic-gazebo-msgs.*ros-noetic-geometry-msgs' .xgc2/scripts/package_debs.sh
grep -q 'ros-noetic-sensor-msgs.*ros-noetic-tf,.*ros-noetic-tf2-ros' .xgc2/scripts/package_debs.sh
for page in extrinsic intrinsic; do
  test -f "xgc_camera_calibration/web/${page}/index.html"
  test -f "xgc_camera_calibration/web/${page}/app.js"
  test -f "xgc_camera_calibration/web/${page}/styles.css"
done
if grep -R --exclude-dir=__pycache__ -E '(PyQt|python3-pyqt5|extrinsic_calibrator_ui)' \
  process-definitions xgc_camera_calibration README.md \
  .xgc2/product.yml .xgc2/scripts/package_debs.sh \
  .xgc2/scripts/build_debs_in_docker.sh \
  .xgc2/scripts/check_installed_packages.sh >/dev/null; then
  echo "desktop Qt dependency leaked into the WebUI camera calibrator" >&2
  exit 1
fi
if grep -R -E -i '(xgc_camera_driver|libxgc2-camera-dev|ros-noetic-xgc-camera-driver)' \
  process-definitions xgc_camera_calibration .xgc2/product.yml \
  .xgc2/scripts/build_debs_in_docker.sh .xgc2/scripts/package_debs.sh \
  .xgc2/scripts/check_installed_packages.sh >/dev/null; then
  echo "camera driver dependency leaked into the independent calibration product" >&2
  exit 1
fi

echo "ROS1 camera product compliance passed"
