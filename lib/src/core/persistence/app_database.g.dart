// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SavedPlacesTable extends SavedPlaces
    with TableInfo<$SavedPlacesTable, SavedPlaceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedPlacesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    category,
    latitude,
    longitude,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_places';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedPlaceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedPlaceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedPlaceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
    );
  }

  @override
  $SavedPlacesTable createAlias(String alias) {
    return $SavedPlacesTable(attachedDatabase, alias);
  }
}

class SavedPlaceRow extends DataClass implements Insertable<SavedPlaceRow> {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  const SavedPlaceRow({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['category'] = Variable<String>(category);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    return map;
  }

  SavedPlacesCompanion toCompanion(bool nullToAbsent) {
    return SavedPlacesCompanion(
      id: Value(id),
      name: Value(name),
      category: Value(category),
      latitude: Value(latitude),
      longitude: Value(longitude),
    );
  }

  factory SavedPlaceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedPlaceRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      category: serializer.fromJson<String>(json['category']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'category': serializer.toJson<String>(category),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
    };
  }

  SavedPlaceRow copyWith({
    String? id,
    String? name,
    String? category,
    double? latitude,
    double? longitude,
  }) => SavedPlaceRow(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
  );
  SavedPlaceRow copyWithCompanion(SavedPlacesCompanion data) {
    return SavedPlaceRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      category: data.category.present ? data.category.value : this.category,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedPlaceRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, category, latitude, longitude);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedPlaceRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.category == this.category &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude);
}

class SavedPlacesCompanion extends UpdateCompanion<SavedPlaceRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> category;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<int> rowid;
  const SavedPlacesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.category = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedPlacesCompanion.insert({
    required String id,
    required String name,
    required String category,
    required double latitude,
    required double longitude,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       category = Value(category),
       latitude = Value(latitude),
       longitude = Value(longitude);
  static Insertable<SavedPlaceRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? category,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedPlacesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? category,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<int>? rowid,
  }) {
    return SavedPlacesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedPlacesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentRouteDestinationsTable extends RecentRouteDestinations
    with TableInfo<$RecentRouteDestinationsTable, RecentRouteDestinationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentRouteDestinationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _travelModeMeta = const VerificationMeta(
    'travelMode',
  );
  @override
  late final GeneratedColumn<String> travelMode = GeneratedColumn<String>(
    'travel_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    latitude,
    longitude,
    travelMode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_route_destinations';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecentRouteDestinationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('travel_mode')) {
      context.handle(
        _travelModeMeta,
        travelMode.isAcceptableOrUnknown(data['travel_mode']!, _travelModeMeta),
      );
    } else if (isInserting) {
      context.missing(_travelModeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecentRouteDestinationRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentRouteDestinationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      travelMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}travel_mode'],
      )!,
    );
  }

  @override
  $RecentRouteDestinationsTable createAlias(String alias) {
    return $RecentRouteDestinationsTable(attachedDatabase, alias);
  }
}

class RecentRouteDestinationRow extends DataClass
    implements Insertable<RecentRouteDestinationRow> {
  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final String travelMode;
  const RecentRouteDestinationRow({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.travelMode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['travel_mode'] = Variable<String>(travelMode);
    return map;
  }

  RecentRouteDestinationsCompanion toCompanion(bool nullToAbsent) {
    return RecentRouteDestinationsCompanion(
      id: Value(id),
      name: Value(name),
      latitude: Value(latitude),
      longitude: Value(longitude),
      travelMode: Value(travelMode),
    );
  }

  factory RecentRouteDestinationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentRouteDestinationRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      travelMode: serializer.fromJson<String>(json['travelMode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'travelMode': serializer.toJson<String>(travelMode),
    };
  }

  RecentRouteDestinationRow copyWith({
    int? id,
    String? name,
    double? latitude,
    double? longitude,
    String? travelMode,
  }) => RecentRouteDestinationRow(
    id: id ?? this.id,
    name: name ?? this.name,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    travelMode: travelMode ?? this.travelMode,
  );
  RecentRouteDestinationRow copyWithCompanion(
    RecentRouteDestinationsCompanion data,
  ) {
    return RecentRouteDestinationRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      travelMode: data.travelMode.present
          ? data.travelMode.value
          : this.travelMode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentRouteDestinationRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('travelMode: $travelMode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, latitude, longitude, travelMode);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentRouteDestinationRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.travelMode == this.travelMode);
}

class RecentRouteDestinationsCompanion
    extends UpdateCompanion<RecentRouteDestinationRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<String> travelMode;
  const RecentRouteDestinationsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.travelMode = const Value.absent(),
  });
  RecentRouteDestinationsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required double latitude,
    required double longitude,
    required String travelMode,
  }) : name = Value(name),
       latitude = Value(latitude),
       longitude = Value(longitude),
       travelMode = Value(travelMode);
  static Insertable<RecentRouteDestinationRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? travelMode,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (travelMode != null) 'travel_mode': travelMode,
    });
  }

  RecentRouteDestinationsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<String>? travelMode,
  }) {
    return RecentRouteDestinationsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      travelMode: travelMode ?? this.travelMode,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (travelMode.present) {
      map['travel_mode'] = Variable<String>(travelMode.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentRouteDestinationsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('travelMode: $travelMode')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SavedPlacesTable savedPlaces = $SavedPlacesTable(this);
  late final $RecentRouteDestinationsTable recentRouteDestinations =
      $RecentRouteDestinationsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    savedPlaces,
    recentRouteDestinations,
  ];
}

typedef $$SavedPlacesTableCreateCompanionBuilder =
    SavedPlacesCompanion Function({
      required String id,
      required String name,
      required String category,
      required double latitude,
      required double longitude,
      Value<int> rowid,
    });
typedef $$SavedPlacesTableUpdateCompanionBuilder =
    SavedPlacesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> category,
      Value<double> latitude,
      Value<double> longitude,
      Value<int> rowid,
    });

