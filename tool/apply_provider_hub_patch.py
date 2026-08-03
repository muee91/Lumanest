from pathlib import Path
import ast
import base64
import gzip
import json

root = Path(__file__).resolve().parents[1]
parts = root / 'tool' / 'provider_patch_parts'
encoded = ''.join(path.read_text().strip() for path in sorted(parts.glob('part-*')))
source = gzip.decompress(base64.b64decode(encoded)).decode('utf-8')

marker = "FILES = json.loads(r'"
start = source.index(marker) + len(marker)
end = source.index("')\n\ndef replace_once", start)
raw_files = source[start:end]
files = json.loads(ast.literal_eval("'" + raw_files + "'"))
tail = source[source.index('def replace_once', end):]
namespace = {'Path': Path, 'ROOT': root, 'FILES': files}
exec(compile(tail, 'apply_provider_hub_patch_payload.py', 'exec'), namespace)
