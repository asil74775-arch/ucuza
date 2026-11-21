from .affiliate_feed import AffiliateFeed

# Yalnızca sözleşmeli affiliate/ortaklık feed'leri kullanılır (site kazıma veya
# kazıma tabanlı arama API'leri bilinçli olarak YOK — hukuki risk).
REGISTRY = [AffiliateFeed()]


def enabled_sources():
    return [s for s in REGISTRY if s.enabled]
