import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('SavedPlaceRow')
class SavedPlaces extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (latitude BETWEEN -90 AND 90)',
    'CHECK (longitude BETWEEN -180 AND 180)',
  ];
}

@DataClassName('RecentRouteDestinationRow')
class RecentRouteDestinations extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get name => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get travelMode => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (id = 1)',
    'CHECK (latitude BETWEEN -90 AND 90)',
    'CHECK (longitude BETWEEN -180 AND 180)',
    "CHECK (travel_mode IN ('driving', 'walking'))",
  ];
}

@DriftDatabase(tables: [SavedPlaces, RecentRouteDestinations])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.production() => AppDatabase(_openConnection());
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

/// Overridden by the Flutter test bootstrap so widget tests never open or
/// mutate the device database. Production keeps the durable factory.
AppDatabase Function() appDatabaseFactory = AppDatabase.production;

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = appDatabaseFactory();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(path.join(directory.path, 'lumanest.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
