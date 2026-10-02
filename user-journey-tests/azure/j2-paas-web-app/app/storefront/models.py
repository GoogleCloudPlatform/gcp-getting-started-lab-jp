"""Catalogue models for the stationery shop's storefront."""

from __future__ import annotations

from django.db import models

# Japanese consumption tax on stationery, as a percentage.
CONSUMPTION_TAX_PERCENT = 10


class Category(models.Model):
    slug = models.SlugField(max_length=40, unique=True)
    name = models.CharField(max_length=80)
    name_ja = models.CharField(max_length=80, blank=True)
    sort_order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "name"]
        verbose_name_plural = "categories"

    def __str__(self) -> str:
        return self.name


class Product(models.Model):
    category = models.ForeignKey(
        Category, on_delete=models.PROTECT, related_name="products"
    )
    slug = models.SlugField(max_length=64, unique=True)
    name = models.CharField(max_length=120)
    name_ja = models.CharField(max_length=120, blank=True)
    description = models.TextField(blank=True)
    price_jpy = models.PositiveIntegerField()
    stock = models.PositiveIntegerField(default=0)
    image_blob = models.CharField(
        max_length=200,
        blank=True,
        help_text="Object name inside the media blob container.",
    )

    class Meta:
        ordering = ["category__sort_order", "name"]

    def __str__(self) -> str:
        return self.name

    @property
    def in_stock(self) -> bool:
        return self.stock > 0

    @property
    def price_with_tax_jpy(self) -> int:
        """Shelf price. Yen has no minor unit, so the tax is truncated."""
        return self.price_jpy * (100 + CONSUMPTION_TAX_PERCENT) // 100
