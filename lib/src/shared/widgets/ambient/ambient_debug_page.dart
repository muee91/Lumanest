import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_canvas.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_composer.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_preset.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_rendering_policy.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_preview_override.dart';

class AmbientDebugPage extends ConsumerStatefulWidget {
  const AmbientDebugPage({super.key});

  @override
  ConsumerState<AmbientDebugPage> createState() => _AmbientDebugPageState();
}

class _AmbientDebugPageState extends ConsumerState<AmbientDebugPage> {
  late final Future<AmbientPresetBundle> _bundle = AmbientPresetBundle.load(
    rootBundle,
  );

  String _fixture = 'clearDay';
  AmbientQualityTier _quality = AmbientQualityTier.balanced;
  bool _conserveEnergy = false;
  double? _timeSpeed;
  double? _warpStrength;
  double? _blendSoftness;
  double? _rotationAmount;
  double? _noiseScale;

  final _fixtures = <String, ContextSnapshot Function()>{
    'clearDay': () => _scenarioSnapshot(
      id: 'debug-clear-day',
      weather: WeatherType.clear,
      phase: DayPhase.day,
    ),
    'cloudyDay': () => _scenarioSnapshot(
      id: 'debug-cloudy-day',
      weather: WeatherType.cloudy,
      phase: DayPhase.day,
      cloud: 78,
    ),
    'rain': () => _scenarioSnapshot(
      id: 'debug-rain',
      weather: WeatherType.rain,
      phase: DayPhase.day,
      wind: 9,
      precipitation: 5,
      cloud: 92,
    ),
    'snow': () => _scenarioSnapshot(
      id: 'debug-snow',
      weather: WeatherType.snow,
      phase: DayPhase.day,
      wind: 3,
      precipitation: 2,
      cloud: 86,
    ),
    'dust': () => _scenarioSnapshot(
      id: 'debug-dust',
      weather: WeatherType.dust,
      phase: DayPhase.day,
      wind: 14,
      cloud: 20,
    ),
    'clearDawn': () => _scenarioSnapshot(
      id: 'debug-clear-dawn',
      weather: WeatherType.clear,
      phase: DayPhase.dawn,
      cloud: 18,
    ),
    'clearSunset': () => _scenarioSnapshot(
      id: 'debug-clear-sunset',
      weather: WeatherType.clear,
      phase: DayPhase.sunset,
      cloud: 18,
    ),
    'blueHour': () => _scenarioSnapshot(
      id: 'debug-blue-hour',
      weather: WeatherType.clear,
      phase: DayPhase.blueHour,
    ),
    'night': () => _scenarioSnapshot(
      id: 'debug-night',
      weather: WeatherType.clear,
      phase: DayPhase.night,
    ),
    'stormSafety': () => _scenarioSnapshot(
      id: 'debug-storm-safety',
      weather: WeatherType.rain,
      phase: DayPhase.sunset,
      wind: 12,
      precipitation: 7,
      cloud: 96,
      safety: true,
    ),
    'typhoon': () => _scenarioSnapshot(
      id: 'debug-typhoon',
      weather: WeatherType.rain,
      phase: DayPhase.day,
      wind: 32,
      precipitation: 12,
      cloud: 95,
    ),
  };

  static const _fixtureLabels = <String, String>{
    'clearDay': '晴朗日间',
    'cloudyDay': '多云日间',
    'rain': '降雨',
    'snow': '降雪',
    'dust': '沙尘',
    'clearDawn': '晴朗日出',
    'clearSunset': '晴朗日落',
    'blueHour': '蓝调时刻',
    'night': '夜间',
    'stormSafety': '雷暴安全状态',
    'typhoon': '台风（风暴眼）',
  };

  static const _qualityLabels = <AmbientQualityTier, String>{
    AmbientQualityTier.full: '增强动效（60 帧）',
    AmbientQualityTier.balanced: '标准动效（30 帧）',
    AmbientQualityTier.reduced: '节能动效（15 帧）',
    AmbientQualityTier.static: '静态背景',
  };

