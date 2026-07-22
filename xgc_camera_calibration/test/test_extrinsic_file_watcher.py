#!/usr/bin/env python3

import os
import tempfile
import unittest
from pathlib import Path

from xgc_camera_calibration.extrinsic_file_watcher import ExtrinsicFileWatcher


class ExtrinsicFileWatcherTest(unittest.TestCase):
    def test_reports_existing_file_once_without_update_requirement(self):
        with tempfile.TemporaryDirectory() as directory:
            asset = Path(directory) / "extrinsics.yaml"
            asset.write_text("first")
            watcher = ExtrinsicFileWatcher(asset)

            self.assertIsNotNone(watcher.next_revision())
            self.assertIsNone(watcher.next_revision())

    def test_ignores_stale_asset_until_it_is_atomically_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            asset = Path(directory) / "extrinsics.yaml"
            replacement = Path(directory) / "replacement.yaml"
            asset.write_text("stale")
            watcher = ExtrinsicFileWatcher(asset, require_update=True)

            self.assertIsNone(watcher.next_revision())
            replacement.write_text("solved")
            os.replace(replacement, asset)
            self.assertIsNotNone(watcher.next_revision())
            self.assertIsNone(watcher.next_revision())

    def test_accepts_first_asset_created_after_start(self):
        with tempfile.TemporaryDirectory() as directory:
            asset = Path(directory) / "extrinsics.yaml"
            watcher = ExtrinsicFileWatcher(asset, require_update=True)

            self.assertIsNone(watcher.next_revision())
            asset.write_text("solved")
            self.assertIsNotNone(watcher.next_revision())


if __name__ == "__main__":
    unittest.main()
