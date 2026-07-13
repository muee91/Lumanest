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
