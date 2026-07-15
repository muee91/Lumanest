import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';
import 'package:luma_nest/src/features/route/infrastructure/gpx_track_parser.dart';

abstract interface class GpxTrackImportService {
  Future<ImportedRouteTrack?> pickAndParse();
}

class FileSelectorGpxTrackImportService implements GpxTrackImportService {
  FileSelectorGpxTrackImportService({
    this.parser = const GpxTrackParser(),
    Future<XFile?> Function()? pickFile,
    DateTime Function()? now,
  }) : _pickFile = pickFile ?? _pickGpxFile,
       _now = now ?? DateTime.now;

  final GpxTrackParser parser;
  final Future<XFile?> Function() _pickFile;
  final DateTime Function() _now;

  @override
  Future<ImportedRouteTrack?> pickAndParse() async {
    final file = await _pickFile();
    if (file == null) return null;
    try {
      if (await file.length() > parser.maximumBytes) {
        throw const GpxTrackFailure(GpxTrackFailureKind.tooLarge);
      }
      return parser.parse(
        await file.readAsBytes(),
        fallbackName: file.name,
        importedAt: _now(),
      );
    } on GpxTrackFailure {
      rethrow;
    } on Object {
      throw const GpxTrackFailure(GpxTrackFailureKind.unreadable);
    }
  }

  static Future<XFile?> _pickGpxFile() => openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'GPX 轨迹', extensions: ['gpx']),
    ],
    confirmButtonText: '导入',
  );
}

final gpxTrackImportServiceProvider = Provider<GpxTrackImportService>((ref) {
  return FileSelectorGpxTrackImportService();
});
