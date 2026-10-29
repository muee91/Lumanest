import { isIP } from 'node:net';

function privateIpv4(address) {
  const octets = address.split('.').map(Number);
  if (octets.length !== 4 || octets.some((value) => !Number.isInteger(value) || value < 0 || value > 255)) {
    return false;
  }
  const [first, second] = octets;
  return first === 127 || first === 10 ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 168);
}

export function isLanAddress(value) {
  if (typeof value !== 'string' || value.length === 0) return false;
  const address = value.toLowerCase().split('%')[0];
  if (address.startsWith('::ffff:')) return privateIpv4(address.slice(7));
  if (isIP(address) === 4) return privateIpv4(address);
  if (isIP(address) !== 6 || address === '::') return false;
  if (address === '::1') return true;
  return address.startsWith('fc') || address.startsWith('fd') ||
    /^fe[89ab]/.test(address);
}

// The socket peer alone cannot decide whether a request is local. Behind the
// Docker userland proxy every request — including one from the public internet —
// arrives from the bridge gateway (172.17.0.1), which is a private address. The
// `Host` header is what the caller actually typed, so it is the only signal that
// still distinguishes "someone on my LAN opened the NAS address" from "someone
// reached the published port from outside".
//
// Accepted hosts: loopback names, private or link-local IP literals, mDNS
// `.local` names, and anything an operator declares in
// LUMANEST_ADMIN_ALLOWED_HOSTS. A public domain or public IP is refused, because
// the admin console is not meant to be reachable from outside the LAN at all.
function hostnameOf(hostHeader) {
  if (typeof hostHeader !== 'string' || hostHeader.length === 0) return null;
  const trimmed = hostHeader.trim().toLowerCase();
  if (trimmed.startsWith('[')) {
    const end = trimmed.indexOf(']');
    if (end < 0) return null;
    return trimmed.slice(1, end);
  }
  const withoutPort = trimmed.split(':')[0];
  return withoutPort.length > 0 ? withoutPort : null;
}

export function isLanHostHeader(hostHeader, { allowedHosts = [] } = {}) {
  const hostname = hostnameOf(hostHeader);
  if (hostname == null) return false;
  if (allowedHosts.includes(hostname)) return true;
  if (hostname === 'localhost' || hostname.endsWith('.localhost')) return true;
  if (hostname.endsWith('.local')) return true;
  return isLanAddress(hostname);
}
