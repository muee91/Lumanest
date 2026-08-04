from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {text.count(old)}")
    return text.replace(old, new, 1)


route_path = Path('lib/src/presentation_v2/route/v2_route_page.dart')
route = route_path.read_text()
route = replace_once(
    route,
    "      final point = ChinaCoordinateConverter.wgs84ToGcj02(place.point);",
    "      final point = place.point.coordinateSystem == CoordinateSystem.gcj02\n"
    "          ? place.point\n"
    "          : ChinaCoordinateConverter.wgs84ToGcj02(place.point);",
    'respect POI coordinate system',
)
route = replace_once(
    route,
    "    final urgent = scout?.criticalCount case final count? when count > 0\n"
    "        ? true\n"
    "        : !canCatch;",
    "    final urgent = (scout?.criticalCount ?? 0) > 0 || !canCatch;",
    'portable urgent boolean',
)
route_path.write_text(route)