class $$SavedPlacesTableFilterComposer
    extends Composer<_$AppDatabase, $SavedPlacesTable> {
  $$SavedPlacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedPlacesTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedPlacesTable> {
  $$SavedPlacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedPlacesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedPlacesTable> {
  $$SavedPlacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);
}

class $$SavedPlacesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedPlacesTable,
          SavedPlaceRow,
          $$SavedPlacesTableFilterComposer,
          $$SavedPlacesTableOrderingComposer,
          $$SavedPlacesTableAnnotationComposer,
          $$SavedPlacesTableCreateCompanionBuilder,
          $$SavedPlacesTableUpdateCompanionBuilder,
          (
            SavedPlaceRow,
            BaseReferences<_$AppDatabase, $SavedPlacesTable, SavedPlaceRow>,
          ),
          SavedPlaceRow,
          PrefetchHooks Function()
        > {
  $$SavedPlacesTableTableManager(_$AppDatabase db, $SavedPlacesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedPlacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedPlacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedPlacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedPlacesCompanion(
                id: id,
                name: name,
                category: category,
                latitude: latitude,
                longitude: longitude,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String category,
                required double latitude,
                required double longitude,
                Value<int> rowid = const Value.absent(),
              }) => SavedPlacesCompanion.insert(
                id: id,
                name: name,
                category: category,
                latitude: latitude,
                longitude: longitude,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedPlacesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedPlacesTable,
      SavedPlaceRow,
      $$SavedPlacesTableFilterComposer,
      $$SavedPlacesTableOrderingComposer,
      $$SavedPlacesTableAnnotationComposer,
      $$SavedPlacesTableCreateCompanionBuilder,
      $$SavedPlacesTableUpdateCompanionBuilder,
      (
        SavedPlaceRow,
        BaseReferences<_$AppDatabase, $SavedPlacesTable, SavedPlaceRow>,
      ),
      SavedPlaceRow,
      PrefetchHooks Function()
    >;
typedef $$RecentRouteDestinationsTableCreateCompanionBuilder =
    RecentRouteDestinationsCompanion Function({
      Value<int> id,
      required String name,
      required double latitude,
      required double longitude,
      required String travelMode,
    });
typedef $$RecentRouteDestinationsTableUpdateCompanionBuilder =
    RecentRouteDestinationsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<double> latitude,
      Value<double> longitude,
      Value<String> travelMode,
    });

class $$RecentRouteDestinationsTableFilterComposer
    extends Composer<_$AppDatabase, $RecentRouteDestinationsTable> {
  $$RecentRouteDestinationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get travelMode => $composableBuilder(
    column: $table.travelMode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecentRouteDestinationsTableOrderingComposer
    extends Composer<_$AppDatabase, $RecentRouteDestinationsTable> {
  $$RecentRouteDestinationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get travelMode => $composableBuilder(
    column: $table.travelMode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecentRouteDestinationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecentRouteDestinationsTable> {
  $$RecentRouteDestinationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get travelMode => $composableBuilder(
    column: $table.travelMode,
    builder: (column) => column,
  );
}

class $$RecentRouteDestinationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecentRouteDestinationsTable,
          RecentRouteDestinationRow,
          $$RecentRouteDestinationsTableFilterComposer,
          $$RecentRouteDestinationsTableOrderingComposer,
          $$RecentRouteDestinationsTableAnnotationComposer,
          $$RecentRouteDestinationsTableCreateCompanionBuilder,
          $$RecentRouteDestinationsTableUpdateCompanionBuilder,
          (
            RecentRouteDestinationRow,
            BaseReferences<
              _$AppDatabase,
              $RecentRouteDestinationsTable,
              RecentRouteDestinationRow
            >,
          ),
          RecentRouteDestinationRow,
          PrefetchHooks Function()
        > {
  $$RecentRouteDestinationsTableTableManager(
    _$AppDatabase db,
    $RecentRouteDestinationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentRouteDestinationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RecentRouteDestinationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RecentRouteDestinationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<String> travelMode = const Value.absent(),
              }) => RecentRouteDestinationsCompanion(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                travelMode: travelMode,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required double latitude,
                required double longitude,
                required String travelMode,
              }) => RecentRouteDestinationsCompanion.insert(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                travelMode: travelMode,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecentRouteDestinationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecentRouteDestinationsTable,
      RecentRouteDestinationRow,
      $$RecentRouteDestinationsTableFilterComposer,
      $$RecentRouteDestinationsTableOrderingComposer,
      $$RecentRouteDestinationsTableAnnotationComposer,
      $$RecentRouteDestinationsTableCreateCompanionBuilder,
      $$RecentRouteDestinationsTableUpdateCompanionBuilder,
      (
        RecentRouteDestinationRow,
        BaseReferences<
          _$AppDatabase,
          $RecentRouteDestinationsTable,
          RecentRouteDestinationRow
        >,
      ),
      RecentRouteDestinationRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SavedPlacesTableTableManager get savedPlaces =>
      $$SavedPlacesTableTableManager(_db, _db.savedPlaces);
  $$RecentRouteDestinationsTableTableManager get recentRouteDestinations =>
      $$RecentRouteDestinationsTableTableManager(
        _db,
        _db.recentRouteDestinations,
      );
}
