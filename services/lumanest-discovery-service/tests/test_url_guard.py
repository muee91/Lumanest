import pytest

from app.crawl.url_guard import UrlPolicy, UrlRejected, guard_url


def policy():
    return UrlPolicy("example.gov.cn", ("/notice/",), ("/notice/login*",))


def test_guard_normalizes_allowed_https_url():
    assert guard_url("https://WWW.Example.Gov.CN/notice/a#section", policy(), resolve_dns=False) == "https://www.example.gov.cn/notice/a"


@pytest.mark.parametrize("url", [
    "http://example.gov.cn/notice/a",
    "https://example.gov.cn/login",
    "https://evil.example/notice/a",
    "https://user:pass@example.gov.cn/notice/a",
    "https://example.gov.cn:8443/notice/a",
])
def test_guard_rejects_unsafe_or_unapproved_urls(url):
    with pytest.raises(UrlRejected):
        guard_url(url, policy(), resolve_dns=False)


def test_guard_rejects_private_dns_result(monkeypatch):
    monkeypatch.setattr("socket.getaddrinfo", lambda *_args, **_kwargs: [(None, None, None, None, ("127.0.0.1", 443))])
    with pytest.raises(UrlRejected, match="private_address"):
        guard_url("https://example.gov.cn/notice/a", policy())
