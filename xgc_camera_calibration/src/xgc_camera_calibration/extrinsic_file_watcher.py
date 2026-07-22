"""Detect atomic camera-extrinsic calibration asset updates."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Union


@dataclass(frozen=True)
class FileFingerprint:
    """Filesystem identity used to distinguish newly solved calibration assets."""

    device: int
    inode: int
    size: int
    modified_ns: int


def file_fingerprint(path: Union[str, Path]) -> Optional[FileFingerprint]:
    """Return a stable fingerprint, or ``None`` while the asset is absent."""

    try:
        status = Path(path).stat()
    except FileNotFoundError:
        return None
    return FileFingerprint(
        device=int(status.st_dev),
        inode=int(status.st_ino),
        size=int(status.st_size),
        modified_ns=int(status.st_mtime_ns),
    )


class ExtrinsicFileWatcher:
    """Yield each newly observed calibration asset revision once."""

    def __init__(self, path: Union[str, Path], require_update: bool = False):
        self.path = Path(path)
        self._last_seen = file_fingerprint(self.path) if require_update else None

    def next_revision(self) -> Optional[FileFingerprint]:
        """Return an unseen revision, ignoring a required pre-start baseline."""

        current = file_fingerprint(self.path)
        if current is None or current == self._last_seen:
            return None
        self._last_seen = current
        return current
