#!/usr/bin/env python
"""Django command-line utility for the stationery shop's storefront."""

import os
import sys


def main():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "webshop.settings")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Django is not importable. Activate a virtual environment and "
            "install requirements.txt first."
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
