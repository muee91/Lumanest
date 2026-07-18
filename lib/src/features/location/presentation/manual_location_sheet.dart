import 'package:amap_map/amap_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x_amap_base/x_amap_base.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/location/application/manual_location_providers.dart';
import 'package:luma_nest/src/features/location/application/base_region_controller.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

class ManualLocationSheet extends ConsumerStatefulWidget {
  const ManualLocationSheet({super.key, this.saveAsBaseRegion = false});

  final bool saveAsBaseRegion;

  @override
  ConsumerState<ManualLocationSheet> createState() =>
      _ManualLocationSheetState();
}

class _ManualLocationSheetState extends ConsumerState<ManualLocationSheet> {
  final _controller = TextEditingController();
  List<LocationSearchResult>? _results;
  var _loading = false;
  var _failed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await ref
          .read(locationSearchRepositoryProvider)
          .search(query);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(LocationSearchResult result) async {
    if (widget.saveAsBaseRegion) {
      await ref.read(baseRegionProvider.notifier).select(result);
    }
    await ref.read(manualLocationProvider.notifier).select(result);
    ref.read(environmentSnapshotProvider.notifier).refresh();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.saveAsBaseRegion ? '设置常驻地区' : '手动选择地点',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              widget.saveAsBaseRegion
                  ? '仅保存在本机，用作默认的环境分析地点。'
                  : '用于天气和光线判断；不会伪装成你的实时位置。',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '搜索目的地、机位或景区',
                suffixIcon: IconButton(
                  onPressed: _loading ? null : _search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('manual-location-map-picker'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                enableDrag: false,
                useSafeArea: true,
                builder: (_) => _MapLocationPicker(onSelect: _select),
              ),
              icon: const Icon(Icons.map_outlined),
              label: const Text('在地图上选点'),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_failed)
              const Text('地点搜索暂时不可用，请稍后重试。')
            else if (_results case final results?)
              if (results.isEmpty)
                const Text('没有找到匹配地点。')
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 310),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = results[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(result.name),
                        subtitle: result.address == null
                            ? null
                            : Text(result.address!),
                        trailing: const Icon(Icons.arrow_outward),
                        onTap: () => _select(result),
                      );
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _MapLocationPicker extends StatefulWidget {
  const _MapLocationPicker({required this.onSelect});
  final Future<void> Function(LocationSearchResult) onSelect;

  @override
  State<_MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<_MapLocationPicker> {
  LatLng? _selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: Stack(
          children: [
            AMapWidget(
              gestureRecognizers: {
                Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
              },
              markers: _selection == null
                  ? const {}
                  : {
                      Marker(
                        position: _selection!,
                        infoWindow: const InfoWindow(title: '手动地点'),
                      ),
                    },
              onTap: (point) => setState(() => _selection = point),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 12,
              child: Material(
                color: theme.colorScheme.surface.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '返回',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('在地图上选点', style: theme.textTheme.titleMedium),
                            Text(
                              _selection == null
                                  ? '拖动地图并轻点一个位置'
                                  : '已选点，确认后用于环境分析',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: Material(
                color: theme.colorScheme.surface.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: FilledButton.icon(
                    onPressed: _selection == null
                        ? null
                        : () async {
                            final gcj02 = GeoPoint(
                              latitude: _selection!.latitude,
                              longitude: _selection!.longitude,
                              coordinateSystem: CoordinateSystem.gcj02,
                            );
                            final wgs84 = ChinaCoordinateConverter.gcj02ToWgs84(
                              gcj02,
                            );
                            await widget.onSelect(
                              LocationSearchResult(
                                id: 'map-${wgs84.latitude.toStringAsFixed(5)}-${wgs84.longitude.toStringAsFixed(5)}',
                                name: '地图选点',
                                point: wgs84,
                              ),
                            );
                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                          },
                    icon: const Icon(Icons.check),
                    label: const Text('使用此地点'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
