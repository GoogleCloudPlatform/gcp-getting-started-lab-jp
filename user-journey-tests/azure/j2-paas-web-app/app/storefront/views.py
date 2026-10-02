"""Storefront views.

Every Azure call goes through webshop.azure_clients — nothing in this module
imports an Azure SDK directly.
"""

from __future__ import annotations

from django.db import connection
from django.http import HttpResponse, JsonResponse
from django.shortcuts import get_object_or_404, render

from webshop import azure_clients

from .models import Category, Product


def product_list(request):
    categories = Category.objects.prefetch_related("products").all()
    products = Product.objects.select_related("category").all()
    return render(
        request,
        "storefront/product_list.html",
        {
            "categories": categories,
            "products": [
                {"product": product, "image_url": azure_clients.media_url(product.image_blob)}
                for product in products
            ],
        },
    )


def product_detail(request, slug: str):
    product = get_object_or_404(Product.objects.select_related("category"), slug=slug)
    return render(
        request,
        "storefront/product_detail.html",
        {
            "product": product,
            "image_url": azure_clients.media_url(product.image_blob),
        },
    )


def media_blob(request, blob_name: str):
    """Serve one product image out of the private blob container.

    The container has no public access, so images travel through the app. Front
    Door caches everything under /media/ so this path is cold only once.
    """
    fetched = azure_clients.download_media(blob_name)
    if fetched is None:
        return HttpResponse(status=404)
    content, content_type = fetched
    response = HttpResponse(content, content_type=content_type)
    response["Cache-Control"] = "public, max-age=3600"
    return response


def _probe_database() -> dict:
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) FROM storefront_product")
            (count,) = cursor.fetchone()
        return {"ok": True, "detail": f"{count} products"}
    except Exception as exc:
        return {"ok": False, "detail": type(exc).__name__}


def health(request):
    """Liveness and dependency check. Never raises.

    Returns 503 only when the database is unreachable, because that is the one
    dependency without which no page can be served. A missing image or an
    unreadable secret degrades the shop rather than taking it down.
    """
    checks = {
        "database": _probe_database(),
        "blob": azure_clients.probe_blob(),
        "vault": azure_clients.probe_vault(),
    }
    all_ok = all(check["ok"] for check in checks.values())
    payload = {
        "status": "ok" if all_ok else "degraded",
        "service": "webshop-storefront",
        "checks": checks,
    }
    status_code = 200 if checks["database"]["ok"] else 503
    return JsonResponse(payload, status=status_code)


def azure_check(request):
    """Per-service parity dashboard.

    After the migration the same page answers for the GCP equivalents, so the
    keys stay service-shaped rather than product-shaped.
    """
    services = {
        "managed_identity": azure_clients.probe_identity(),
        "blob_storage": azure_clients.probe_blob(),
        "key_vault": azure_clients.probe_vault(),
        "postgresql": _probe_database(),
        "telemetry": azure_clients.probe_telemetry(),
    }
    return JsonResponse(
        {
            "service": "webshop-storefront",
            "all_ok": all(entry["ok"] for entry in services.values()),
            "services": services,
            "media_sample": azure_clients.list_media(limit=3),
        }
    )
