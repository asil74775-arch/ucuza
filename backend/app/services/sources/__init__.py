from .affiliate_feed import AffiliateFeed
from .serpapi import SerpApiShopping
from .youtube import YouTubeComments

REGISTRY = [AffiliateFeed(), SerpApiShopping(), YouTubeComments()]


def enabled_sources():
    return [s for s in REGISTRY if s.enabled]
