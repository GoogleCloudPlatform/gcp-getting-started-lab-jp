#!/usr/bin/env python3
"""Package app/ into the zip App Service is given.

Both scripts/deploy.sh and scripts/app-self-test.sh call this, so the layout the
self-test runs against and the layout that gets deployed are the same layout by
construction rather than by two copies of the same loop agreeing.

What ends up at the root of the archive matters: App Service builds the Python
environment with Oryx, and Oryx installs from a requirements.txt at the ROOT of
what it is handed. app/requirements.txt therefore has to become ./requirements.txt
in the archive, which is why the paths are written relative to app/ and not to
the journey directory.

Usage: package-app.py <app-dir> <destination.zip>
"""

from __future__ import annotations

import os
import sys
import zipfile

SKIP_DIRS = {"__pycache__", ".venv", "venv", ".pytest_cache"}


def build(source: str, destination: str) -> int:
    written = 0
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for root, dirs, files in os.walk(source):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for name in sorted(files):
                if name.endswith(".pyc"):
                    continue
                full = os.path.join(root, name)
                archive.write(full, os.path.relpath(full, source))
                written += 1
    return written


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    source, destination = sys.argv[1], sys.argv[2]
    written = build(source, destination)
    print(f"packaged {destination} ({written} files)")


if __name__ == "__main__":
    main()
