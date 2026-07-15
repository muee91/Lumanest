import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    ref.read(manualLocationProvider.notifier).select(result);
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
