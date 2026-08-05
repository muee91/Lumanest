from pathlib import Path

path = Path('test/presentation_v2/explore/v2_provider_facts_sheet_test.dart')
text = path.read_text(encoding='utf-8')
old = "expect(find.textContaining('不代表动物当前仍在现场'), findsOneWidget);"
new = "expect(find.textContaining('不代表动物当前仍在现场'), findsNWidgets(2));"
count = text.count(old)
if count != 1:
    raise SystemExit(f'ecology widget assertion anchor mismatch: {count}')
path.write_text(text.replace(old, new), encoding='utf-8')
