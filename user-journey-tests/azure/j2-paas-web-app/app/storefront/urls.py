"""Storefront routes."""

from django.urls import path

from . import views

urlpatterns = [
    path("", views.product_list, name="product-list"),
    path("health", views.health, name="health"),
    path("admin/azure-check", views.azure_check, name="azure-check"),
    path("media/<str:blob_name>", views.media_blob, name="media-blob"),
    path("product/<slug:slug>/", views.product_detail, name="product-detail"),
]
