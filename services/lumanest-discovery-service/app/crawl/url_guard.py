from __future__ import annotations

import ipaddress
import socket
from dataclasses import dataclass
from urllib.parse import urlsplit, urlunsplit


@dataclass(frozen=True)
class UrlPolicy:
    domain: str
    allowed_path_prefixes: tuple[str, ...] = ()
    denied_path_patterns: tuple[str, ...] = ()


class UrlRejected(ValueError):
    pass


def guard_url(value: str, policy: UrlPolicy, *, resolve_dns: bool = True) -> str:
    parsed = urlsplit(value)
    if parsed.scheme != "https" or parsed.port not in (None, 443) or parsed.username or parsed.password:
        raise UrlRejected("url_not_allowed")
    hostname = (parsed.hostname or "").casefold().rstrip(".")
    domain = policy.domain.casefold().rstrip(".")
    if not hostname or not (hostname == domain or hostname.endswith(f".{domain}")):
        raise UrlRejected("domain_not_allowed")
    path = parsed.path or "/"
    if policy.allowed_path_prefixes and not any(path.startswith(prefix) for prefix in policy.allowed_path_prefixes):
        raise UrlRejected("path_not_allowed")
    if any(_glob_match(path, pattern) for pattern in policy.denied_path_patterns):
        raise UrlRejected("path_denied")
    if resolve_dns:
        try:
            addresses = {item[4][0] for item in socket.getaddrinfo(hostname, 443, type=socket.SOCK_STREAM)}
        except OSError as error:
            raise UrlRejected("dns_failed") from error
        if any(_private_or_reserved(address) for address in addresses):
            raise UrlRejected("private_address")
    return urlunsplit(("https", hostname, path, parsed.query, ""))


def _private_or_reserved(value: str) -> bool:
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        return True
    return address.is_private or address.is_loopback or address.is_link_local or address.is_reserved or address.is_unspecified or address.is_multicast


def _glob_match(value: str, pattern: str) -> bool:
    import fnmatch
    return fnmatch.fnmatchcase(value, pattern)
