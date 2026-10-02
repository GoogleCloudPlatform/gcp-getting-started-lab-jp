"""Storefront application config.

ready() is where the shop wires up telemetry and pulls the checkout signing key
out of the vault. Both are best-effort: a worker that cannot reach either one
still serves the catalogue.
"""

from __future__ import annotations

import logging
import os

from django.apps import AppConfig

logger = logging.getLogger(__name__)


class StorefrontConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "storefront"

    def ready(self) -> None:
        self._start_telemetry()
        self._load_checkout_key()

    def _start_telemetry(self) -> None:
        connection_string = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
        if not connection_string:
            logger.info("telemetry not configured; skipping exporter setup")
            return
        try:
            from azure.monitor.opentelemetry import configure_azure_monitor

            configure_azure_monitor(connection_string=connection_string)
            logger.info("telemetry exporter configured")
        except Exception:
            logger.warning("telemetry exporter unavailable; continuing without it")

    def _load_checkout_key(self) -> None:
        from webshop import azure_clients

        key = azure_clients.load_checkout_signing_key()
        if key:
            logger.info("checkout signing key loaded (%d characters)", len(key))
        else:
            logger.warning("checkout signing key is empty")
