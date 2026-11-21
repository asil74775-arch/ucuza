from .affiliate_feed import AffiliateFeed
from .serpapi import SerpApiShopping

REGISTRY = [AffiliateFeed(), SerpApiShopping()]


def enabled_sources():
    return [s for s in REGISTRY if s.enabled]
