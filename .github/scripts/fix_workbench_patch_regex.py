from pathlib import Path

path = Path('.github/scripts/workbench_clarity_patch.py')
text = path.read_text(encoding='utf-8')
replacements = {
    r"r'class _EnvironmentSummary extends StatelessWidget \\{.*?\\n\\}\\n\\nclass _FactGrid'": r"r'class _EnvironmentSummary extends StatelessWidget \{.*?\n\}\n\nclass _FactGrid'",
    r"r'class _TrendMetricSelector extends StatelessWidget \\{.*?\\n\\}\\n\\nclass _ForecastSample'": r"r'class _TrendMetricSelector extends StatelessWidget \{.*?\n\}\n\nclass _ForecastSample'",
    r"r'class _ProvenanceCard extends StatelessWidget \\{.*?\\n\\}\\n\\nclass _EmptyPanel'": r"r'class _ProvenanceCard extends StatelessWidget \{.*?\n\}\n\nclass _EmptyPanel'",
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f'expected one regex literal, found {text.count(old)}: {old}')
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
