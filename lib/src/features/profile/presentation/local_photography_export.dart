import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../library/domain/user_library.dart';

/// Writes a user-requested photography-only export to device storage.
///
/// The export deliberately uses [UserLibraryState.toExportJson], which omits
/// preferences, diagnostics and cached environment history. Android exposes
/// the app's Downloads directory; platforms without one fall back to the
/// app's documents directory instead of sending the data anywhere.
abstract interface class LocalPhotographyExportService {
  Future<String> export(UserLibraryState library);
}

class DeviceLocalPhotographyExportService
    implements LocalPhotographyExportService {
  const DeviceLocalPhotographyExportService({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  @override
  Future<String> export(UserLibraryState library) async {
    final root =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final target = Directory(path.join(root.path, 'LumaNest'));
    await target.create(recursive: true);
    final timestamp = _now().toLocal().toIso8601String().replaceAll(':', '-');
    final file = File(path.join(target.path, 'photography-$timestamp.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(library.toExportJson()),
      flush: true,
    );
    return file.path;
  }
}

final localPhotographyExportServiceProvider =
    Provider<LocalPhotographyExportService>((ref) {
      return const DeviceLocalPhotographyExportService();
    });