  @override
  Widget build(BuildContext context) => FutureBuilder<AmbientPresetBundle>(
    future: _bundle,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          backgroundColor: _StudioColors.background,
          body: SafeArea(
            child: Center(
              child: Text(
                '背景预设加载失败：${snapshot.error}',
                style: const TextStyle(color: _StudioColors.ink),
              ),
            ),
          ),
        );
      }
      final bundle = snapshot.data;
      if (bundle == null) {
        return const Scaffold(
          backgroundColor: _StudioColors.background,
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return _buildStudio(context, bundle);
    },
  );

  Widget _buildStudio(BuildContext context, AmbientPresetBundle bundle) {
    final snapshot = _fixtures[_fixture]!();
    final visual = const AmbientVisualMapper().resolveSnapshot(
      snapshot,
      Brightness.light,
    );
    final preset = bundle.select(
      weather: snapshot.weather,
      dayPhase: snapshot.dayPhase,
      conserveEnergy: _conserveEnergy,
    );
    final composition = const AmbientComposer().compose(
      visualState: visual,
      preset: preset,
      quality: _quality,
    );
    final field = composition.field.copyWith(
      timeSpeed: _timeSpeed ?? composition.field.timeSpeed,
      warpStrength: _warpStrength ?? composition.field.warpStrength,
      blendSoftness: _blendSoftness ?? composition.field.blendSoftness,
      rotationAmountDegrees:
          _rotationAmount ?? composition.field.rotationAmountDegrees,
      noiseScale: _noiseScale ?? composition.field.noiseScale,
    );
    final previewComposition = AmbientVisualComposition(
      semanticState: visual,
      field: field,
      quality: _quality,
      transitionDuration: composition.transitionDuration,
    );
    final fixtureLabel = _fixtureLabels[_fixture]!;
    final qualityLabel = _qualityLabels[_quality]!;

    return Scaffold(
      backgroundColor: _StudioColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back),
                    color: _StudioColors.ink,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '动态背景实验室',
                          style: TextStyle(
                            color: _StudioColors.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '所有改动都会立即显示在下方预览中',
                          style: TextStyle(
                            color: _StudioColors.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_clearOverrides),
                    style: TextButton.styleFrom(
                      foregroundColor: _StudioColors.accent,
                    ),
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AmbientCanvas(
                        visualState: visual,
                        composition: previewComposition,
                        reduceMotion: _quality == AmbientQualityTier.static,
                        reduceFlashing: false,
                        showWeatherTexture: true,
                        renderer: AmbientRenderer.fragment,
                        intensity: 1,
                      ),
                      Positioned(
                        left: 14,
                        top: 14,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              '$fixtureLabel · $qualityLabel',
                              style: const TextStyle(
                                color: _StudioColors.ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '这是即时预览。调整不会永久保存；点击下方“应用到首页”后，可在首页按当前情景检查完整布局。',
                style: TextStyle(
                  color: _StudioColors.secondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    _sectionTitle('1. 选择要测试的情景'),
                    _selector<String>(
                      label: '天气与时间情景',
                      value: _fixture,
                      items: _fixtures.keys,
                      labelFor: (value) => _fixtureLabels[value]!,
                      onChanged: (value) => setState(() {
                        _fixture = value!;
                        _clearOverrides();
                      }),
                    ),
                    const SizedBox(height: 12),
                    _sectionTitle('2. 选择动效级别'),
                    _selector<AmbientQualityTier>(
                      label: '动态强度与刷新率',
                      value: _quality,
                      items: AmbientQualityTier.values,
                      labelFor: (value) => _qualityLabels[value]!,
                      onChanged: (value) => setState(() {
                        _quality = value!;
                        _clearOverrides();
                      }),
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: _StudioColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: _StudioColors.line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile.adaptive(
                        title: const Text(
                          '模拟低电量节能模式',
                          style: TextStyle(
                            color: _StudioColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: const Text(
                          '开启后背景应接近静态',
                          style: TextStyle(color: _StudioColors.secondary),
                        ),
                        value: _conserveEnergy,
                        activeTrackColor: _StudioColors.accent,
                        onChanged: (value) =>
                            setState(() => _conserveEnergy = value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        collapsedBackgroundColor: _StudioColors.surface,
                        backgroundColor: _StudioColors.surface,
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: _StudioColors.line),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: _StudioColors.line),
                        ),
                        iconColor: _StudioColors.ink,
                        collapsedIconColor: _StudioColors.ink,
                        title: const Text(
                          '高级参数（可选）',
                          style: TextStyle(
                            color: _StudioColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: const Text(
                          '只有需要放大观察差异时才调整',
                          style: TextStyle(color: _StudioColors.secondary),
                        ),
                        children: [
                          _slider(
                            '流动速度',
                            _timeSpeed ?? composition.field.timeSpeed,
                            0,
                            .8,
                            (value) => setState(() => _timeSpeed = value),
                          ),
                          _slider(
                            '形变强度',
                            _warpStrength ?? composition.field.warpStrength,
                            0,
                            1.8,
                            (value) => setState(() => _warpStrength = value),
                          ),
                          _slider(
                            '色彩融合',
                            _blendSoftness ?? composition.field.blendSoftness,
                            .2,
                            .92,
                            (value) => setState(() => _blendSoftness = value),
                          ),
                          _slider(
                            '旋转扰动',
                            _rotationAmount ??
                                composition.field.rotationAmountDegrees,
                            0,
                            620,
                            (value) => setState(() => _rotationAmount = value),
                          ),
                          _slider(
                            '纹理尺度',
                            _noiseScale ?? composition.field.noiseScale,
                            1.2,
                            3.2,
                            (value) => setState(() => _noiseScale = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () {
                        ref
                            .read(ambientPreviewOverrideProvider.notifier)
                            .set(
                              AmbientPreviewOverride(
                                snapshot: snapshot,
                                composition: previewComposition,
                                label: fixtureLabel,
                              ),
                            );
                        context.go('/today');
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _StudioColors.accent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.wb_sunny_outlined),
                      label: const Text('应用到首页并查看效果'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        ref
                            .read(ambientPreviewOverrideProvider.notifier)
                            .clear();
                        context.go('/today');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _StudioColors.ink,
                      ),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('清除首页调试预览'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前预设：${preset.label} · '
                      '最低文字对比度目标 ${preset.minTextContrast.toStringAsFixed(1)}:1',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _StudioColors.secondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selector<T>({
    required String label,
    required T value,
    required Iterable<T> items,
    String Function(T value)? labelFor,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      dropdownColor: _StudioColors.surface,
      style: const TextStyle(
        color: _StudioColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      iconEnabledColor: _StudioColors.ink,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _StudioColors.secondary),
        filled: true,
        fillColor: _StudioColors.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _StudioColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _StudioColors.accent, width: 2),
        ),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(
            value: item,
            child: Text(labelFor?.call(item) ?? item.toString()),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _StudioColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(color: _StudioColors.secondary),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: _StudioColors.accent,
          inactiveColor: _StudioColors.line,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      value,
      style: const TextStyle(
        color: _StudioColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w900,
      ),
    ),
  );

  void _clearOverrides() {
    _timeSpeed = null;
    _warpStrength = null;
    _blendSoftness = null;
    _rotationAmount = null;
    _noiseScale = null;
  }
}

abstract final class _StudioColors {
  static const background = Color(0xFFF5F5F1);
  static const surface = Colors.white;
  static const ink = Color(0xFF1E2523);
  static const secondary = Color(0xFF68706C);
  static const line = Color(0xFFD8DDD9);
  static const accent = Color(0xFF20A9DF);
}

ContextSnapshot _scenarioSnapshot({
  required String id,
  required WeatherType weather,
  required DayPhase phase,
  double wind = 2,
  double cloud = 35,
  double precipitation = 0,
  bool safety = false,
}) {
  final now = DateTime.utc(2026, 7, 19, 10);
  return ContextSnapshot(
    id: id,
    observedAt: now,
    expiresAt: now.add(const Duration(minutes: 20)),
    primaryScene: SceneType.lake,
    dayPhase: phase,
    weather: weather,
    activeRoute: false,
    windSpeedMetersPerSecond: wind,
    windDirectionDegrees: 285,
    cloudCoverPercent: cloud,
    precipitationMillimeters: precipitation,
    safetyEventIds: safety ? const ['thunderstorm'] : const [],
  );
}
