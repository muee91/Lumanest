from pathlib import Path

path = Path('.github/scripts/workbench_clarity_patch.py')
lines = path.read_text(encoding='utf-8').splitlines(keepends=True)
targets = (
    "r'class _EnvironmentSummary extends StatelessWidget",
    "r'class _TrendMetricSelector extends StatelessWidget",
    "r'class _ProvenanceCard extends StatelessWidget",
)
updated = []
count = 0
for line in lines:
    if any(target in line for target in targets):
        line = line.replace(r'\\{', r'\{')
        line = line.replace(r'\\}', r'\}')
        line = line.replace(r'\\n', r'\n')
        count += 1
    updated.append(line)
if count != len(targets):
    raise SystemExit(f'expected {len(targets)} regex lines, found {count}')
path.write_text(''.join(updated), encoding='utf-8')
