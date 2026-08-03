from pathlib import Path
import base64
import gzip

root = Path(__file__).resolve().parents[1]
parts = root / 'tool' / 'provider_patch_parts'
encoded = ''.join(path.read_text().strip() for path in sorted(parts.glob('part-*')))
payload = gzip.decompress(base64.b64decode(encoded))
exec(compile(payload, 'apply_provider_hub_patch_payload.py', 'exec'))
