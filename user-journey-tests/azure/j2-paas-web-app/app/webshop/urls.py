"""Root URL configuration for the stationery shop's storefront."""

from django.urls import include, path

urlpatterns = [
    path("", include("storefront.urls")),
]
