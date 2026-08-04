from pathlib import Path

model_path = Path('lib/src/features/today/application/environment_visualization.dart')
model = model_path.read_text(encoding='utf-8')
old = """    final values = <String, double>{
      if (lowCloudCoverPercent case final value?) '低云': value,
      if (middleCloudCoverPercent case final value?) '中云': value,
      if (highCloudCoverPercent case final value?) '高云': value,
    };
    if (values.isEmpty) return null;
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
"""
new = """    final values = <MapEntry<String, double>>[];
    if (lowCloudCoverPercent case final value?) {
      values.add(MapEntry('低云', value));
    }
    if (middleCloudCoverPercent case final value?) {
      values.add(MapEntry('中云', value));
    }
    if (highCloudCoverPercent case final value?) {
      values.add(MapEntry('高云', value));
    }
    if (values.isEmpty) return null;
    final sorted = values..sort((a, b) => b.value.compareTo(a.value));
"""
if old not in model:
    raise SystemExit('dominant layer block not found')
model_path.write_text(model.replace(old, new, 1), encoding='utf-8')

sheet_path = Path('lib/src/presentation_v2/environment/v2_cloud_detail_sheet.dart')
sheet = sheet_path.read_text(encoding='utf-8')
old_sheet = "text: const TextSpan(text: '无数据', style: labelStyle),"
new_sheet = "text: TextSpan(text: '无数据', style: labelStyle),"
if old_sheet not in sheet:
    raise SystemExit('invalid const text span not found')
sheet_path.write_text(sheet.replace(old_sheet, new_sheet, 1), encoding='utf-8')
