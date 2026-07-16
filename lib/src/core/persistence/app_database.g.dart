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

class $SavedRoutesTable extends SavedRoutes
    with TableInfo<$SavedRoutesTable, SavedRouteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedRoutesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    latitude,
    longitude,
    travelMode,
    savedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_routes';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedRouteRow> instance, {
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
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedRouteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedRouteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
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
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      )!,
    );
  }

  @override
  $SavedRoutesTable createAlias(String alias) {
    return $SavedRoutesTable(attachedDatabase, alias);
  }
}

class SavedRouteRow extends DataClass implements Insertable<SavedRouteRow> {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String travelMode;
  final DateTime savedAt;
  const SavedRouteRow({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.travelMode,
    required this.savedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['travel_mode'] = Variable<String>(travelMode);
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  SavedRoutesCompanion toCompanion(bool nullToAbsent) {
    return SavedRoutesCompanion(
      id: Value(id),
      name: Value(name),
      latitude: Value(latitude),
      longitude: Value(longitude),
      travelMode: Value(travelMode),
      savedAt: Value(savedAt),
    );
  }

  factory SavedRouteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedRouteRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      travelMode: serializer.fromJson<String>(json['travelMode']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'travelMode': serializer.toJson<String>(travelMode),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  SavedRouteRow copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    String? travelMode,
    DateTime? savedAt,
  }) => SavedRouteRow(
    id: id ?? this.id,
    name: name ?? this.name,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    travelMode: travelMode ?? this.travelMode,
    savedAt: savedAt ?? this.savedAt,
  );
  SavedRouteRow copyWithCompanion(SavedRoutesCompanion data) {
    return SavedRouteRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      travelMode: data.travelMode.present
          ? data.travelMode.value
          : this.travelMode,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedRouteRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('travelMode: $travelMode, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, latitude, longitude, travelMode, savedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedRouteRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.travelMode == this.travelMode &&
          other.savedAt == this.savedAt);
}

class SavedRoutesCompanion extends UpdateCompanion<SavedRouteRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<String> travelMode;
  final Value<DateTime> savedAt;
  final Value<int> rowid;
  const SavedRoutesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.travelMode = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedRoutesCompanion.insert({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
    required String travelMode,
    required DateTime savedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       latitude = Value(latitude),
       longitude = Value(longitude),
       travelMode = Value(travelMode),
       savedAt = Value(savedAt);
  static Insertable<SavedRouteRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? travelMode,
    Expression<DateTime>? savedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (travelMode != null) 'travel_mode': travelMode,
      if (savedAt != null) 'saved_at': savedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedRoutesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<String>? travelMode,
    Value<DateTime>? savedAt,
    Value<int>? rowid,
  }) {
    return SavedRoutesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      travelMode: travelMode ?? this.travelMode,
      savedAt: savedAt ?? this.savedAt,
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
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (travelMode.present) {
      map['travel_mode'] = Variable<String>(travelMode.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedRoutesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('travelMode: $travelMode, ')
          ..write('savedAt: $savedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedJourneysTable extends SavedJourneys
    with TableInfo<$SavedJourneysTable, SavedJourneyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedJourneysTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _routeKeyMeta = const VerificationMeta(
    'routeKey',
  );
  @override
  late final GeneratedColumn<String> routeKey = GeneratedColumn<String>(
    'route_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    latitude,
    longitude,
    travelMode,
    routeKey,
    startedAt,
    endedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_journeys';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedJourneyRow> instance, {
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
    if (data.containsKey('route_key')) {
      context.handle(
        _routeKeyMeta,
        routeKey.isAcceptableOrUnknown(data['route_key']!, _routeKeyMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedJourneyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedJourneyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
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
      routeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_key'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
    );
  }

  @override
  $SavedJourneysTable createAlias(String alias) {
    return $SavedJourneysTable(attachedDatabase, alias);
  }
}

class SavedJourneyRow extends DataClass implements Insertable<SavedJourneyRow> {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String travelMode;
  final String? routeKey;
  final DateTime startedAt;
  final DateTime? endedAt;
  const SavedJourneyRow({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.travelMode,
    this.routeKey,
    required this.startedAt,
    this.endedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['travel_mode'] = Variable<String>(travelMode);
    if (!nullToAbsent || routeKey != null) {
      map['route_key'] = Variable<String>(routeKey);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    return map;
  }

  SavedJourneysCompanion toCompanion(bool nullToAbsent) {
    return SavedJourneysCompanion(
      id: Value(id),
      name: Value(name),
      latitude: Value(latitude),
      longitude: Value(longitude),
      travelMode: Value(travelMode),
      routeKey: routeKey == null && nullToAbsent
          ? const Value.absent()
          : Value(routeKey),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
    );
  }

  factory SavedJourneyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedJourneyRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      travelMode: serializer.fromJson<String>(json['travelMode']),
      routeKey: serializer.fromJson<String?>(json['routeKey']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'travelMode': serializer.toJson<String>(travelMode),
      'routeKey': serializer.toJson<String?>(routeKey),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
    };
  }

  SavedJourneyRow copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    String? travelMode,
    Value<String?> routeKey = const Value.absent(),
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
  }) => SavedJourneyRow(
    id: id ?? this.id,
    name: name ?? this.name,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    travelMode: travelMode ?? this.travelMode,
    routeKey: routeKey.present ? routeKey.value : this.routeKey,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
  );
  SavedJourneyRow copyWithCompanion(SavedJourneysCompanion data) {
    return SavedJourneyRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      travelMode: data.travelMode.present
          ? data.travelMode.value
          : this.travelMode,
      routeKey: data.routeKey.present ? data.routeKey.value : this.routeKey,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedJourneyRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('travelMode: $travelMode, ')
          ..write('routeKey: $routeKey, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    latitude,
    longitude,
    travelMode,
    routeKey,
    startedAt,
    endedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedJourneyRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.travelMode == this.travelMode &&
          other.routeKey == this.routeKey &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt);
}

class SavedJourneysCompanion extends UpdateCompanion<SavedJourneyRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<String> travelMode;
  final Value<String?> routeKey;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int> rowid;
  const SavedJourneysCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.travelMode = const Value.absent(),
    this.routeKey = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedJourneysCompanion.insert({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
    required String travelMode,
    this.routeKey = const Value.absent(),
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       latitude = Value(latitude),
       longitude = Value(longitude),
       travelMode = Value(travelMode),
       startedAt = Value(startedAt);
  static Insertable<SavedJourneyRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? travelMode,
    Expression<String>? routeKey,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (travelMode != null) 'travel_mode': travelMode,
      if (routeKey != null) 'route_key': routeKey,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedJourneysCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<String>? travelMode,
    Value<String?>? routeKey,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<int>? rowid,
  }) {
    return SavedJourneysCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      travelMode: travelMode ?? this.travelMode,
      routeKey: routeKey ?? this.routeKey,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
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
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (travelMode.present) {
      map['travel_mode'] = Variable<String>(travelMode.value);
    }
    if (routeKey.present) {
      map['route_key'] = Variable<String>(routeKey.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedJourneysCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('travelMode: $travelMode, ')
          ..write('routeKey: $routeKey, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportedRouteTracksTable extends ImportedRouteTracks
    with TableInfo<$ImportedRouteTracksTable, ImportedRouteTrackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportedRouteTracksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<DateTime> importedAt = GeneratedColumn<DateTime>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pointsJsonMeta = const VerificationMeta(
    'pointsJson',
  );
  @override
  late final GeneratedColumn<String> pointsJson = GeneratedColumn<String>(
    'points_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<int> distanceMeters = GeneratedColumn<int>(
    'distance_meters',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationEstimatedMeta = const VerificationMeta(
    'durationEstimated',
  );
  @override
  late final GeneratedColumn<bool> durationEstimated = GeneratedColumn<bool>(
    'duration_estimated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("duration_estimated" IN (0, 1))',
    ),
  );
  static const VerificationMeta _ascentMetersMeta = const VerificationMeta(
    'ascentMeters',
  );
  @override
  late final GeneratedColumn<int> ascentMeters = GeneratedColumn<int>(
    'ascent_meters',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descentMetersMeta = const VerificationMeta(
    'descentMeters',
  );
  @override
  late final GeneratedColumn<int> descentMeters = GeneratedColumn<int>(
    'descent_meters',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    importedAt,
    pointsJson,
    distanceMeters,
    durationSeconds,
    durationEstimated,
    ascentMeters,
    descentMeters,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imported_route_tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportedRouteTrackRow> instance, {
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
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    if (data.containsKey('points_json')) {
      context.handle(
        _pointsJsonMeta,
        pointsJson.isAcceptableOrUnknown(data['points_json']!, _pointsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_pointsJsonMeta);
    }
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_distanceMetersMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecondsMeta);
    }
    if (data.containsKey('duration_estimated')) {
      context.handle(
        _durationEstimatedMeta,
        durationEstimated.isAcceptableOrUnknown(
          data['duration_estimated']!,
          _durationEstimatedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationEstimatedMeta);
    }
    if (data.containsKey('ascent_meters')) {
      context.handle(
        _ascentMetersMeta,
        ascentMeters.isAcceptableOrUnknown(
          data['ascent_meters']!,
          _ascentMetersMeta,
        ),
      );
    }
    if (data.containsKey('descent_meters')) {
      context.handle(
        _descentMetersMeta,
        descentMeters.isAcceptableOrUnknown(
          data['descent_meters']!,
          _descentMetersMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportedRouteTrackRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportedRouteTrackRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}imported_at'],
      )!,
      pointsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}points_json'],
      )!,
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distance_meters'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      durationEstimated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}duration_estimated'],
      )!,
      ascentMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ascent_meters'],
      ),
      descentMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}descent_meters'],
      ),
    );
  }

  @override
  $ImportedRouteTracksTable createAlias(String alias) {
    return $ImportedRouteTracksTable(attachedDatabase, alias);
  }
}

class ImportedRouteTrackRow extends DataClass
    implements Insertable<ImportedRouteTrackRow> {
  final String id;
  final String name;
  final DateTime importedAt;
  final String pointsJson;
  final int distanceMeters;
  final int durationSeconds;
  final bool durationEstimated;
  final int? ascentMeters;
  final int? descentMeters;
  const ImportedRouteTrackRow({
    required this.id,
    required this.name,
    required this.importedAt,
    required this.pointsJson,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.durationEstimated,
    this.ascentMeters,
    this.descentMeters,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['imported_at'] = Variable<DateTime>(importedAt);
    map['points_json'] = Variable<String>(pointsJson);
    map['distance_meters'] = Variable<int>(distanceMeters);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['duration_estimated'] = Variable<bool>(durationEstimated);
    if (!nullToAbsent || ascentMeters != null) {
      map['ascent_meters'] = Variable<int>(ascentMeters);
    }
    if (!nullToAbsent || descentMeters != null) {
      map['descent_meters'] = Variable<int>(descentMeters);
    }
    return map;
  }

  ImportedRouteTracksCompanion toCompanion(bool nullToAbsent) {
    return ImportedRouteTracksCompanion(
      id: Value(id),
      name: Value(name),
      importedAt: Value(importedAt),
      pointsJson: Value(pointsJson),
      distanceMeters: Value(distanceMeters),
      durationSeconds: Value(durationSeconds),
      durationEstimated: Value(durationEstimated),
      ascentMeters: ascentMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(ascentMeters),
      descentMeters: descentMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(descentMeters),
    );
  }

  factory ImportedRouteTrackRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportedRouteTrackRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      importedAt: serializer.fromJson<DateTime>(json['importedAt']),
      pointsJson: serializer.fromJson<String>(json['pointsJson']),
      distanceMeters: serializer.fromJson<int>(json['distanceMeters']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      durationEstimated: serializer.fromJson<bool>(json['durationEstimated']),
      ascentMeters: serializer.fromJson<int?>(json['ascentMeters']),
      descentMeters: serializer.fromJson<int?>(json['descentMeters']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'importedAt': serializer.toJson<DateTime>(importedAt),
      'pointsJson': serializer.toJson<String>(pointsJson),
      'distanceMeters': serializer.toJson<int>(distanceMeters),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'durationEstimated': serializer.toJson<bool>(durationEstimated),
      'ascentMeters': serializer.toJson<int?>(ascentMeters),
      'descentMeters': serializer.toJson<int?>(descentMeters),
    };
  }

  ImportedRouteTrackRow copyWith({
    String? id,
    String? name,
    DateTime? importedAt,
    String? pointsJson,
    int? distanceMeters,
    int? durationSeconds,
    bool? durationEstimated,
    Value<int?> ascentMeters = const Value.absent(),
    Value<int?> descentMeters = const Value.absent(),
  }) => ImportedRouteTrackRow(
    id: id ?? this.id,
    name: name ?? this.name,
    importedAt: importedAt ?? this.importedAt,
    pointsJson: pointsJson ?? this.pointsJson,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    durationEstimated: durationEstimated ?? this.durationEstimated,
    ascentMeters: ascentMeters.present ? ascentMeters.value : this.ascentMeters,
    descentMeters: descentMeters.present
        ? descentMeters.value
        : this.descentMeters,
  );
  ImportedRouteTrackRow copyWithCompanion(ImportedRouteTracksCompanion data) {
    return ImportedRouteTrackRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      pointsJson: data.pointsJson.present
          ? data.pointsJson.value
          : this.pointsJson,
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      durationEstimated: data.durationEstimated.present
          ? data.durationEstimated.value
          : this.durationEstimated,
      ascentMeters: data.ascentMeters.present
          ? data.ascentMeters.value
          : this.ascentMeters,
      descentMeters: data.descentMeters.present
          ? data.descentMeters.value
          : this.descentMeters,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportedRouteTrackRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('importedAt: $importedAt, ')
          ..write('pointsJson: $pointsJson, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('durationEstimated: $durationEstimated, ')
          ..write('ascentMeters: $ascentMeters, ')
          ..write('descentMeters: $descentMeters')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    importedAt,
    pointsJson,
    distanceMeters,
    durationSeconds,
    durationEstimated,
    ascentMeters,
    descentMeters,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportedRouteTrackRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.importedAt == this.importedAt &&
          other.pointsJson == this.pointsJson &&
          other.distanceMeters == this.distanceMeters &&
          other.durationSeconds == this.durationSeconds &&
          other.durationEstimated == this.durationEstimated &&
          other.ascentMeters == this.ascentMeters &&
          other.descentMeters == this.descentMeters);
}

class ImportedRouteTracksCompanion
    extends UpdateCompanion<ImportedRouteTrackRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> importedAt;
  final Value<String> pointsJson;
  final Value<int> distanceMeters;
  final Value<int> durationSeconds;
  final Value<bool> durationEstimated;
  final Value<int?> ascentMeters;
  final Value<int?> descentMeters;
  final Value<int> rowid;
  const ImportedRouteTracksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.pointsJson = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.durationEstimated = const Value.absent(),
    this.ascentMeters = const Value.absent(),
    this.descentMeters = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportedRouteTracksCompanion.insert({
    required String id,
    required String name,
    required DateTime importedAt,
    required String pointsJson,
    required int distanceMeters,
    required int durationSeconds,
    required bool durationEstimated,
    this.ascentMeters = const Value.absent(),
    this.descentMeters = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       importedAt = Value(importedAt),
       pointsJson = Value(pointsJson),
       distanceMeters = Value(distanceMeters),
       durationSeconds = Value(durationSeconds),
       durationEstimated = Value(durationEstimated);
  static Insertable<ImportedRouteTrackRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? importedAt,
    Expression<String>? pointsJson,
    Expression<int>? distanceMeters,
    Expression<int>? durationSeconds,
    Expression<bool>? durationEstimated,
    Expression<int>? ascentMeters,
    Expression<int>? descentMeters,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (importedAt != null) 'imported_at': importedAt,
      if (pointsJson != null) 'points_json': pointsJson,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (durationEstimated != null) 'duration_estimated': durationEstimated,
      if (ascentMeters != null) 'ascent_meters': ascentMeters,
      if (descentMeters != null) 'descent_meters': descentMeters,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportedRouteTracksCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? importedAt,
    Value<String>? pointsJson,
    Value<int>? distanceMeters,
    Value<int>? durationSeconds,
    Value<bool>? durationEstimated,
    Value<int?>? ascentMeters,
    Value<int?>? descentMeters,
    Value<int>? rowid,
  }) {
    return ImportedRouteTracksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      importedAt: importedAt ?? this.importedAt,
      pointsJson: pointsJson ?? this.pointsJson,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      durationEstimated: durationEstimated ?? this.durationEstimated,
      ascentMeters: ascentMeters ?? this.ascentMeters,
      descentMeters: descentMeters ?? this.descentMeters,
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
    if (importedAt.present) {
      map['imported_at'] = Variable<DateTime>(importedAt.value);
    }
    if (pointsJson.present) {
      map['points_json'] = Variable<String>(pointsJson.value);
    }
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<int>(distanceMeters.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (durationEstimated.present) {
      map['duration_estimated'] = Variable<bool>(durationEstimated.value);
    }
    if (ascentMeters.present) {
      map['ascent_meters'] = Variable<int>(ascentMeters.value);
    }
    if (descentMeters.present) {
      map['descent_meters'] = Variable<int>(descentMeters.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportedRouteTracksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('importedAt: $importedAt, ')
          ..write('pointsJson: $pointsJson, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('durationEstimated: $durationEstimated, ')
          ..write('ascentMeters: $ascentMeters, ')
          ..write('descentMeters: $descentMeters, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfilePreferenceRecordsTable extends ProfilePreferenceRecords
    with TableInfo<$ProfilePreferenceRecordsTable, ProfilePreferenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilePreferenceRecordsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _ambientBackgroundEnabledMeta =
      const VerificationMeta('ambientBackgroundEnabled');
  @override
  late final GeneratedColumn<bool> ambientBackgroundEnabled =
      GeneratedColumn<bool>(
        'ambient_background_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("ambient_background_enabled" IN (0, 1))',
        ),
      );
  static const VerificationMeta _reduceMotionMeta = const VerificationMeta(
    'reduceMotion',
  );
  @override
  late final GeneratedColumn<bool> reduceMotion = GeneratedColumn<bool>(
    'reduce_motion',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reduce_motion" IN (0, 1))',
    ),
  );
  static const VerificationMeta _reduceFlashingMeta = const VerificationMeta(
    'reduceFlashing',
  );
  @override
  late final GeneratedColumn<bool> reduceFlashing = GeneratedColumn<bool>(
    'reduce_flashing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reduce_flashing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _highContrastMeta = const VerificationMeta(
    'highContrast',
  );
  @override
  late final GeneratedColumn<bool> highContrast = GeneratedColumn<bool>(
    'high_contrast',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("high_contrast" IN (0, 1))',
    ),
  );
  static const VerificationMeta _ambientMotionModeMeta = const VerificationMeta(
    'ambientMotionMode',
  );
  @override
  late final GeneratedColumn<String> ambientMotionMode =
      GeneratedColumn<String>(
        'ambient_motion_mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _photographyPreferencesJsonMeta =
      const VerificationMeta('photographyPreferencesJson');
  @override
  late final GeneratedColumn<String> photographyPreferencesJson =
      GeneratedColumn<String>(
        'photography_preferences_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _activityPreferencesJsonMeta =
      const VerificationMeta('activityPreferencesJson');
  @override
  late final GeneratedColumn<String> activityPreferencesJson =
      GeneratedColumn<String>(
        'activity_preferences_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _equipmentListMeta = const VerificationMeta(
    'equipmentList',
  );
  @override
  late final GeneratedColumn<String> equipmentList = GeneratedColumn<String>(
    'equipment_list',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aiToneMeta = const VerificationMeta('aiTone');
  @override
  late final GeneratedColumn<String> aiTone = GeneratedColumn<String>(
    'ai_tone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recommendationIntensityMeta =
      const VerificationMeta('recommendationIntensity');
  @override
  late final GeneratedColumn<double> recommendationIntensity =
      GeneratedColumn<double>(
        'recommendation_intensity',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ambientBackgroundEnabled,
    reduceMotion,
    reduceFlashing,
    highContrast,
    ambientMotionMode,
    photographyPreferencesJson,
    activityPreferencesJson,
    equipmentList,
    aiTone,
    recommendationIntensity,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfilePreferenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ambient_background_enabled')) {
      context.handle(
        _ambientBackgroundEnabledMeta,
        ambientBackgroundEnabled.isAcceptableOrUnknown(
          data['ambient_background_enabled']!,
          _ambientBackgroundEnabledMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ambientBackgroundEnabledMeta);
    }
    if (data.containsKey('reduce_motion')) {
      context.handle(
        _reduceMotionMeta,
        reduceMotion.isAcceptableOrUnknown(
          data['reduce_motion']!,
          _reduceMotionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reduceMotionMeta);
    }
    if (data.containsKey('reduce_flashing')) {
      context.handle(
        _reduceFlashingMeta,
        reduceFlashing.isAcceptableOrUnknown(
          data['reduce_flashing']!,
          _reduceFlashingMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reduceFlashingMeta);
    }
    if (data.containsKey('high_contrast')) {
      context.handle(
        _highContrastMeta,
        highContrast.isAcceptableOrUnknown(
          data['high_contrast']!,
          _highContrastMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_highContrastMeta);
    }
    if (data.containsKey('ambient_motion_mode')) {
      context.handle(
        _ambientMotionModeMeta,
        ambientMotionMode.isAcceptableOrUnknown(
          data['ambient_motion_mode']!,
          _ambientMotionModeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ambientMotionModeMeta);
    }
    if (data.containsKey('photography_preferences_json')) {
      context.handle(
        _photographyPreferencesJsonMeta,
        photographyPreferencesJson.isAcceptableOrUnknown(
          data['photography_preferences_json']!,
          _photographyPreferencesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_photographyPreferencesJsonMeta);
    }
    if (data.containsKey('activity_preferences_json')) {
      context.handle(
        _activityPreferencesJsonMeta,
        activityPreferencesJson.isAcceptableOrUnknown(
          data['activity_preferences_json']!,
          _activityPreferencesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activityPreferencesJsonMeta);
    }
    if (data.containsKey('equipment_list')) {
      context.handle(
        _equipmentListMeta,
        equipmentList.isAcceptableOrUnknown(
          data['equipment_list']!,
          _equipmentListMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_equipmentListMeta);
    }
    if (data.containsKey('ai_tone')) {
      context.handle(
        _aiToneMeta,
        aiTone.isAcceptableOrUnknown(data['ai_tone']!, _aiToneMeta),
      );
    } else if (isInserting) {
      context.missing(_aiToneMeta);
    }
    if (data.containsKey('recommendation_intensity')) {
      context.handle(
        _recommendationIntensityMeta,
        recommendationIntensity.isAcceptableOrUnknown(
          data['recommendation_intensity']!,
          _recommendationIntensityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recommendationIntensityMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfilePreferenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfilePreferenceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      ambientBackgroundEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}ambient_background_enabled'],
      )!,
      reduceMotion: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reduce_motion'],
      )!,
      reduceFlashing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reduce_flashing'],
      )!,
      highContrast: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}high_contrast'],
      )!,
      ambientMotionMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ambient_motion_mode'],
      )!,
      photographyPreferencesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photography_preferences_json'],
      )!,
      activityPreferencesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_preferences_json'],
      )!,
      equipmentList: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}equipment_list'],
      )!,
      aiTone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_tone'],
      )!,
      recommendationIntensity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}recommendation_intensity'],
      )!,
    );
  }

  @override
  $ProfilePreferenceRecordsTable createAlias(String alias) {
    return $ProfilePreferenceRecordsTable(attachedDatabase, alias);
  }
}

class ProfilePreferenceRow extends DataClass
    implements Insertable<ProfilePreferenceRow> {
  final int id;
  final bool ambientBackgroundEnabled;
  final bool reduceMotion;
  final bool reduceFlashing;
  final bool highContrast;
  final String ambientMotionMode;
  final String photographyPreferencesJson;
  final String activityPreferencesJson;
  final String equipmentList;
  final String aiTone;
  final double recommendationIntensity;
  const ProfilePreferenceRow({
    required this.id,
    required this.ambientBackgroundEnabled,
    required this.reduceMotion,
    required this.reduceFlashing,
    required this.highContrast,
    required this.ambientMotionMode,
    required this.photographyPreferencesJson,
    required this.activityPreferencesJson,
    required this.equipmentList,
    required this.aiTone,
    required this.recommendationIntensity,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['ambient_background_enabled'] = Variable<bool>(
      ambientBackgroundEnabled,
    );
    map['reduce_motion'] = Variable<bool>(reduceMotion);
    map['reduce_flashing'] = Variable<bool>(reduceFlashing);
    map['high_contrast'] = Variable<bool>(highContrast);
    map['ambient_motion_mode'] = Variable<String>(ambientMotionMode);
    map['photography_preferences_json'] = Variable<String>(
      photographyPreferencesJson,
    );
    map['activity_preferences_json'] = Variable<String>(
      activityPreferencesJson,
    );
    map['equipment_list'] = Variable<String>(equipmentList);
    map['ai_tone'] = Variable<String>(aiTone);
    map['recommendation_intensity'] = Variable<double>(recommendationIntensity);
    return map;
  }

  ProfilePreferenceRecordsCompanion toCompanion(bool nullToAbsent) {
    return ProfilePreferenceRecordsCompanion(
      id: Value(id),
      ambientBackgroundEnabled: Value(ambientBackgroundEnabled),
      reduceMotion: Value(reduceMotion),
      reduceFlashing: Value(reduceFlashing),
      highContrast: Value(highContrast),
      ambientMotionMode: Value(ambientMotionMode),
      photographyPreferencesJson: Value(photographyPreferencesJson),
      activityPreferencesJson: Value(activityPreferencesJson),
      equipmentList: Value(equipmentList),
      aiTone: Value(aiTone),
      recommendationIntensity: Value(recommendationIntensity),
    );
  }

  factory ProfilePreferenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfilePreferenceRow(
      id: serializer.fromJson<int>(json['id']),
      ambientBackgroundEnabled: serializer.fromJson<bool>(
        json['ambientBackgroundEnabled'],
      ),
      reduceMotion: serializer.fromJson<bool>(json['reduceMotion']),
      reduceFlashing: serializer.fromJson<bool>(json['reduceFlashing']),
      highContrast: serializer.fromJson<bool>(json['highContrast']),
      ambientMotionMode: serializer.fromJson<String>(json['ambientMotionMode']),
      photographyPreferencesJson: serializer.fromJson<String>(
        json['photographyPreferencesJson'],
      ),
      activityPreferencesJson: serializer.fromJson<String>(
        json['activityPreferencesJson'],
      ),
      equipmentList: serializer.fromJson<String>(json['equipmentList']),
      aiTone: serializer.fromJson<String>(json['aiTone']),
      recommendationIntensity: serializer.fromJson<double>(
        json['recommendationIntensity'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ambientBackgroundEnabled': serializer.toJson<bool>(
        ambientBackgroundEnabled,
      ),
      'reduceMotion': serializer.toJson<bool>(reduceMotion),
      'reduceFlashing': serializer.toJson<bool>(reduceFlashing),
      'highContrast': serializer.toJson<bool>(highContrast),
      'ambientMotionMode': serializer.toJson<String>(ambientMotionMode),
      'photographyPreferencesJson': serializer.toJson<String>(
        photographyPreferencesJson,
      ),
      'activityPreferencesJson': serializer.toJson<String>(
        activityPreferencesJson,
      ),
      'equipmentList': serializer.toJson<String>(equipmentList),
      'aiTone': serializer.toJson<String>(aiTone),
      'recommendationIntensity': serializer.toJson<double>(
        recommendationIntensity,
      ),
    };
  }

  ProfilePreferenceRow copyWith({
    int? id,
    bool? ambientBackgroundEnabled,
    bool? reduceMotion,
    bool? reduceFlashing,
    bool? highContrast,
    String? ambientMotionMode,
    String? photographyPreferencesJson,
    String? activityPreferencesJson,
    String? equipmentList,
    String? aiTone,
    double? recommendationIntensity,
  }) => ProfilePreferenceRow(
    id: id ?? this.id,
    ambientBackgroundEnabled:
        ambientBackgroundEnabled ?? this.ambientBackgroundEnabled,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    reduceFlashing: reduceFlashing ?? this.reduceFlashing,
    highContrast: highContrast ?? this.highContrast,
    ambientMotionMode: ambientMotionMode ?? this.ambientMotionMode,
    photographyPreferencesJson:
        photographyPreferencesJson ?? this.photographyPreferencesJson,
    activityPreferencesJson:
        activityPreferencesJson ?? this.activityPreferencesJson,
    equipmentList: equipmentList ?? this.equipmentList,
    aiTone: aiTone ?? this.aiTone,
    recommendationIntensity:
        recommendationIntensity ?? this.recommendationIntensity,
  );
  ProfilePreferenceRow copyWithCompanion(
    ProfilePreferenceRecordsCompanion data,
  ) {
    return ProfilePreferenceRow(
      id: data.id.present ? data.id.value : this.id,
      ambientBackgroundEnabled: data.ambientBackgroundEnabled.present
          ? data.ambientBackgroundEnabled.value
          : this.ambientBackgroundEnabled,
      reduceMotion: data.reduceMotion.present
          ? data.reduceMotion.value
          : this.reduceMotion,
      reduceFlashing: data.reduceFlashing.present
          ? data.reduceFlashing.value
          : this.reduceFlashing,
      highContrast: data.highContrast.present
          ? data.highContrast.value
          : this.highContrast,
      ambientMotionMode: data.ambientMotionMode.present
          ? data.ambientMotionMode.value
          : this.ambientMotionMode,
      photographyPreferencesJson: data.photographyPreferencesJson.present
          ? data.photographyPreferencesJson.value
          : this.photographyPreferencesJson,
      activityPreferencesJson: data.activityPreferencesJson.present
          ? data.activityPreferencesJson.value
          : this.activityPreferencesJson,
      equipmentList: data.equipmentList.present
          ? data.equipmentList.value
          : this.equipmentList,
      aiTone: data.aiTone.present ? data.aiTone.value : this.aiTone,
      recommendationIntensity: data.recommendationIntensity.present
          ? data.recommendationIntensity.value
          : this.recommendationIntensity,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfilePreferenceRow(')
          ..write('id: $id, ')
          ..write('ambientBackgroundEnabled: $ambientBackgroundEnabled, ')
          ..write('reduceMotion: $reduceMotion, ')
          ..write('reduceFlashing: $reduceFlashing, ')
          ..write('highContrast: $highContrast, ')
          ..write('ambientMotionMode: $ambientMotionMode, ')
          ..write('photographyPreferencesJson: $photographyPreferencesJson, ')
          ..write('activityPreferencesJson: $activityPreferencesJson, ')
          ..write('equipmentList: $equipmentList, ')
          ..write('aiTone: $aiTone, ')
          ..write('recommendationIntensity: $recommendationIntensity')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ambientBackgroundEnabled,
    reduceMotion,
    reduceFlashing,
    highContrast,
    ambientMotionMode,
    photographyPreferencesJson,
    activityPreferencesJson,
    equipmentList,
    aiTone,
    recommendationIntensity,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfilePreferenceRow &&
          other.id == this.id &&
          other.ambientBackgroundEnabled == this.ambientBackgroundEnabled &&
          other.reduceMotion == this.reduceMotion &&
          other.reduceFlashing == this.reduceFlashing &&
          other.highContrast == this.highContrast &&
          other.ambientMotionMode == this.ambientMotionMode &&
          other.photographyPreferencesJson == this.photographyPreferencesJson &&
          other.activityPreferencesJson == this.activityPreferencesJson &&
          other.equipmentList == this.equipmentList &&
          other.aiTone == this.aiTone &&
          other.recommendationIntensity == this.recommendationIntensity);
}

class ProfilePreferenceRecordsCompanion
    extends UpdateCompanion<ProfilePreferenceRow> {
  final Value<int> id;
  final Value<bool> ambientBackgroundEnabled;
  final Value<bool> reduceMotion;
  final Value<bool> reduceFlashing;
  final Value<bool> highContrast;
  final Value<String> ambientMotionMode;
  final Value<String> photographyPreferencesJson;
  final Value<String> activityPreferencesJson;
  final Value<String> equipmentList;
  final Value<String> aiTone;
  final Value<double> recommendationIntensity;
  const ProfilePreferenceRecordsCompanion({
    this.id = const Value.absent(),
    this.ambientBackgroundEnabled = const Value.absent(),
    this.reduceMotion = const Value.absent(),
    this.reduceFlashing = const Value.absent(),
    this.highContrast = const Value.absent(),
    this.ambientMotionMode = const Value.absent(),
    this.photographyPreferencesJson = const Value.absent(),
    this.activityPreferencesJson = const Value.absent(),
    this.equipmentList = const Value.absent(),
    this.aiTone = const Value.absent(),
    this.recommendationIntensity = const Value.absent(),
  });
  ProfilePreferenceRecordsCompanion.insert({
    this.id = const Value.absent(),
    required bool ambientBackgroundEnabled,
    required bool reduceMotion,
    required bool reduceFlashing,
    required bool highContrast,
    required String ambientMotionMode,
    required String photographyPreferencesJson,
    required String activityPreferencesJson,
    required String equipmentList,
    required String aiTone,
    required double recommendationIntensity,
  }) : ambientBackgroundEnabled = Value(ambientBackgroundEnabled),
       reduceMotion = Value(reduceMotion),
       reduceFlashing = Value(reduceFlashing),
       highContrast = Value(highContrast),
       ambientMotionMode = Value(ambientMotionMode),
       photographyPreferencesJson = Value(photographyPreferencesJson),
       activityPreferencesJson = Value(activityPreferencesJson),
       equipmentList = Value(equipmentList),
       aiTone = Value(aiTone),
       recommendationIntensity = Value(recommendationIntensity);
  static Insertable<ProfilePreferenceRow> custom({
    Expression<int>? id,
    Expression<bool>? ambientBackgroundEnabled,
    Expression<bool>? reduceMotion,
    Expression<bool>? reduceFlashing,
    Expression<bool>? highContrast,
    Expression<String>? ambientMotionMode,
    Expression<String>? photographyPreferencesJson,
    Expression<String>? activityPreferencesJson,
    Expression<String>? equipmentList,
    Expression<String>? aiTone,
    Expression<double>? recommendationIntensity,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ambientBackgroundEnabled != null)
        'ambient_background_enabled': ambientBackgroundEnabled,
      if (reduceMotion != null) 'reduce_motion': reduceMotion,
      if (reduceFlashing != null) 'reduce_flashing': reduceFlashing,
      if (highContrast != null) 'high_contrast': highContrast,
      if (ambientMotionMode != null) 'ambient_motion_mode': ambientMotionMode,
      if (photographyPreferencesJson != null)
        'photography_preferences_json': photographyPreferencesJson,
      if (activityPreferencesJson != null)
        'activity_preferences_json': activityPreferencesJson,
      if (equipmentList != null) 'equipment_list': equipmentList,
      if (aiTone != null) 'ai_tone': aiTone,
      if (recommendationIntensity != null)
        'recommendation_intensity': recommendationIntensity,
    });
  }

  ProfilePreferenceRecordsCompanion copyWith({
    Value<int>? id,
    Value<bool>? ambientBackgroundEnabled,
    Value<bool>? reduceMotion,
    Value<bool>? reduceFlashing,
    Value<bool>? highContrast,
    Value<String>? ambientMotionMode,
    Value<String>? photographyPreferencesJson,
    Value<String>? activityPreferencesJson,
    Value<String>? equipmentList,
    Value<String>? aiTone,
    Value<double>? recommendationIntensity,
  }) {
    return ProfilePreferenceRecordsCompanion(
      id: id ?? this.id,
      ambientBackgroundEnabled:
          ambientBackgroundEnabled ?? this.ambientBackgroundEnabled,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      reduceFlashing: reduceFlashing ?? this.reduceFlashing,
      highContrast: highContrast ?? this.highContrast,
      ambientMotionMode: ambientMotionMode ?? this.ambientMotionMode,
      photographyPreferencesJson:
          photographyPreferencesJson ?? this.photographyPreferencesJson,
      activityPreferencesJson:
          activityPreferencesJson ?? this.activityPreferencesJson,
      equipmentList: equipmentList ?? this.equipmentList,
      aiTone: aiTone ?? this.aiTone,
      recommendationIntensity:
          recommendationIntensity ?? this.recommendationIntensity,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ambientBackgroundEnabled.present) {
      map['ambient_background_enabled'] = Variable<bool>(
        ambientBackgroundEnabled.value,
      );
    }
    if (reduceMotion.present) {
      map['reduce_motion'] = Variable<bool>(reduceMotion.value);
    }
    if (reduceFlashing.present) {
      map['reduce_flashing'] = Variable<bool>(reduceFlashing.value);
    }
    if (highContrast.present) {
      map['high_contrast'] = Variable<bool>(highContrast.value);
    }
    if (ambientMotionMode.present) {
      map['ambient_motion_mode'] = Variable<String>(ambientMotionMode.value);
    }
    if (photographyPreferencesJson.present) {
      map['photography_preferences_json'] = Variable<String>(
        photographyPreferencesJson.value,
      );
    }
    if (activityPreferencesJson.present) {
      map['activity_preferences_json'] = Variable<String>(
        activityPreferencesJson.value,
      );
    }
    if (equipmentList.present) {
      map['equipment_list'] = Variable<String>(equipmentList.value);
    }
    if (aiTone.present) {
      map['ai_tone'] = Variable<String>(aiTone.value);
    }
    if (recommendationIntensity.present) {
      map['recommendation_intensity'] = Variable<double>(
        recommendationIntensity.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilePreferenceRecordsCompanion(')
          ..write('id: $id, ')
          ..write('ambientBackgroundEnabled: $ambientBackgroundEnabled, ')
          ..write('reduceMotion: $reduceMotion, ')
          ..write('reduceFlashing: $reduceFlashing, ')
          ..write('highContrast: $highContrast, ')
          ..write('ambientMotionMode: $ambientMotionMode, ')
          ..write('photographyPreferencesJson: $photographyPreferencesJson, ')
          ..write('activityPreferencesJson: $activityPreferencesJson, ')
          ..write('equipmentList: $equipmentList, ')
          ..write('aiTone: $aiTone, ')
          ..write('recommendationIntensity: $recommendationIntensity')
          ..write(')'))
        .toString();
  }
}

class $BaseRegionsTable extends BaseRegions
    with TableInfo<$BaseRegionsTable, BaseRegionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BaseRegionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _selectedAtMeta = const VerificationMeta(
    'selectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> selectedAt = GeneratedColumn<DateTime>(
    'selected_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    address,
    latitude,
    longitude,
    selectedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'base_regions';
  @override
  VerificationContext validateIntegrity(
    Insertable<BaseRegionRow> instance, {
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
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
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
    if (data.containsKey('selected_at')) {
      context.handle(
        _selectedAtMeta,
        selectedAt.isAcceptableOrUnknown(data['selected_at']!, _selectedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_selectedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BaseRegionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BaseRegionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      selectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}selected_at'],
      )!,
    );
  }

  @override
  $BaseRegionsTable createAlias(String alias) {
    return $BaseRegionsTable(attachedDatabase, alias);
  }
}

class BaseRegionRow extends DataClass implements Insertable<BaseRegionRow> {
  final int id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final DateTime selectedAt;
  const BaseRegionRow({
    required this.id,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    required this.selectedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['selected_at'] = Variable<DateTime>(selectedAt);
    return map;
  }

  BaseRegionsCompanion toCompanion(bool nullToAbsent) {
    return BaseRegionsCompanion(
      id: Value(id),
      name: Value(name),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      latitude: Value(latitude),
      longitude: Value(longitude),
      selectedAt: Value(selectedAt),
    );
  }

  factory BaseRegionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BaseRegionRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      address: serializer.fromJson<String?>(json['address']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      selectedAt: serializer.fromJson<DateTime>(json['selectedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'address': serializer.toJson<String?>(address),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'selectedAt': serializer.toJson<DateTime>(selectedAt),
    };
  }

  BaseRegionRow copyWith({
    int? id,
    String? name,
    Value<String?> address = const Value.absent(),
    double? latitude,
    double? longitude,
    DateTime? selectedAt,
  }) => BaseRegionRow(
    id: id ?? this.id,
    name: name ?? this.name,
    address: address.present ? address.value : this.address,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    selectedAt: selectedAt ?? this.selectedAt,
  );
  BaseRegionRow copyWithCompanion(BaseRegionsCompanion data) {
    return BaseRegionRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      address: data.address.present ? data.address.value : this.address,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      selectedAt: data.selectedAt.present
          ? data.selectedAt.value
          : this.selectedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BaseRegionRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('selectedAt: $selectedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, address, latitude, longitude, selectedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BaseRegionRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.address == this.address &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.selectedAt == this.selectedAt);
}

class BaseRegionsCompanion extends UpdateCompanion<BaseRegionRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> address;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<DateTime> selectedAt;
  const BaseRegionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.selectedAt = const Value.absent(),
  });
  BaseRegionsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.address = const Value.absent(),
    required double latitude,
    required double longitude,
    required DateTime selectedAt,
  }) : name = Value(name),
       latitude = Value(latitude),
       longitude = Value(longitude),
       selectedAt = Value(selectedAt);
  static Insertable<BaseRegionRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? address,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<DateTime>? selectedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (selectedAt != null) 'selected_at': selectedAt,
    });
  }

  BaseRegionsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? address,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<DateTime>? selectedAt,
  }) {
    return BaseRegionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      selectedAt: selectedAt ?? this.selectedAt,
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
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (selectedAt.present) {
      map['selected_at'] = Variable<DateTime>(selectedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BaseRegionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('selectedAt: $selectedAt')
          ..write(')'))
        .toString();
  }
}

class $SavedInspirationNotesTable extends SavedInspirationNotes
    with TableInfo<$SavedInspirationNotesTable, SavedInspirationNoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedInspirationNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNoteIdMeta = const VerificationMeta(
    'sourceNoteId',
  );
  @override
  late final GeneratedColumn<String> sourceNoteId = GeneratedColumn<String>(
    'source_note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('saved-note'),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
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
  static const VerificationMeta _actionNameMeta = const VerificationMeta(
    'actionName',
  );
  @override
  late final GeneratedColumn<String> actionName = GeneratedColumn<String>(
    'action_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorityUrlMeta = const VerificationMeta(
    'authorityUrl',
  );
  @override
  late final GeneratedColumn<String> authorityUrl = GeneratedColumn<String>(
    'authority_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceNoteId,
    label,
    emoji,
    category,
    actionName,
    detail,
    authorityUrl,
    savedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_inspiration_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedInspirationNoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_note_id')) {
      context.handle(
        _sourceNoteIdMeta,
        sourceNoteId.isAcceptableOrUnknown(
          data['source_note_id']!,
          _sourceNoteIdMeta,
        ),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    } else if (isInserting) {
      context.missing(_emojiMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('action_name')) {
      context.handle(
        _actionNameMeta,
        actionName.isAcceptableOrUnknown(data['action_name']!, _actionNameMeta),
      );
    } else if (isInserting) {
      context.missing(_actionNameMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    } else if (isInserting) {
      context.missing(_detailMeta);
    }
    if (data.containsKey('authority_url')) {
      context.handle(
        _authorityUrlMeta,
        authorityUrl.isAcceptableOrUnknown(
          data['authority_url']!,
          _authorityUrlMeta,
        ),
      );
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedInspirationNoteRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedInspirationNoteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceNoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_note_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      actionName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_name'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      )!,
      authorityUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}authority_url'],
      ),
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      )!,
    );
  }

  @override
  $SavedInspirationNotesTable createAlias(String alias) {
    return $SavedInspirationNotesTable(attachedDatabase, alias);
  }
}

class SavedInspirationNoteRow extends DataClass
    implements Insertable<SavedInspirationNoteRow> {
  final String id;
  final String sourceNoteId;
  final String label;
  final String emoji;
  final String category;
  final String actionName;
  final String detail;
  final String? authorityUrl;
  final DateTime savedAt;
  const SavedInspirationNoteRow({
    required this.id,
    required this.sourceNoteId,
    required this.label,
    required this.emoji,
    required this.category,
    required this.actionName,
    required this.detail,
    this.authorityUrl,
    required this.savedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_note_id'] = Variable<String>(sourceNoteId);
    map['label'] = Variable<String>(label);
    map['emoji'] = Variable<String>(emoji);
    map['category'] = Variable<String>(category);
    map['action_name'] = Variable<String>(actionName);
    map['detail'] = Variable<String>(detail);
    if (!nullToAbsent || authorityUrl != null) {
      map['authority_url'] = Variable<String>(authorityUrl);
    }
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  SavedInspirationNotesCompanion toCompanion(bool nullToAbsent) {
    return SavedInspirationNotesCompanion(
      id: Value(id),
      sourceNoteId: Value(sourceNoteId),
      label: Value(label),
      emoji: Value(emoji),
      category: Value(category),
      actionName: Value(actionName),
      detail: Value(detail),
      authorityUrl: authorityUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(authorityUrl),
      savedAt: Value(savedAt),
    );
  }

  factory SavedInspirationNoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedInspirationNoteRow(
      id: serializer.fromJson<String>(json['id']),
      sourceNoteId: serializer.fromJson<String>(json['sourceNoteId']),
      label: serializer.fromJson<String>(json['label']),
      emoji: serializer.fromJson<String>(json['emoji']),
      category: serializer.fromJson<String>(json['category']),
      actionName: serializer.fromJson<String>(json['actionName']),
      detail: serializer.fromJson<String>(json['detail']),
      authorityUrl: serializer.fromJson<String?>(json['authorityUrl']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceNoteId': serializer.toJson<String>(sourceNoteId),
      'label': serializer.toJson<String>(label),
      'emoji': serializer.toJson<String>(emoji),
      'category': serializer.toJson<String>(category),
      'actionName': serializer.toJson<String>(actionName),
      'detail': serializer.toJson<String>(detail),
      'authorityUrl': serializer.toJson<String?>(authorityUrl),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  SavedInspirationNoteRow copyWith({
    String? id,
    String? sourceNoteId,
    String? label,
    String? emoji,
    String? category,
    String? actionName,
    String? detail,
    Value<String?> authorityUrl = const Value.absent(),
    DateTime? savedAt,
  }) => SavedInspirationNoteRow(
    id: id ?? this.id,
    sourceNoteId: sourceNoteId ?? this.sourceNoteId,
    label: label ?? this.label,
    emoji: emoji ?? this.emoji,
    category: category ?? this.category,
    actionName: actionName ?? this.actionName,
    detail: detail ?? this.detail,
    authorityUrl: authorityUrl.present ? authorityUrl.value : this.authorityUrl,
    savedAt: savedAt ?? this.savedAt,
  );
  SavedInspirationNoteRow copyWithCompanion(
    SavedInspirationNotesCompanion data,
  ) {
    return SavedInspirationNoteRow(
      id: data.id.present ? data.id.value : this.id,
      sourceNoteId: data.sourceNoteId.present
          ? data.sourceNoteId.value
          : this.sourceNoteId,
      label: data.label.present ? data.label.value : this.label,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      category: data.category.present ? data.category.value : this.category,
      actionName: data.actionName.present
          ? data.actionName.value
          : this.actionName,
      detail: data.detail.present ? data.detail.value : this.detail,
      authorityUrl: data.authorityUrl.present
          ? data.authorityUrl.value
          : this.authorityUrl,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedInspirationNoteRow(')
          ..write('id: $id, ')
          ..write('sourceNoteId: $sourceNoteId, ')
          ..write('label: $label, ')
          ..write('emoji: $emoji, ')
          ..write('category: $category, ')
          ..write('actionName: $actionName, ')
          ..write('detail: $detail, ')
          ..write('authorityUrl: $authorityUrl, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceNoteId,
    label,
    emoji,
    category,
    actionName,
    detail,
    authorityUrl,
    savedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedInspirationNoteRow &&
          other.id == this.id &&
          other.sourceNoteId == this.sourceNoteId &&
          other.label == this.label &&
          other.emoji == this.emoji &&
          other.category == this.category &&
          other.actionName == this.actionName &&
          other.detail == this.detail &&
          other.authorityUrl == this.authorityUrl &&
          other.savedAt == this.savedAt);
}

class SavedInspirationNotesCompanion
    extends UpdateCompanion<SavedInspirationNoteRow> {
  final Value<String> id;
  final Value<String> sourceNoteId;
  final Value<String> label;
  final Value<String> emoji;
  final Value<String> category;
  final Value<String> actionName;
  final Value<String> detail;
  final Value<String?> authorityUrl;
  final Value<DateTime> savedAt;
  final Value<int> rowid;
  const SavedInspirationNotesCompanion({
    this.id = const Value.absent(),
    this.sourceNoteId = const Value.absent(),
    this.label = const Value.absent(),
    this.emoji = const Value.absent(),
    this.category = const Value.absent(),
    this.actionName = const Value.absent(),
    this.detail = const Value.absent(),
    this.authorityUrl = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedInspirationNotesCompanion.insert({
    required String id,
    this.sourceNoteId = const Value.absent(),
    required String label,
    required String emoji,
    required String category,
    required String actionName,
    required String detail,
    this.authorityUrl = const Value.absent(),
    required DateTime savedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       label = Value(label),
       emoji = Value(emoji),
       category = Value(category),
       actionName = Value(actionName),
       detail = Value(detail),
       savedAt = Value(savedAt);
  static Insertable<SavedInspirationNoteRow> custom({
    Expression<String>? id,
    Expression<String>? sourceNoteId,
    Expression<String>? label,
    Expression<String>? emoji,
    Expression<String>? category,
    Expression<String>? actionName,
    Expression<String>? detail,
    Expression<String>? authorityUrl,
    Expression<DateTime>? savedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceNoteId != null) 'source_note_id': sourceNoteId,
      if (label != null) 'label': label,
      if (emoji != null) 'emoji': emoji,
      if (category != null) 'category': category,
      if (actionName != null) 'action_name': actionName,
      if (detail != null) 'detail': detail,
      if (authorityUrl != null) 'authority_url': authorityUrl,
      if (savedAt != null) 'saved_at': savedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedInspirationNotesCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceNoteId,
    Value<String>? label,
    Value<String>? emoji,
    Value<String>? category,
    Value<String>? actionName,
    Value<String>? detail,
    Value<String?>? authorityUrl,
    Value<DateTime>? savedAt,
    Value<int>? rowid,
  }) {
    return SavedInspirationNotesCompanion(
      id: id ?? this.id,
      sourceNoteId: sourceNoteId ?? this.sourceNoteId,
      label: label ?? this.label,
      emoji: emoji ?? this.emoji,
      category: category ?? this.category,
      actionName: actionName ?? this.actionName,
      detail: detail ?? this.detail,
      authorityUrl: authorityUrl ?? this.authorityUrl,
      savedAt: savedAt ?? this.savedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceNoteId.present) {
      map['source_note_id'] = Variable<String>(sourceNoteId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (actionName.present) {
      map['action_name'] = Variable<String>(actionName.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (authorityUrl.present) {
      map['authority_url'] = Variable<String>(authorityUrl.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedInspirationNotesCompanion(')
          ..write('id: $id, ')
          ..write('sourceNoteId: $sourceNoteId, ')
          ..write('label: $label, ')
          ..write('emoji: $emoji, ')
          ..write('category: $category, ')
          ..write('actionName: $actionName, ')
          ..write('detail: $detail, ')
          ..write('authorityUrl: $authorityUrl, ')
          ..write('savedAt: $savedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WildlifeMapLayerCachesTable extends WildlifeMapLayerCaches
    with TableInfo<$WildlifeMapLayerCachesTable, WildlifeMapLayerCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WildlifeMapLayerCachesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _centerLatitudeMeta = const VerificationMeta(
    'centerLatitude',
  );
  @override
  late final GeneratedColumn<double> centerLatitude = GeneratedColumn<double>(
    'center_latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _centerLongitudeMeta = const VerificationMeta(
    'centerLongitude',
  );
  @override
  late final GeneratedColumn<double> centerLongitude = GeneratedColumn<double>(
    'center_longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _radiusKilometersMeta = const VerificationMeta(
    'radiusKilometers',
  );
  @override
  late final GeneratedColumn<int> radiusKilometers = GeneratedColumn<int>(
    'radius_kilometers',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generatedAtMeta = const VerificationMeta(
    'generatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> generatedAt = GeneratedColumn<DateTime>(
    'generated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    centerLatitude,
    centerLongitude,
    radiusKilometers,
    savedAt,
    generatedAt,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wildlife_map_layer_caches';
  @override
  VerificationContext validateIntegrity(
    Insertable<WildlifeMapLayerCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('center_latitude')) {
      context.handle(
        _centerLatitudeMeta,
        centerLatitude.isAcceptableOrUnknown(
          data['center_latitude']!,
          _centerLatitudeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_centerLatitudeMeta);
    }
    if (data.containsKey('center_longitude')) {
      context.handle(
        _centerLongitudeMeta,
        centerLongitude.isAcceptableOrUnknown(
          data['center_longitude']!,
          _centerLongitudeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_centerLongitudeMeta);
    }
    if (data.containsKey('radius_kilometers')) {
      context.handle(
        _radiusKilometersMeta,
        radiusKilometers.isAcceptableOrUnknown(
          data['radius_kilometers']!,
          _radiusKilometersMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_radiusKilometersMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('generated_at')) {
      context.handle(
        _generatedAtMeta,
        generatedAt.isAcceptableOrUnknown(
          data['generated_at']!,
          _generatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_generatedAtMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WildlifeMapLayerCacheRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WildlifeMapLayerCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      centerLatitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}center_latitude'],
      )!,
      centerLongitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}center_longitude'],
      )!,
      radiusKilometers: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}radius_kilometers'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      )!,
      generatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}generated_at'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $WildlifeMapLayerCachesTable createAlias(String alias) {
    return $WildlifeMapLayerCachesTable(attachedDatabase, alias);
  }
}

class WildlifeMapLayerCacheRow extends DataClass
    implements Insertable<WildlifeMapLayerCacheRow> {
  final String id;
  final double centerLatitude;
  final double centerLongitude;
  final int radiusKilometers;
  final DateTime savedAt;
  final DateTime generatedAt;
  final String payloadJson;
  const WildlifeMapLayerCacheRow({
    required this.id,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.radiusKilometers,
    required this.savedAt,
    required this.generatedAt,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['center_latitude'] = Variable<double>(centerLatitude);
    map['center_longitude'] = Variable<double>(centerLongitude);
    map['radius_kilometers'] = Variable<int>(radiusKilometers);
    map['saved_at'] = Variable<DateTime>(savedAt);
    map['generated_at'] = Variable<DateTime>(generatedAt);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  WildlifeMapLayerCachesCompanion toCompanion(bool nullToAbsent) {
    return WildlifeMapLayerCachesCompanion(
      id: Value(id),
      centerLatitude: Value(centerLatitude),
      centerLongitude: Value(centerLongitude),
      radiusKilometers: Value(radiusKilometers),
      savedAt: Value(savedAt),
      generatedAt: Value(generatedAt),
      payloadJson: Value(payloadJson),
    );
  }

  factory WildlifeMapLayerCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WildlifeMapLayerCacheRow(
      id: serializer.fromJson<String>(json['id']),
      centerLatitude: serializer.fromJson<double>(json['centerLatitude']),
      centerLongitude: serializer.fromJson<double>(json['centerLongitude']),
      radiusKilometers: serializer.fromJson<int>(json['radiusKilometers']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
      generatedAt: serializer.fromJson<DateTime>(json['generatedAt']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'centerLatitude': serializer.toJson<double>(centerLatitude),
      'centerLongitude': serializer.toJson<double>(centerLongitude),
      'radiusKilometers': serializer.toJson<int>(radiusKilometers),
      'savedAt': serializer.toJson<DateTime>(savedAt),
      'generatedAt': serializer.toJson<DateTime>(generatedAt),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  WildlifeMapLayerCacheRow copyWith({
    String? id,
    double? centerLatitude,
    double? centerLongitude,
    int? radiusKilometers,
    DateTime? savedAt,
    DateTime? generatedAt,
    String? payloadJson,
  }) => WildlifeMapLayerCacheRow(
    id: id ?? this.id,
    centerLatitude: centerLatitude ?? this.centerLatitude,
    centerLongitude: centerLongitude ?? this.centerLongitude,
    radiusKilometers: radiusKilometers ?? this.radiusKilometers,
    savedAt: savedAt ?? this.savedAt,
    generatedAt: generatedAt ?? this.generatedAt,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  WildlifeMapLayerCacheRow copyWithCompanion(
    WildlifeMapLayerCachesCompanion data,
  ) {
    return WildlifeMapLayerCacheRow(
      id: data.id.present ? data.id.value : this.id,
      centerLatitude: data.centerLatitude.present
          ? data.centerLatitude.value
          : this.centerLatitude,
      centerLongitude: data.centerLongitude.present
          ? data.centerLongitude.value
          : this.centerLongitude,
      radiusKilometers: data.radiusKilometers.present
          ? data.radiusKilometers.value
          : this.radiusKilometers,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      generatedAt: data.generatedAt.present
          ? data.generatedAt.value
          : this.generatedAt,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WildlifeMapLayerCacheRow(')
          ..write('id: $id, ')
          ..write('centerLatitude: $centerLatitude, ')
          ..write('centerLongitude: $centerLongitude, ')
          ..write('radiusKilometers: $radiusKilometers, ')
          ..write('savedAt: $savedAt, ')
          ..write('generatedAt: $generatedAt, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    centerLatitude,
    centerLongitude,
    radiusKilometers,
    savedAt,
    generatedAt,
    payloadJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WildlifeMapLayerCacheRow &&
          other.id == this.id &&
          other.centerLatitude == this.centerLatitude &&
          other.centerLongitude == this.centerLongitude &&
          other.radiusKilometers == this.radiusKilometers &&
          other.savedAt == this.savedAt &&
          other.generatedAt == this.generatedAt &&
          other.payloadJson == this.payloadJson);
}

class WildlifeMapLayerCachesCompanion
    extends UpdateCompanion<WildlifeMapLayerCacheRow> {
  final Value<String> id;
  final Value<double> centerLatitude;
  final Value<double> centerLongitude;
  final Value<int> radiusKilometers;
  final Value<DateTime> savedAt;
  final Value<DateTime> generatedAt;
  final Value<String> payloadJson;
  final Value<int> rowid;
  const WildlifeMapLayerCachesCompanion({
    this.id = const Value.absent(),
    this.centerLatitude = const Value.absent(),
    this.centerLongitude = const Value.absent(),
    this.radiusKilometers = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.generatedAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WildlifeMapLayerCachesCompanion.insert({
    required String id,
    required double centerLatitude,
    required double centerLongitude,
    required int radiusKilometers,
    required DateTime savedAt,
    required DateTime generatedAt,
    required String payloadJson,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       centerLatitude = Value(centerLatitude),
       centerLongitude = Value(centerLongitude),
       radiusKilometers = Value(radiusKilometers),
       savedAt = Value(savedAt),
       generatedAt = Value(generatedAt),
       payloadJson = Value(payloadJson);
  static Insertable<WildlifeMapLayerCacheRow> custom({
    Expression<String>? id,
    Expression<double>? centerLatitude,
    Expression<double>? centerLongitude,
    Expression<int>? radiusKilometers,
    Expression<DateTime>? savedAt,
    Expression<DateTime>? generatedAt,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (centerLatitude != null) 'center_latitude': centerLatitude,
      if (centerLongitude != null) 'center_longitude': centerLongitude,
      if (radiusKilometers != null) 'radius_kilometers': radiusKilometers,
      if (savedAt != null) 'saved_at': savedAt,
      if (generatedAt != null) 'generated_at': generatedAt,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WildlifeMapLayerCachesCompanion copyWith({
    Value<String>? id,
    Value<double>? centerLatitude,
    Value<double>? centerLongitude,
    Value<int>? radiusKilometers,
    Value<DateTime>? savedAt,
    Value<DateTime>? generatedAt,
    Value<String>? payloadJson,
    Value<int>? rowid,
  }) {
    return WildlifeMapLayerCachesCompanion(
      id: id ?? this.id,
      centerLatitude: centerLatitude ?? this.centerLatitude,
      centerLongitude: centerLongitude ?? this.centerLongitude,
      radiusKilometers: radiusKilometers ?? this.radiusKilometers,
      savedAt: savedAt ?? this.savedAt,
      generatedAt: generatedAt ?? this.generatedAt,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (centerLatitude.present) {
      map['center_latitude'] = Variable<double>(centerLatitude.value);
    }
    if (centerLongitude.present) {
      map['center_longitude'] = Variable<double>(centerLongitude.value);
    }
    if (radiusKilometers.present) {
      map['radius_kilometers'] = Variable<int>(radiusKilometers.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (generatedAt.present) {
      map['generated_at'] = Variable<DateTime>(generatedAt.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WildlifeMapLayerCachesCompanion(')
          ..write('id: $id, ')
          ..write('centerLatitude: $centerLatitude, ')
          ..write('centerLongitude: $centerLongitude, ')
          ..write('radiusKilometers: $radiusKilometers, ')
          ..write('savedAt: $savedAt, ')
          ..write('generatedAt: $generatedAt, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchedPhotographyOpportunitiesTable
    extends WatchedPhotographyOpportunities
    with
        TableInfo<
          $WatchedPhotographyOpportunitiesTable,
          WatchedPhotographyOpportunityRow
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchedPhotographyOpportunitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opportunityIdMeta = const VerificationMeta(
    'opportunityId',
  );
  @override
  late final GeneratedColumn<String> opportunityId = GeneratedColumn<String>(
    'opportunity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  @override
  late final GeneratedColumn<String> snapshotId = GeneratedColumn<String>(
    'snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _watchedAtMeta = const VerificationMeta(
    'watchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> watchedAt = GeneratedColumn<DateTime>(
    'watched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    opportunityId,
    snapshotId,
    title,
    targetId,
    watchedAt,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watched_photography_opportunities';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchedPhotographyOpportunityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('opportunity_id')) {
      context.handle(
        _opportunityIdMeta,
        opportunityId.isAcceptableOrUnknown(
          data['opportunity_id']!,
          _opportunityIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_opportunityIdMeta);
    }
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    }
    if (data.containsKey('watched_at')) {
      context.handle(
        _watchedAtMeta,
        watchedAt.isAcceptableOrUnknown(data['watched_at']!, _watchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_watchedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WatchedPhotographyOpportunityRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchedPhotographyOpportunityRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      opportunityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opportunity_id'],
      )!,
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      ),
      watchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}watched_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
    );
  }

  @override
  $WatchedPhotographyOpportunitiesTable createAlias(String alias) {
    return $WatchedPhotographyOpportunitiesTable(attachedDatabase, alias);
  }
}

class WatchedPhotographyOpportunityRow extends DataClass
    implements Insertable<WatchedPhotographyOpportunityRow> {
  final String id;
  final String opportunityId;
  final String snapshotId;
  final String title;
  final String? targetId;
  final DateTime watchedAt;
  final DateTime expiresAt;
  const WatchedPhotographyOpportunityRow({
    required this.id,
    required this.opportunityId,
    required this.snapshotId,
    required this.title,
    this.targetId,
    required this.watchedAt,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['opportunity_id'] = Variable<String>(opportunityId);
    map['snapshot_id'] = Variable<String>(snapshotId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || targetId != null) {
      map['target_id'] = Variable<String>(targetId);
    }
    map['watched_at'] = Variable<DateTime>(watchedAt);
    map['expires_at'] = Variable<DateTime>(expiresAt);
    return map;
  }

  WatchedPhotographyOpportunitiesCompanion toCompanion(bool nullToAbsent) {
    return WatchedPhotographyOpportunitiesCompanion(
      id: Value(id),
      opportunityId: Value(opportunityId),
      snapshotId: Value(snapshotId),
      title: Value(title),
      targetId: targetId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetId),
      watchedAt: Value(watchedAt),
      expiresAt: Value(expiresAt),
    );
  }

  factory WatchedPhotographyOpportunityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchedPhotographyOpportunityRow(
      id: serializer.fromJson<String>(json['id']),
      opportunityId: serializer.fromJson<String>(json['opportunityId']),
      snapshotId: serializer.fromJson<String>(json['snapshotId']),
      title: serializer.fromJson<String>(json['title']),
      targetId: serializer.fromJson<String?>(json['targetId']),
      watchedAt: serializer.fromJson<DateTime>(json['watchedAt']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'opportunityId': serializer.toJson<String>(opportunityId),
      'snapshotId': serializer.toJson<String>(snapshotId),
      'title': serializer.toJson<String>(title),
      'targetId': serializer.toJson<String?>(targetId),
      'watchedAt': serializer.toJson<DateTime>(watchedAt),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
    };
  }

  WatchedPhotographyOpportunityRow copyWith({
    String? id,
    String? opportunityId,
    String? snapshotId,
    String? title,
    Value<String?> targetId = const Value.absent(),
    DateTime? watchedAt,
    DateTime? expiresAt,
  }) => WatchedPhotographyOpportunityRow(
    id: id ?? this.id,
    opportunityId: opportunityId ?? this.opportunityId,
    snapshotId: snapshotId ?? this.snapshotId,
    title: title ?? this.title,
    targetId: targetId.present ? targetId.value : this.targetId,
    watchedAt: watchedAt ?? this.watchedAt,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  WatchedPhotographyOpportunityRow copyWithCompanion(
    WatchedPhotographyOpportunitiesCompanion data,
  ) {
    return WatchedPhotographyOpportunityRow(
      id: data.id.present ? data.id.value : this.id,
      opportunityId: data.opportunityId.present
          ? data.opportunityId.value
          : this.opportunityId,
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
      title: data.title.present ? data.title.value : this.title,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      watchedAt: data.watchedAt.present ? data.watchedAt.value : this.watchedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchedPhotographyOpportunityRow(')
          ..write('id: $id, ')
          ..write('opportunityId: $opportunityId, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('title: $title, ')
          ..write('targetId: $targetId, ')
          ..write('watchedAt: $watchedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    opportunityId,
    snapshotId,
    title,
    targetId,
    watchedAt,
    expiresAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchedPhotographyOpportunityRow &&
          other.id == this.id &&
          other.opportunityId == this.opportunityId &&
          other.snapshotId == this.snapshotId &&
          other.title == this.title &&
          other.targetId == this.targetId &&
          other.watchedAt == this.watchedAt &&
          other.expiresAt == this.expiresAt);
}

class WatchedPhotographyOpportunitiesCompanion
    extends UpdateCompanion<WatchedPhotographyOpportunityRow> {
  final Value<String> id;
  final Value<String> opportunityId;
  final Value<String> snapshotId;
  final Value<String> title;
  final Value<String?> targetId;
  final Value<DateTime> watchedAt;
  final Value<DateTime> expiresAt;
  final Value<int> rowid;
  const WatchedPhotographyOpportunitiesCompanion({
    this.id = const Value.absent(),
    this.opportunityId = const Value.absent(),
    this.snapshotId = const Value.absent(),
    this.title = const Value.absent(),
    this.targetId = const Value.absent(),
    this.watchedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchedPhotographyOpportunitiesCompanion.insert({
    required String id,
    required String opportunityId,
    required String snapshotId,
    required String title,
    this.targetId = const Value.absent(),
    required DateTime watchedAt,
    required DateTime expiresAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       opportunityId = Value(opportunityId),
       snapshotId = Value(snapshotId),
       title = Value(title),
       watchedAt = Value(watchedAt),
       expiresAt = Value(expiresAt);
  static Insertable<WatchedPhotographyOpportunityRow> custom({
    Expression<String>? id,
    Expression<String>? opportunityId,
    Expression<String>? snapshotId,
    Expression<String>? title,
    Expression<String>? targetId,
    Expression<DateTime>? watchedAt,
    Expression<DateTime>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (opportunityId != null) 'opportunity_id': opportunityId,
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (title != null) 'title': title,
      if (targetId != null) 'target_id': targetId,
      if (watchedAt != null) 'watched_at': watchedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchedPhotographyOpportunitiesCompanion copyWith({
    Value<String>? id,
    Value<String>? opportunityId,
    Value<String>? snapshotId,
    Value<String>? title,
    Value<String?>? targetId,
    Value<DateTime>? watchedAt,
    Value<DateTime>? expiresAt,
    Value<int>? rowid,
  }) {
    return WatchedPhotographyOpportunitiesCompanion(
      id: id ?? this.id,
      opportunityId: opportunityId ?? this.opportunityId,
      snapshotId: snapshotId ?? this.snapshotId,
      title: title ?? this.title,
      targetId: targetId ?? this.targetId,
      watchedAt: watchedAt ?? this.watchedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (opportunityId.present) {
      map['opportunity_id'] = Variable<String>(opportunityId.value);
    }
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<String>(snapshotId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (watchedAt.present) {
      map['watched_at'] = Variable<DateTime>(watchedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchedPhotographyOpportunitiesCompanion(')
          ..write('id: $id, ')
          ..write('opportunityId: $opportunityId, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('title: $title, ')
          ..write('targetId: $targetId, ')
          ..write('watchedAt: $watchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhotographyOpportunityResultsTable extends PhotographyOpportunityResults
    with
        TableInfo<
          $PhotographyOpportunityResultsTable,
          PhotographyOpportunityResultRow
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhotographyOpportunityResultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opportunityIdMeta = const VerificationMeta(
    'opportunityId',
  );
  @override
  late final GeneratedColumn<String> opportunityId = GeneratedColumn<String>(
    'opportunity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  @override
  late final GeneratedColumn<String> snapshotId = GeneratedColumn<String>(
    'snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    opportunityId,
    snapshotId,
    targetId,
    outcome,
    reason,
    recordedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'photography_opportunity_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<PhotographyOpportunityResultRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('opportunity_id')) {
      context.handle(
        _opportunityIdMeta,
        opportunityId.isAcceptableOrUnknown(
          data['opportunity_id']!,
          _opportunityIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_opportunityIdMeta);
    }
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PhotographyOpportunityResultRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PhotographyOpportunityResultRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      opportunityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opportunity_id'],
      )!,
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_id'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      ),
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $PhotographyOpportunityResultsTable createAlias(String alias) {
    return $PhotographyOpportunityResultsTable(attachedDatabase, alias);
  }
}

class PhotographyOpportunityResultRow extends DataClass
    implements Insertable<PhotographyOpportunityResultRow> {
  final String id;
  final String opportunityId;
  final String snapshotId;
  final String? targetId;
  final String outcome;
  final String? reason;
  final DateTime recordedAt;
  const PhotographyOpportunityResultRow({
    required this.id,
    required this.opportunityId,
    required this.snapshotId,
    this.targetId,
    required this.outcome,
    this.reason,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['opportunity_id'] = Variable<String>(opportunityId);
    map['snapshot_id'] = Variable<String>(snapshotId);
    if (!nullToAbsent || targetId != null) {
      map['target_id'] = Variable<String>(targetId);
    }
    map['outcome'] = Variable<String>(outcome);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    return map;
  }

  PhotographyOpportunityResultsCompanion toCompanion(bool nullToAbsent) {
    return PhotographyOpportunityResultsCompanion(
      id: Value(id),
      opportunityId: Value(opportunityId),
      snapshotId: Value(snapshotId),
      targetId: targetId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetId),
      outcome: Value(outcome),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      recordedAt: Value(recordedAt),
    );
  }

  factory PhotographyOpportunityResultRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PhotographyOpportunityResultRow(
      id: serializer.fromJson<String>(json['id']),
      opportunityId: serializer.fromJson<String>(json['opportunityId']),
      snapshotId: serializer.fromJson<String>(json['snapshotId']),
      targetId: serializer.fromJson<String?>(json['targetId']),
      outcome: serializer.fromJson<String>(json['outcome']),
      reason: serializer.fromJson<String?>(json['reason']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'opportunityId': serializer.toJson<String>(opportunityId),
      'snapshotId': serializer.toJson<String>(snapshotId),
      'targetId': serializer.toJson<String?>(targetId),
      'outcome': serializer.toJson<String>(outcome),
      'reason': serializer.toJson<String?>(reason),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
    };
  }

  PhotographyOpportunityResultRow copyWith({
    String? id,
    String? opportunityId,
    String? snapshotId,
    Value<String?> targetId = const Value.absent(),
    String? outcome,
    Value<String?> reason = const Value.absent(),
    DateTime? recordedAt,
  }) => PhotographyOpportunityResultRow(
    id: id ?? this.id,
    opportunityId: opportunityId ?? this.opportunityId,
    snapshotId: snapshotId ?? this.snapshotId,
    targetId: targetId.present ? targetId.value : this.targetId,
    outcome: outcome ?? this.outcome,
    reason: reason.present ? reason.value : this.reason,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  PhotographyOpportunityResultRow copyWithCompanion(
    PhotographyOpportunityResultsCompanion data,
  ) {
    return PhotographyOpportunityResultRow(
      id: data.id.present ? data.id.value : this.id,
      opportunityId: data.opportunityId.present
          ? data.opportunityId.value
          : this.opportunityId,
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      reason: data.reason.present ? data.reason.value : this.reason,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PhotographyOpportunityResultRow(')
          ..write('id: $id, ')
          ..write('opportunityId: $opportunityId, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('targetId: $targetId, ')
          ..write('outcome: $outcome, ')
          ..write('reason: $reason, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    opportunityId,
    snapshotId,
    targetId,
    outcome,
    reason,
    recordedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhotographyOpportunityResultRow &&
          other.id == this.id &&
          other.opportunityId == this.opportunityId &&
          other.snapshotId == this.snapshotId &&
          other.targetId == this.targetId &&
          other.outcome == this.outcome &&
          other.reason == this.reason &&
          other.recordedAt == this.recordedAt);
}

class PhotographyOpportunityResultsCompanion
    extends UpdateCompanion<PhotographyOpportunityResultRow> {
  final Value<String> id;
  final Value<String> opportunityId;
  final Value<String> snapshotId;
  final Value<String?> targetId;
  final Value<String> outcome;
  final Value<String?> reason;
  final Value<DateTime> recordedAt;
  final Value<int> rowid;
  const PhotographyOpportunityResultsCompanion({
    this.id = const Value.absent(),
    this.opportunityId = const Value.absent(),
    this.snapshotId = const Value.absent(),
    this.targetId = const Value.absent(),
    this.outcome = const Value.absent(),
    this.reason = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhotographyOpportunityResultsCompanion.insert({
    required String id,
    required String opportunityId,
    required String snapshotId,
    this.targetId = const Value.absent(),
    required String outcome,
    this.reason = const Value.absent(),
    required DateTime recordedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       opportunityId = Value(opportunityId),
       snapshotId = Value(snapshotId),
       outcome = Value(outcome),
       recordedAt = Value(recordedAt);
  static Insertable<PhotographyOpportunityResultRow> custom({
    Expression<String>? id,
    Expression<String>? opportunityId,
    Expression<String>? snapshotId,
    Expression<String>? targetId,
    Expression<String>? outcome,
    Expression<String>? reason,
    Expression<DateTime>? recordedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (opportunityId != null) 'opportunity_id': opportunityId,
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (targetId != null) 'target_id': targetId,
      if (outcome != null) 'outcome': outcome,
      if (reason != null) 'reason': reason,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhotographyOpportunityResultsCompanion copyWith({
    Value<String>? id,
    Value<String>? opportunityId,
    Value<String>? snapshotId,
    Value<String?>? targetId,
    Value<String>? outcome,
    Value<String?>? reason,
    Value<DateTime>? recordedAt,
    Value<int>? rowid,
  }) {
    return PhotographyOpportunityResultsCompanion(
      id: id ?? this.id,
      opportunityId: opportunityId ?? this.opportunityId,
      snapshotId: snapshotId ?? this.snapshotId,
      targetId: targetId ?? this.targetId,
      outcome: outcome ?? this.outcome,
      reason: reason ?? this.reason,
      recordedAt: recordedAt ?? this.recordedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (opportunityId.present) {
      map['opportunity_id'] = Variable<String>(opportunityId.value);
    }
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<String>(snapshotId.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhotographyOpportunityResultsCompanion(')
          ..write('id: $id, ')
          ..write('opportunityId: $opportunityId, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('targetId: $targetId, ')
          ..write('outcome: $outcome, ')
          ..write('reason: $reason, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflinePhotographyPacksTable extends OfflinePhotographyPacks
    with TableInfo<$OfflinePhotographyPacksTable, OfflinePhotographyPackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflinePhotographyPacksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataTimestampMeta = const VerificationMeta(
    'dataTimestamp',
  );
  @override
  late final GeneratedColumn<DateTime> dataTimestamp =
      GeneratedColumn<DateTime>(
        'data_timestamp',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _routeJsonMeta = const VerificationMeta(
    'routeJson',
  );
  @override
  late final GeneratedColumn<String> routeJson = GeneratedColumn<String>(
    'route_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _placesJsonMeta = const VerificationMeta(
    'placesJson',
  );
  @override
  late final GeneratedColumn<String> placesJson = GeneratedColumn<String>(
    'places_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _windowsJsonMeta = const VerificationMeta(
    'windowsJson',
  );
  @override
  late final GeneratedColumn<String> windowsJson = GeneratedColumn<String>(
    'windows_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opportunityJsonMeta = const VerificationMeta(
    'opportunityJson',
  );
  @override
  late final GeneratedColumn<String> opportunityJson = GeneratedColumn<String>(
    'opportunity_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    createdAt,
    dataTimestamp,
    routeJson,
    placesJson,
    windowsJson,
    opportunityJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_photography_packs';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflinePhotographyPackRow> instance, {
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
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('data_timestamp')) {
      context.handle(
        _dataTimestampMeta,
        dataTimestamp.isAcceptableOrUnknown(
          data['data_timestamp']!,
          _dataTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dataTimestampMeta);
    }
    if (data.containsKey('route_json')) {
      context.handle(
        _routeJsonMeta,
        routeJson.isAcceptableOrUnknown(data['route_json']!, _routeJsonMeta),
      );
    }
    if (data.containsKey('places_json')) {
      context.handle(
        _placesJsonMeta,
        placesJson.isAcceptableOrUnknown(data['places_json']!, _placesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_placesJsonMeta);
    }
    if (data.containsKey('windows_json')) {
      context.handle(
        _windowsJsonMeta,
        windowsJson.isAcceptableOrUnknown(
          data['windows_json']!,
          _windowsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_windowsJsonMeta);
    }
    if (data.containsKey('opportunity_json')) {
      context.handle(
        _opportunityJsonMeta,
        opportunityJson.isAcceptableOrUnknown(
          data['opportunity_json']!,
          _opportunityJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_opportunityJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflinePhotographyPackRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflinePhotographyPackRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      dataTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}data_timestamp'],
      )!,
      routeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_json'],
      ),
      placesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}places_json'],
      )!,
      windowsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}windows_json'],
      )!,
      opportunityJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opportunity_json'],
      )!,
    );
  }

  @override
  $OfflinePhotographyPacksTable createAlias(String alias) {
    return $OfflinePhotographyPacksTable(attachedDatabase, alias);
  }
}

class OfflinePhotographyPackRow extends DataClass
    implements Insertable<OfflinePhotographyPackRow> {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime dataTimestamp;
  final String? routeJson;
  final String placesJson;
  final String windowsJson;
  final String opportunityJson;
  const OfflinePhotographyPackRow({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.dataTimestamp,
    this.routeJson,
    required this.placesJson,
    required this.windowsJson,
    required this.opportunityJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['data_timestamp'] = Variable<DateTime>(dataTimestamp);
    if (!nullToAbsent || routeJson != null) {
      map['route_json'] = Variable<String>(routeJson);
    }
    map['places_json'] = Variable<String>(placesJson);
    map['windows_json'] = Variable<String>(windowsJson);
    map['opportunity_json'] = Variable<String>(opportunityJson);
    return map;
  }

  OfflinePhotographyPacksCompanion toCompanion(bool nullToAbsent) {
    return OfflinePhotographyPacksCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      dataTimestamp: Value(dataTimestamp),
      routeJson: routeJson == null && nullToAbsent
          ? const Value.absent()
          : Value(routeJson),
      placesJson: Value(placesJson),
      windowsJson: Value(windowsJson),
      opportunityJson: Value(opportunityJson),
    );
  }

  factory OfflinePhotographyPackRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflinePhotographyPackRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      dataTimestamp: serializer.fromJson<DateTime>(json['dataTimestamp']),
      routeJson: serializer.fromJson<String?>(json['routeJson']),
      placesJson: serializer.fromJson<String>(json['placesJson']),
      windowsJson: serializer.fromJson<String>(json['windowsJson']),
      opportunityJson: serializer.fromJson<String>(json['opportunityJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'dataTimestamp': serializer.toJson<DateTime>(dataTimestamp),
      'routeJson': serializer.toJson<String?>(routeJson),
      'placesJson': serializer.toJson<String>(placesJson),
      'windowsJson': serializer.toJson<String>(windowsJson),
      'opportunityJson': serializer.toJson<String>(opportunityJson),
    };
  }

  OfflinePhotographyPackRow copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? dataTimestamp,
    Value<String?> routeJson = const Value.absent(),
    String? placesJson,
    String? windowsJson,
    String? opportunityJson,
  }) => OfflinePhotographyPackRow(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    dataTimestamp: dataTimestamp ?? this.dataTimestamp,
    routeJson: routeJson.present ? routeJson.value : this.routeJson,
    placesJson: placesJson ?? this.placesJson,
    windowsJson: windowsJson ?? this.windowsJson,
    opportunityJson: opportunityJson ?? this.opportunityJson,
  );
  OfflinePhotographyPackRow copyWithCompanion(
    OfflinePhotographyPacksCompanion data,
  ) {
    return OfflinePhotographyPackRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      dataTimestamp: data.dataTimestamp.present
          ? data.dataTimestamp.value
          : this.dataTimestamp,
      routeJson: data.routeJson.present ? data.routeJson.value : this.routeJson,
      placesJson: data.placesJson.present
          ? data.placesJson.value
          : this.placesJson,
      windowsJson: data.windowsJson.present
          ? data.windowsJson.value
          : this.windowsJson,
      opportunityJson: data.opportunityJson.present
          ? data.opportunityJson.value
          : this.opportunityJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflinePhotographyPackRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('dataTimestamp: $dataTimestamp, ')
          ..write('routeJson: $routeJson, ')
          ..write('placesJson: $placesJson, ')
          ..write('windowsJson: $windowsJson, ')
          ..write('opportunityJson: $opportunityJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    createdAt,
    dataTimestamp,
    routeJson,
    placesJson,
    windowsJson,
    opportunityJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflinePhotographyPackRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.dataTimestamp == this.dataTimestamp &&
          other.routeJson == this.routeJson &&
          other.placesJson == this.placesJson &&
          other.windowsJson == this.windowsJson &&
          other.opportunityJson == this.opportunityJson);
}

class OfflinePhotographyPacksCompanion
    extends UpdateCompanion<OfflinePhotographyPackRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<DateTime> dataTimestamp;
  final Value<String?> routeJson;
  final Value<String> placesJson;
  final Value<String> windowsJson;
  final Value<String> opportunityJson;
  final Value<int> rowid;
  const OfflinePhotographyPacksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.dataTimestamp = const Value.absent(),
    this.routeJson = const Value.absent(),
    this.placesJson = const Value.absent(),
    this.windowsJson = const Value.absent(),
    this.opportunityJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflinePhotographyPacksCompanion.insert({
    required String id,
    required String name,
    required DateTime createdAt,
    required DateTime dataTimestamp,
    this.routeJson = const Value.absent(),
    required String placesJson,
    required String windowsJson,
    required String opportunityJson,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       dataTimestamp = Value(dataTimestamp),
       placesJson = Value(placesJson),
       windowsJson = Value(windowsJson),
       opportunityJson = Value(opportunityJson);
  static Insertable<OfflinePhotographyPackRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? dataTimestamp,
    Expression<String>? routeJson,
    Expression<String>? placesJson,
    Expression<String>? windowsJson,
    Expression<String>? opportunityJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (dataTimestamp != null) 'data_timestamp': dataTimestamp,
      if (routeJson != null) 'route_json': routeJson,
      if (placesJson != null) 'places_json': placesJson,
      if (windowsJson != null) 'windows_json': windowsJson,
      if (opportunityJson != null) 'opportunity_json': opportunityJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflinePhotographyPacksCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<DateTime>? dataTimestamp,
    Value<String?>? routeJson,
    Value<String>? placesJson,
    Value<String>? windowsJson,
    Value<String>? opportunityJson,
    Value<int>? rowid,
  }) {
    return OfflinePhotographyPacksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      dataTimestamp: dataTimestamp ?? this.dataTimestamp,
      routeJson: routeJson ?? this.routeJson,
      placesJson: placesJson ?? this.placesJson,
      windowsJson: windowsJson ?? this.windowsJson,
      opportunityJson: opportunityJson ?? this.opportunityJson,
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
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (dataTimestamp.present) {
      map['data_timestamp'] = Variable<DateTime>(dataTimestamp.value);
    }
    if (routeJson.present) {
      map['route_json'] = Variable<String>(routeJson.value);
    }
    if (placesJson.present) {
      map['places_json'] = Variable<String>(placesJson.value);
    }
    if (windowsJson.present) {
      map['windows_json'] = Variable<String>(windowsJson.value);
    }
    if (opportunityJson.present) {
      map['opportunity_json'] = Variable<String>(opportunityJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflinePhotographyPacksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('dataTimestamp: $dataTimestamp, ')
          ..write('routeJson: $routeJson, ')
          ..write('placesJson: $placesJson, ')
          ..write('windowsJson: $windowsJson, ')
          ..write('opportunityJson: $opportunityJson, ')
          ..write('rowid: $rowid')
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
  late final $SavedRoutesTable savedRoutes = $SavedRoutesTable(this);
  late final $SavedJourneysTable savedJourneys = $SavedJourneysTable(this);
  late final $ImportedRouteTracksTable importedRouteTracks =
      $ImportedRouteTracksTable(this);
  late final $ProfilePreferenceRecordsTable profilePreferenceRecords =
      $ProfilePreferenceRecordsTable(this);
  late final $BaseRegionsTable baseRegions = $BaseRegionsTable(this);
  late final $SavedInspirationNotesTable savedInspirationNotes =
      $SavedInspirationNotesTable(this);
  late final $WildlifeMapLayerCachesTable wildlifeMapLayerCaches =
      $WildlifeMapLayerCachesTable(this);
  late final $WatchedPhotographyOpportunitiesTable
  watchedPhotographyOpportunities = $WatchedPhotographyOpportunitiesTable(this);
  late final $PhotographyOpportunityResultsTable photographyOpportunityResults =
      $PhotographyOpportunityResultsTable(this);
  late final $OfflinePhotographyPacksTable offlinePhotographyPacks =
      $OfflinePhotographyPacksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    savedPlaces,
    recentRouteDestinations,
    savedRoutes,
    savedJourneys,
    importedRouteTracks,
    profilePreferenceRecords,
    baseRegions,
    savedInspirationNotes,
    wildlifeMapLayerCaches,
    watchedPhotographyOpportunities,
    photographyOpportunityResults,
    offlinePhotographyPacks,
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
typedef $$SavedRoutesTableCreateCompanionBuilder =
    SavedRoutesCompanion Function({
      required String id,
      required String name,
      required double latitude,
      required double longitude,
      required String travelMode,
      required DateTime savedAt,
      Value<int> rowid,
    });
typedef $$SavedRoutesTableUpdateCompanionBuilder =
    SavedRoutesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<double> latitude,
      Value<double> longitude,
      Value<String> travelMode,
      Value<DateTime> savedAt,
      Value<int> rowid,
    });

class $$SavedRoutesTableFilterComposer
    extends Composer<_$AppDatabase, $SavedRoutesTable> {
  $$SavedRoutesTableFilterComposer({
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

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedRoutesTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedRoutesTable> {
  $$SavedRoutesTableOrderingComposer({
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

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedRoutesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedRoutesTable> {
  $$SavedRoutesTableAnnotationComposer({
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

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get travelMode => $composableBuilder(
    column: $table.travelMode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);
}

class $$SavedRoutesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedRoutesTable,
          SavedRouteRow,
          $$SavedRoutesTableFilterComposer,
          $$SavedRoutesTableOrderingComposer,
          $$SavedRoutesTableAnnotationComposer,
          $$SavedRoutesTableCreateCompanionBuilder,
          $$SavedRoutesTableUpdateCompanionBuilder,
          (
            SavedRouteRow,
            BaseReferences<_$AppDatabase, $SavedRoutesTable, SavedRouteRow>,
          ),
          SavedRouteRow,
          PrefetchHooks Function()
        > {
  $$SavedRoutesTableTableManager(_$AppDatabase db, $SavedRoutesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedRoutesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedRoutesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedRoutesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<String> travelMode = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedRoutesCompanion(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                travelMode: travelMode,
                savedAt: savedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required double latitude,
                required double longitude,
                required String travelMode,
                required DateTime savedAt,
                Value<int> rowid = const Value.absent(),
              }) => SavedRoutesCompanion.insert(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                travelMode: travelMode,
                savedAt: savedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedRoutesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedRoutesTable,
      SavedRouteRow,
      $$SavedRoutesTableFilterComposer,
      $$SavedRoutesTableOrderingComposer,
      $$SavedRoutesTableAnnotationComposer,
      $$SavedRoutesTableCreateCompanionBuilder,
      $$SavedRoutesTableUpdateCompanionBuilder,
      (
        SavedRouteRow,
        BaseReferences<_$AppDatabase, $SavedRoutesTable, SavedRouteRow>,
      ),
      SavedRouteRow,
      PrefetchHooks Function()
    >;
typedef $$SavedJourneysTableCreateCompanionBuilder =
    SavedJourneysCompanion Function({
      required String id,
      required String name,
      required double latitude,
      required double longitude,
      required String travelMode,
      Value<String?> routeKey,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      Value<int> rowid,
    });
typedef $$SavedJourneysTableUpdateCompanionBuilder =
    SavedJourneysCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<double> latitude,
      Value<double> longitude,
      Value<String> travelMode,
      Value<String?> routeKey,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<int> rowid,
    });

class $$SavedJourneysTableFilterComposer
    extends Composer<_$AppDatabase, $SavedJourneysTable> {
  $$SavedJourneysTableFilterComposer({
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

  ColumnFilters<String> get routeKey => $composableBuilder(
    column: $table.routeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedJourneysTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedJourneysTable> {
  $$SavedJourneysTableOrderingComposer({
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

  ColumnOrderings<String> get routeKey => $composableBuilder(
    column: $table.routeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedJourneysTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedJourneysTable> {
  $$SavedJourneysTableAnnotationComposer({
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

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get travelMode => $composableBuilder(
    column: $table.travelMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get routeKey =>
      $composableBuilder(column: $table.routeKey, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);
}

class $$SavedJourneysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedJourneysTable,
          SavedJourneyRow,
          $$SavedJourneysTableFilterComposer,
          $$SavedJourneysTableOrderingComposer,
          $$SavedJourneysTableAnnotationComposer,
          $$SavedJourneysTableCreateCompanionBuilder,
          $$SavedJourneysTableUpdateCompanionBuilder,
          (
            SavedJourneyRow,
            BaseReferences<_$AppDatabase, $SavedJourneysTable, SavedJourneyRow>,
          ),
          SavedJourneyRow,
          PrefetchHooks Function()
        > {
  $$SavedJourneysTableTableManager(_$AppDatabase db, $SavedJourneysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedJourneysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedJourneysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedJourneysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<String> travelMode = const Value.absent(),
                Value<String?> routeKey = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedJourneysCompanion(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                travelMode: travelMode,
                routeKey: routeKey,
                startedAt: startedAt,
                endedAt: endedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required double latitude,
                required double longitude,
                required String travelMode,
                Value<String?> routeKey = const Value.absent(),
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedJourneysCompanion.insert(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                travelMode: travelMode,
                routeKey: routeKey,
                startedAt: startedAt,
                endedAt: endedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedJourneysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedJourneysTable,
      SavedJourneyRow,
      $$SavedJourneysTableFilterComposer,
      $$SavedJourneysTableOrderingComposer,
      $$SavedJourneysTableAnnotationComposer,
      $$SavedJourneysTableCreateCompanionBuilder,
      $$SavedJourneysTableUpdateCompanionBuilder,
      (
        SavedJourneyRow,
        BaseReferences<_$AppDatabase, $SavedJourneysTable, SavedJourneyRow>,
      ),
      SavedJourneyRow,
      PrefetchHooks Function()
    >;
typedef $$ImportedRouteTracksTableCreateCompanionBuilder =
    ImportedRouteTracksCompanion Function({
      required String id,
      required String name,
      required DateTime importedAt,
      required String pointsJson,
      required int distanceMeters,
      required int durationSeconds,
      required bool durationEstimated,
      Value<int?> ascentMeters,
      Value<int?> descentMeters,
      Value<int> rowid,
    });
typedef $$ImportedRouteTracksTableUpdateCompanionBuilder =
    ImportedRouteTracksCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> importedAt,
      Value<String> pointsJson,
      Value<int> distanceMeters,
      Value<int> durationSeconds,
      Value<bool> durationEstimated,
      Value<int?> ascentMeters,
      Value<int?> descentMeters,
      Value<int> rowid,
    });

class $$ImportedRouteTracksTableFilterComposer
    extends Composer<_$AppDatabase, $ImportedRouteTracksTable> {
  $$ImportedRouteTracksTableFilterComposer({
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

  ColumnFilters<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pointsJson => $composableBuilder(
    column: $table.pointsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get durationEstimated => $composableBuilder(
    column: $table.durationEstimated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ascentMeters => $composableBuilder(
    column: $table.ascentMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get descentMeters => $composableBuilder(
    column: $table.descentMeters,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImportedRouteTracksTableOrderingComposer
    extends Composer<_$AppDatabase, $ImportedRouteTracksTable> {
  $$ImportedRouteTracksTableOrderingComposer({
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

  ColumnOrderings<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pointsJson => $composableBuilder(
    column: $table.pointsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get durationEstimated => $composableBuilder(
    column: $table.durationEstimated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ascentMeters => $composableBuilder(
    column: $table.ascentMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get descentMeters => $composableBuilder(
    column: $table.descentMeters,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportedRouteTracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImportedRouteTracksTable> {
  $$ImportedRouteTracksTableAnnotationComposer({
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

  GeneratedColumn<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pointsJson => $composableBuilder(
    column: $table.pointsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get durationEstimated => $composableBuilder(
    column: $table.durationEstimated,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ascentMeters => $composableBuilder(
    column: $table.ascentMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get descentMeters => $composableBuilder(
    column: $table.descentMeters,
    builder: (column) => column,
  );
}

class $$ImportedRouteTracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImportedRouteTracksTable,
          ImportedRouteTrackRow,
          $$ImportedRouteTracksTableFilterComposer,
          $$ImportedRouteTracksTableOrderingComposer,
          $$ImportedRouteTracksTableAnnotationComposer,
          $$ImportedRouteTracksTableCreateCompanionBuilder,
          $$ImportedRouteTracksTableUpdateCompanionBuilder,
          (
            ImportedRouteTrackRow,
            BaseReferences<
              _$AppDatabase,
              $ImportedRouteTracksTable,
              ImportedRouteTrackRow
            >,
          ),
          ImportedRouteTrackRow,
          PrefetchHooks Function()
        > {
  $$ImportedRouteTracksTableTableManager(
    _$AppDatabase db,
    $ImportedRouteTracksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportedRouteTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportedRouteTracksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ImportedRouteTracksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> importedAt = const Value.absent(),
                Value<String> pointsJson = const Value.absent(),
                Value<int> distanceMeters = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<bool> durationEstimated = const Value.absent(),
                Value<int?> ascentMeters = const Value.absent(),
                Value<int?> descentMeters = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportedRouteTracksCompanion(
                id: id,
                name: name,
                importedAt: importedAt,
                pointsJson: pointsJson,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                durationEstimated: durationEstimated,
                ascentMeters: ascentMeters,
                descentMeters: descentMeters,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime importedAt,
                required String pointsJson,
                required int distanceMeters,
                required int durationSeconds,
                required bool durationEstimated,
                Value<int?> ascentMeters = const Value.absent(),
                Value<int?> descentMeters = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportedRouteTracksCompanion.insert(
                id: id,
                name: name,
                importedAt: importedAt,
                pointsJson: pointsJson,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                durationEstimated: durationEstimated,
                ascentMeters: ascentMeters,
                descentMeters: descentMeters,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImportedRouteTracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImportedRouteTracksTable,
      ImportedRouteTrackRow,
      $$ImportedRouteTracksTableFilterComposer,
      $$ImportedRouteTracksTableOrderingComposer,
      $$ImportedRouteTracksTableAnnotationComposer,
      $$ImportedRouteTracksTableCreateCompanionBuilder,
      $$ImportedRouteTracksTableUpdateCompanionBuilder,
      (
        ImportedRouteTrackRow,
        BaseReferences<
          _$AppDatabase,
          $ImportedRouteTracksTable,
          ImportedRouteTrackRow
        >,
      ),
      ImportedRouteTrackRow,
      PrefetchHooks Function()
    >;
typedef $$ProfilePreferenceRecordsTableCreateCompanionBuilder =
    ProfilePreferenceRecordsCompanion Function({
      Value<int> id,
      required bool ambientBackgroundEnabled,
      required bool reduceMotion,
      required bool reduceFlashing,
      required bool highContrast,
      required String ambientMotionMode,
      required String photographyPreferencesJson,
      required String activityPreferencesJson,
      required String equipmentList,
      required String aiTone,
      required double recommendationIntensity,
    });
typedef $$ProfilePreferenceRecordsTableUpdateCompanionBuilder =
    ProfilePreferenceRecordsCompanion Function({
      Value<int> id,
      Value<bool> ambientBackgroundEnabled,
      Value<bool> reduceMotion,
      Value<bool> reduceFlashing,
      Value<bool> highContrast,
      Value<String> ambientMotionMode,
      Value<String> photographyPreferencesJson,
      Value<String> activityPreferencesJson,
      Value<String> equipmentList,
      Value<String> aiTone,
      Value<double> recommendationIntensity,
    });

class $$ProfilePreferenceRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilePreferenceRecordsTable> {
  $$ProfilePreferenceRecordsTableFilterComposer({
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

  ColumnFilters<bool> get ambientBackgroundEnabled => $composableBuilder(
    column: $table.ambientBackgroundEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reduceMotion => $composableBuilder(
    column: $table.reduceMotion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reduceFlashing => $composableBuilder(
    column: $table.reduceFlashing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get highContrast => $composableBuilder(
    column: $table.highContrast,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ambientMotionMode => $composableBuilder(
    column: $table.ambientMotionMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photographyPreferencesJson => $composableBuilder(
    column: $table.photographyPreferencesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activityPreferencesJson => $composableBuilder(
    column: $table.activityPreferencesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get equipmentList => $composableBuilder(
    column: $table.equipmentList,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiTone => $composableBuilder(
    column: $table.aiTone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get recommendationIntensity => $composableBuilder(
    column: $table.recommendationIntensity,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfilePreferenceRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilePreferenceRecordsTable> {
  $$ProfilePreferenceRecordsTableOrderingComposer({
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

  ColumnOrderings<bool> get ambientBackgroundEnabled => $composableBuilder(
    column: $table.ambientBackgroundEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reduceMotion => $composableBuilder(
    column: $table.reduceMotion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reduceFlashing => $composableBuilder(
    column: $table.reduceFlashing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get highContrast => $composableBuilder(
    column: $table.highContrast,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ambientMotionMode => $composableBuilder(
    column: $table.ambientMotionMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photographyPreferencesJson => $composableBuilder(
    column: $table.photographyPreferencesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activityPreferencesJson => $composableBuilder(
    column: $table.activityPreferencesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get equipmentList => $composableBuilder(
    column: $table.equipmentList,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiTone => $composableBuilder(
    column: $table.aiTone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get recommendationIntensity => $composableBuilder(
    column: $table.recommendationIntensity,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilePreferenceRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilePreferenceRecordsTable> {
  $$ProfilePreferenceRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get ambientBackgroundEnabled => $composableBuilder(
    column: $table.ambientBackgroundEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reduceMotion => $composableBuilder(
    column: $table.reduceMotion,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reduceFlashing => $composableBuilder(
    column: $table.reduceFlashing,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get highContrast => $composableBuilder(
    column: $table.highContrast,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ambientMotionMode => $composableBuilder(
    column: $table.ambientMotionMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photographyPreferencesJson => $composableBuilder(
    column: $table.photographyPreferencesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activityPreferencesJson => $composableBuilder(
    column: $table.activityPreferencesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get equipmentList => $composableBuilder(
    column: $table.equipmentList,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiTone =>
      $composableBuilder(column: $table.aiTone, builder: (column) => column);

  GeneratedColumn<double> get recommendationIntensity => $composableBuilder(
    column: $table.recommendationIntensity,
    builder: (column) => column,
  );
}

class $$ProfilePreferenceRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfilePreferenceRecordsTable,
          ProfilePreferenceRow,
          $$ProfilePreferenceRecordsTableFilterComposer,
          $$ProfilePreferenceRecordsTableOrderingComposer,
          $$ProfilePreferenceRecordsTableAnnotationComposer,
          $$ProfilePreferenceRecordsTableCreateCompanionBuilder,
          $$ProfilePreferenceRecordsTableUpdateCompanionBuilder,
          (
            ProfilePreferenceRow,
            BaseReferences<
              _$AppDatabase,
              $ProfilePreferenceRecordsTable,
              ProfilePreferenceRow
            >,
          ),
          ProfilePreferenceRow,
          PrefetchHooks Function()
        > {
  $$ProfilePreferenceRecordsTableTableManager(
    _$AppDatabase db,
    $ProfilePreferenceRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilePreferenceRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ProfilePreferenceRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProfilePreferenceRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> ambientBackgroundEnabled = const Value.absent(),
                Value<bool> reduceMotion = const Value.absent(),
                Value<bool> reduceFlashing = const Value.absent(),
                Value<bool> highContrast = const Value.absent(),
                Value<String> ambientMotionMode = const Value.absent(),
                Value<String> photographyPreferencesJson = const Value.absent(),
                Value<String> activityPreferencesJson = const Value.absent(),
                Value<String> equipmentList = const Value.absent(),
                Value<String> aiTone = const Value.absent(),
                Value<double> recommendationIntensity = const Value.absent(),
              }) => ProfilePreferenceRecordsCompanion(
                id: id,
                ambientBackgroundEnabled: ambientBackgroundEnabled,
                reduceMotion: reduceMotion,
                reduceFlashing: reduceFlashing,
                highContrast: highContrast,
                ambientMotionMode: ambientMotionMode,
                photographyPreferencesJson: photographyPreferencesJson,
                activityPreferencesJson: activityPreferencesJson,
                equipmentList: equipmentList,
                aiTone: aiTone,
                recommendationIntensity: recommendationIntensity,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required bool ambientBackgroundEnabled,
                required bool reduceMotion,
                required bool reduceFlashing,
                required bool highContrast,
                required String ambientMotionMode,
                required String photographyPreferencesJson,
                required String activityPreferencesJson,
                required String equipmentList,
                required String aiTone,
                required double recommendationIntensity,
              }) => ProfilePreferenceRecordsCompanion.insert(
                id: id,
                ambientBackgroundEnabled: ambientBackgroundEnabled,
                reduceMotion: reduceMotion,
                reduceFlashing: reduceFlashing,
                highContrast: highContrast,
                ambientMotionMode: ambientMotionMode,
                photographyPreferencesJson: photographyPreferencesJson,
                activityPreferencesJson: activityPreferencesJson,
                equipmentList: equipmentList,
                aiTone: aiTone,
                recommendationIntensity: recommendationIntensity,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfilePreferenceRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfilePreferenceRecordsTable,
      ProfilePreferenceRow,
      $$ProfilePreferenceRecordsTableFilterComposer,
      $$ProfilePreferenceRecordsTableOrderingComposer,
      $$ProfilePreferenceRecordsTableAnnotationComposer,
      $$ProfilePreferenceRecordsTableCreateCompanionBuilder,
      $$ProfilePreferenceRecordsTableUpdateCompanionBuilder,
      (
        ProfilePreferenceRow,
        BaseReferences<
          _$AppDatabase,
          $ProfilePreferenceRecordsTable,
          ProfilePreferenceRow
        >,
      ),
      ProfilePreferenceRow,
      PrefetchHooks Function()
    >;
typedef $$BaseRegionsTableCreateCompanionBuilder =
    BaseRegionsCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> address,
      required double latitude,
      required double longitude,
      required DateTime selectedAt,
    });
typedef $$BaseRegionsTableUpdateCompanionBuilder =
    BaseRegionsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> address,
      Value<double> latitude,
      Value<double> longitude,
      Value<DateTime> selectedAt,
    });

class $$BaseRegionsTableFilterComposer
    extends Composer<_$AppDatabase, $BaseRegionsTable> {
  $$BaseRegionsTableFilterComposer({
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

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
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

  ColumnFilters<DateTime> get selectedAt => $composableBuilder(
    column: $table.selectedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BaseRegionsTableOrderingComposer
    extends Composer<_$AppDatabase, $BaseRegionsTable> {
  $$BaseRegionsTableOrderingComposer({
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

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
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

  ColumnOrderings<DateTime> get selectedAt => $composableBuilder(
    column: $table.selectedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BaseRegionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BaseRegionsTable> {
  $$BaseRegionsTableAnnotationComposer({
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

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<DateTime> get selectedAt => $composableBuilder(
    column: $table.selectedAt,
    builder: (column) => column,
  );
}

class $$BaseRegionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BaseRegionsTable,
          BaseRegionRow,
          $$BaseRegionsTableFilterComposer,
          $$BaseRegionsTableOrderingComposer,
          $$BaseRegionsTableAnnotationComposer,
          $$BaseRegionsTableCreateCompanionBuilder,
          $$BaseRegionsTableUpdateCompanionBuilder,
          (
            BaseRegionRow,
            BaseReferences<_$AppDatabase, $BaseRegionsTable, BaseRegionRow>,
          ),
          BaseRegionRow,
          PrefetchHooks Function()
        > {
  $$BaseRegionsTableTableManager(_$AppDatabase db, $BaseRegionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BaseRegionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BaseRegionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BaseRegionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<DateTime> selectedAt = const Value.absent(),
              }) => BaseRegionsCompanion(
                id: id,
                name: name,
                address: address,
                latitude: latitude,
                longitude: longitude,
                selectedAt: selectedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> address = const Value.absent(),
                required double latitude,
                required double longitude,
                required DateTime selectedAt,
              }) => BaseRegionsCompanion.insert(
                id: id,
                name: name,
                address: address,
                latitude: latitude,
                longitude: longitude,
                selectedAt: selectedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BaseRegionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BaseRegionsTable,
      BaseRegionRow,
      $$BaseRegionsTableFilterComposer,
      $$BaseRegionsTableOrderingComposer,
      $$BaseRegionsTableAnnotationComposer,
      $$BaseRegionsTableCreateCompanionBuilder,
      $$BaseRegionsTableUpdateCompanionBuilder,
      (
        BaseRegionRow,
        BaseReferences<_$AppDatabase, $BaseRegionsTable, BaseRegionRow>,
      ),
      BaseRegionRow,
      PrefetchHooks Function()
    >;
typedef $$SavedInspirationNotesTableCreateCompanionBuilder =
    SavedInspirationNotesCompanion Function({
      required String id,
      Value<String> sourceNoteId,
      required String label,
      required String emoji,
      required String category,
      required String actionName,
      required String detail,
      Value<String?> authorityUrl,
      required DateTime savedAt,
      Value<int> rowid,
    });
typedef $$SavedInspirationNotesTableUpdateCompanionBuilder =
    SavedInspirationNotesCompanion Function({
      Value<String> id,
      Value<String> sourceNoteId,
      Value<String> label,
      Value<String> emoji,
      Value<String> category,
      Value<String> actionName,
      Value<String> detail,
      Value<String?> authorityUrl,
      Value<DateTime> savedAt,
      Value<int> rowid,
    });

class $$SavedInspirationNotesTableFilterComposer
    extends Composer<_$AppDatabase, $SavedInspirationNotesTable> {
  $$SavedInspirationNotesTableFilterComposer({
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

  ColumnFilters<String> get sourceNoteId => $composableBuilder(
    column: $table.sourceNoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actionName => $composableBuilder(
    column: $table.actionName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorityUrl => $composableBuilder(
    column: $table.authorityUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedInspirationNotesTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedInspirationNotesTable> {
  $$SavedInspirationNotesTableOrderingComposer({
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

  ColumnOrderings<String> get sourceNoteId => $composableBuilder(
    column: $table.sourceNoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actionName => $composableBuilder(
    column: $table.actionName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorityUrl => $composableBuilder(
    column: $table.authorityUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedInspirationNotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedInspirationNotesTable> {
  $$SavedInspirationNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceNoteId => $composableBuilder(
    column: $table.sourceNoteId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get actionName => $composableBuilder(
    column: $table.actionName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<String> get authorityUrl => $composableBuilder(
    column: $table.authorityUrl,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);
}

class $$SavedInspirationNotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedInspirationNotesTable,
          SavedInspirationNoteRow,
          $$SavedInspirationNotesTableFilterComposer,
          $$SavedInspirationNotesTableOrderingComposer,
          $$SavedInspirationNotesTableAnnotationComposer,
          $$SavedInspirationNotesTableCreateCompanionBuilder,
          $$SavedInspirationNotesTableUpdateCompanionBuilder,
          (
            SavedInspirationNoteRow,
            BaseReferences<
              _$AppDatabase,
              $SavedInspirationNotesTable,
              SavedInspirationNoteRow
            >,
          ),
          SavedInspirationNoteRow,
          PrefetchHooks Function()
        > {
  $$SavedInspirationNotesTableTableManager(
    _$AppDatabase db,
    $SavedInspirationNotesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedInspirationNotesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SavedInspirationNotesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SavedInspirationNotesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceNoteId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> actionName = const Value.absent(),
                Value<String> detail = const Value.absent(),
                Value<String?> authorityUrl = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedInspirationNotesCompanion(
                id: id,
                sourceNoteId: sourceNoteId,
                label: label,
                emoji: emoji,
                category: category,
                actionName: actionName,
                detail: detail,
                authorityUrl: authorityUrl,
                savedAt: savedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> sourceNoteId = const Value.absent(),
                required String label,
                required String emoji,
                required String category,
                required String actionName,
                required String detail,
                Value<String?> authorityUrl = const Value.absent(),
                required DateTime savedAt,
                Value<int> rowid = const Value.absent(),
              }) => SavedInspirationNotesCompanion.insert(
                id: id,
                sourceNoteId: sourceNoteId,
                label: label,
                emoji: emoji,
                category: category,
                actionName: actionName,
                detail: detail,
                authorityUrl: authorityUrl,
                savedAt: savedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedInspirationNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedInspirationNotesTable,
      SavedInspirationNoteRow,
      $$SavedInspirationNotesTableFilterComposer,
      $$SavedInspirationNotesTableOrderingComposer,
      $$SavedInspirationNotesTableAnnotationComposer,
      $$SavedInspirationNotesTableCreateCompanionBuilder,
      $$SavedInspirationNotesTableUpdateCompanionBuilder,
      (
        SavedInspirationNoteRow,
        BaseReferences<
          _$AppDatabase,
          $SavedInspirationNotesTable,
          SavedInspirationNoteRow
        >,
      ),
      SavedInspirationNoteRow,
      PrefetchHooks Function()
    >;
typedef $$WildlifeMapLayerCachesTableCreateCompanionBuilder =
    WildlifeMapLayerCachesCompanion Function({
      required String id,
      required double centerLatitude,
      required double centerLongitude,
      required int radiusKilometers,
      required DateTime savedAt,
      required DateTime generatedAt,
      required String payloadJson,
      Value<int> rowid,
    });
typedef $$WildlifeMapLayerCachesTableUpdateCompanionBuilder =
    WildlifeMapLayerCachesCompanion Function({
      Value<String> id,
      Value<double> centerLatitude,
      Value<double> centerLongitude,
      Value<int> radiusKilometers,
      Value<DateTime> savedAt,
      Value<DateTime> generatedAt,
      Value<String> payloadJson,
      Value<int> rowid,
    });

class $$WildlifeMapLayerCachesTableFilterComposer
    extends Composer<_$AppDatabase, $WildlifeMapLayerCachesTable> {
  $$WildlifeMapLayerCachesTableFilterComposer({
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

  ColumnFilters<double> get centerLatitude => $composableBuilder(
    column: $table.centerLatitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get centerLongitude => $composableBuilder(
    column: $table.centerLongitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get radiusKilometers => $composableBuilder(
    column: $table.radiusKilometers,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WildlifeMapLayerCachesTableOrderingComposer
    extends Composer<_$AppDatabase, $WildlifeMapLayerCachesTable> {
  $$WildlifeMapLayerCachesTableOrderingComposer({
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

  ColumnOrderings<double> get centerLatitude => $composableBuilder(
    column: $table.centerLatitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get centerLongitude => $composableBuilder(
    column: $table.centerLongitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get radiusKilometers => $composableBuilder(
    column: $table.radiusKilometers,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WildlifeMapLayerCachesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WildlifeMapLayerCachesTable> {
  $$WildlifeMapLayerCachesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get centerLatitude => $composableBuilder(
    column: $table.centerLatitude,
    builder: (column) => column,
  );

  GeneratedColumn<double> get centerLongitude => $composableBuilder(
    column: $table.centerLongitude,
    builder: (column) => column,
  );

  GeneratedColumn<int> get radiusKilometers => $composableBuilder(
    column: $table.radiusKilometers,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$WildlifeMapLayerCachesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WildlifeMapLayerCachesTable,
          WildlifeMapLayerCacheRow,
          $$WildlifeMapLayerCachesTableFilterComposer,
          $$WildlifeMapLayerCachesTableOrderingComposer,
          $$WildlifeMapLayerCachesTableAnnotationComposer,
          $$WildlifeMapLayerCachesTableCreateCompanionBuilder,
          $$WildlifeMapLayerCachesTableUpdateCompanionBuilder,
          (
            WildlifeMapLayerCacheRow,
            BaseReferences<
              _$AppDatabase,
              $WildlifeMapLayerCachesTable,
              WildlifeMapLayerCacheRow
            >,
          ),
          WildlifeMapLayerCacheRow,
          PrefetchHooks Function()
        > {
  $$WildlifeMapLayerCachesTableTableManager(
    _$AppDatabase db,
    $WildlifeMapLayerCachesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WildlifeMapLayerCachesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$WildlifeMapLayerCachesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$WildlifeMapLayerCachesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<double> centerLatitude = const Value.absent(),
                Value<double> centerLongitude = const Value.absent(),
                Value<int> radiusKilometers = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
                Value<DateTime> generatedAt = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WildlifeMapLayerCachesCompanion(
                id: id,
                centerLatitude: centerLatitude,
                centerLongitude: centerLongitude,
                radiusKilometers: radiusKilometers,
                savedAt: savedAt,
                generatedAt: generatedAt,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required double centerLatitude,
                required double centerLongitude,
                required int radiusKilometers,
                required DateTime savedAt,
                required DateTime generatedAt,
                required String payloadJson,
                Value<int> rowid = const Value.absent(),
              }) => WildlifeMapLayerCachesCompanion.insert(
                id: id,
                centerLatitude: centerLatitude,
                centerLongitude: centerLongitude,
                radiusKilometers: radiusKilometers,
                savedAt: savedAt,
                generatedAt: generatedAt,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WildlifeMapLayerCachesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WildlifeMapLayerCachesTable,
      WildlifeMapLayerCacheRow,
      $$WildlifeMapLayerCachesTableFilterComposer,
      $$WildlifeMapLayerCachesTableOrderingComposer,
      $$WildlifeMapLayerCachesTableAnnotationComposer,
      $$WildlifeMapLayerCachesTableCreateCompanionBuilder,
      $$WildlifeMapLayerCachesTableUpdateCompanionBuilder,
      (
        WildlifeMapLayerCacheRow,
        BaseReferences<
          _$AppDatabase,
          $WildlifeMapLayerCachesTable,
          WildlifeMapLayerCacheRow
        >,
      ),
      WildlifeMapLayerCacheRow,
      PrefetchHooks Function()
    >;
typedef $$WatchedPhotographyOpportunitiesTableCreateCompanionBuilder =
    WatchedPhotographyOpportunitiesCompanion Function({
      required String id,
      required String opportunityId,
      required String snapshotId,
      required String title,
      Value<String?> targetId,
      required DateTime watchedAt,
      required DateTime expiresAt,
      Value<int> rowid,
    });
typedef $$WatchedPhotographyOpportunitiesTableUpdateCompanionBuilder =
    WatchedPhotographyOpportunitiesCompanion Function({
      Value<String> id,
      Value<String> opportunityId,
      Value<String> snapshotId,
      Value<String> title,
      Value<String?> targetId,
      Value<DateTime> watchedAt,
      Value<DateTime> expiresAt,
      Value<int> rowid,
    });

class $$WatchedPhotographyOpportunitiesTableFilterComposer
    extends Composer<_$AppDatabase, $WatchedPhotographyOpportunitiesTable> {
  $$WatchedPhotographyOpportunitiesTableFilterComposer({
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

  ColumnFilters<String> get opportunityId => $composableBuilder(
    column: $table.opportunityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get watchedAt => $composableBuilder(
    column: $table.watchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchedPhotographyOpportunitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchedPhotographyOpportunitiesTable> {
  $$WatchedPhotographyOpportunitiesTableOrderingComposer({
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

  ColumnOrderings<String> get opportunityId => $composableBuilder(
    column: $table.opportunityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get watchedAt => $composableBuilder(
    column: $table.watchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchedPhotographyOpportunitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchedPhotographyOpportunitiesTable> {
  $$WatchedPhotographyOpportunitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get opportunityId => $composableBuilder(
    column: $table.opportunityId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<DateTime> get watchedAt =>
      $composableBuilder(column: $table.watchedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$WatchedPhotographyOpportunitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchedPhotographyOpportunitiesTable,
          WatchedPhotographyOpportunityRow,
          $$WatchedPhotographyOpportunitiesTableFilterComposer,
          $$WatchedPhotographyOpportunitiesTableOrderingComposer,
          $$WatchedPhotographyOpportunitiesTableAnnotationComposer,
          $$WatchedPhotographyOpportunitiesTableCreateCompanionBuilder,
          $$WatchedPhotographyOpportunitiesTableUpdateCompanionBuilder,
          (
            WatchedPhotographyOpportunityRow,
            BaseReferences<
              _$AppDatabase,
              $WatchedPhotographyOpportunitiesTable,
              WatchedPhotographyOpportunityRow
            >,
          ),
          WatchedPhotographyOpportunityRow,
          PrefetchHooks Function()
        > {
  $$WatchedPhotographyOpportunitiesTableTableManager(
    _$AppDatabase db,
    $WatchedPhotographyOpportunitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchedPhotographyOpportunitiesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$WatchedPhotographyOpportunitiesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$WatchedPhotographyOpportunitiesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> opportunityId = const Value.absent(),
                Value<String> snapshotId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> targetId = const Value.absent(),
                Value<DateTime> watchedAt = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchedPhotographyOpportunitiesCompanion(
                id: id,
                opportunityId: opportunityId,
                snapshotId: snapshotId,
                title: title,
                targetId: targetId,
                watchedAt: watchedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String opportunityId,
                required String snapshotId,
                required String title,
                Value<String?> targetId = const Value.absent(),
                required DateTime watchedAt,
                required DateTime expiresAt,
                Value<int> rowid = const Value.absent(),
              }) => WatchedPhotographyOpportunitiesCompanion.insert(
                id: id,
                opportunityId: opportunityId,
                snapshotId: snapshotId,
                title: title,
                targetId: targetId,
                watchedAt: watchedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchedPhotographyOpportunitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchedPhotographyOpportunitiesTable,
      WatchedPhotographyOpportunityRow,
      $$WatchedPhotographyOpportunitiesTableFilterComposer,
      $$WatchedPhotographyOpportunitiesTableOrderingComposer,
      $$WatchedPhotographyOpportunitiesTableAnnotationComposer,
      $$WatchedPhotographyOpportunitiesTableCreateCompanionBuilder,
      $$WatchedPhotographyOpportunitiesTableUpdateCompanionBuilder,
      (
        WatchedPhotographyOpportunityRow,
        BaseReferences<
          _$AppDatabase,
          $WatchedPhotographyOpportunitiesTable,
          WatchedPhotographyOpportunityRow
        >,
      ),
      WatchedPhotographyOpportunityRow,
      PrefetchHooks Function()
    >;
typedef $$PhotographyOpportunityResultsTableCreateCompanionBuilder =
    PhotographyOpportunityResultsCompanion Function({
      required String id,
      required String opportunityId,
      required String snapshotId,
      Value<String?> targetId,
      required String outcome,
      Value<String?> reason,
      required DateTime recordedAt,
      Value<int> rowid,
    });
typedef $$PhotographyOpportunityResultsTableUpdateCompanionBuilder =
    PhotographyOpportunityResultsCompanion Function({
      Value<String> id,
      Value<String> opportunityId,
      Value<String> snapshotId,
      Value<String?> targetId,
      Value<String> outcome,
      Value<String?> reason,
      Value<DateTime> recordedAt,
      Value<int> rowid,
    });

class $$PhotographyOpportunityResultsTableFilterComposer
    extends Composer<_$AppDatabase, $PhotographyOpportunityResultsTable> {
  $$PhotographyOpportunityResultsTableFilterComposer({
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

  ColumnFilters<String> get opportunityId => $composableBuilder(
    column: $table.opportunityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PhotographyOpportunityResultsTableOrderingComposer
    extends Composer<_$AppDatabase, $PhotographyOpportunityResultsTable> {
  $$PhotographyOpportunityResultsTableOrderingComposer({
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

  ColumnOrderings<String> get opportunityId => $composableBuilder(
    column: $table.opportunityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PhotographyOpportunityResultsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PhotographyOpportunityResultsTable> {
  $$PhotographyOpportunityResultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get opportunityId => $composableBuilder(
    column: $table.opportunityId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );
}

class $$PhotographyOpportunityResultsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PhotographyOpportunityResultsTable,
          PhotographyOpportunityResultRow,
          $$PhotographyOpportunityResultsTableFilterComposer,
          $$PhotographyOpportunityResultsTableOrderingComposer,
          $$PhotographyOpportunityResultsTableAnnotationComposer,
          $$PhotographyOpportunityResultsTableCreateCompanionBuilder,
          $$PhotographyOpportunityResultsTableUpdateCompanionBuilder,
          (
            PhotographyOpportunityResultRow,
            BaseReferences<
              _$AppDatabase,
              $PhotographyOpportunityResultsTable,
              PhotographyOpportunityResultRow
            >,
          ),
          PhotographyOpportunityResultRow,
          PrefetchHooks Function()
        > {
  $$PhotographyOpportunityResultsTableTableManager(
    _$AppDatabase db,
    $PhotographyOpportunityResultsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhotographyOpportunityResultsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PhotographyOpportunityResultsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PhotographyOpportunityResultsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> opportunityId = const Value.absent(),
                Value<String> snapshotId = const Value.absent(),
                Value<String?> targetId = const Value.absent(),
                Value<String> outcome = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotographyOpportunityResultsCompanion(
                id: id,
                opportunityId: opportunityId,
                snapshotId: snapshotId,
                targetId: targetId,
                outcome: outcome,
                reason: reason,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String opportunityId,
                required String snapshotId,
                Value<String?> targetId = const Value.absent(),
                required String outcome,
                Value<String?> reason = const Value.absent(),
                required DateTime recordedAt,
                Value<int> rowid = const Value.absent(),
              }) => PhotographyOpportunityResultsCompanion.insert(
                id: id,
                opportunityId: opportunityId,
                snapshotId: snapshotId,
                targetId: targetId,
                outcome: outcome,
                reason: reason,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PhotographyOpportunityResultsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PhotographyOpportunityResultsTable,
      PhotographyOpportunityResultRow,
      $$PhotographyOpportunityResultsTableFilterComposer,
      $$PhotographyOpportunityResultsTableOrderingComposer,
      $$PhotographyOpportunityResultsTableAnnotationComposer,
      $$PhotographyOpportunityResultsTableCreateCompanionBuilder,
      $$PhotographyOpportunityResultsTableUpdateCompanionBuilder,
      (
        PhotographyOpportunityResultRow,
        BaseReferences<
          _$AppDatabase,
          $PhotographyOpportunityResultsTable,
          PhotographyOpportunityResultRow
        >,
      ),
      PhotographyOpportunityResultRow,
      PrefetchHooks Function()
    >;
typedef $$OfflinePhotographyPacksTableCreateCompanionBuilder =
    OfflinePhotographyPacksCompanion Function({
      required String id,
      required String name,
      required DateTime createdAt,
      required DateTime dataTimestamp,
      Value<String?> routeJson,
      required String placesJson,
      required String windowsJson,
      required String opportunityJson,
      Value<int> rowid,
    });
typedef $$OfflinePhotographyPacksTableUpdateCompanionBuilder =
    OfflinePhotographyPacksCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<DateTime> dataTimestamp,
      Value<String?> routeJson,
      Value<String> placesJson,
      Value<String> windowsJson,
      Value<String> opportunityJson,
      Value<int> rowid,
    });

class $$OfflinePhotographyPacksTableFilterComposer
    extends Composer<_$AppDatabase, $OfflinePhotographyPacksTable> {
  $$OfflinePhotographyPacksTableFilterComposer({
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

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dataTimestamp => $composableBuilder(
    column: $table.dataTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeJson => $composableBuilder(
    column: $table.routeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placesJson => $composableBuilder(
    column: $table.placesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get windowsJson => $composableBuilder(
    column: $table.windowsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get opportunityJson => $composableBuilder(
    column: $table.opportunityJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflinePhotographyPacksTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflinePhotographyPacksTable> {
  $$OfflinePhotographyPacksTableOrderingComposer({
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

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dataTimestamp => $composableBuilder(
    column: $table.dataTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeJson => $composableBuilder(
    column: $table.routeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placesJson => $composableBuilder(
    column: $table.placesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get windowsJson => $composableBuilder(
    column: $table.windowsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get opportunityJson => $composableBuilder(
    column: $table.opportunityJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflinePhotographyPacksTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflinePhotographyPacksTable> {
  $$OfflinePhotographyPacksTableAnnotationComposer({
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

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get dataTimestamp => $composableBuilder(
    column: $table.dataTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get routeJson =>
      $composableBuilder(column: $table.routeJson, builder: (column) => column);

  GeneratedColumn<String> get placesJson => $composableBuilder(
    column: $table.placesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get windowsJson => $composableBuilder(
    column: $table.windowsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get opportunityJson => $composableBuilder(
    column: $table.opportunityJson,
    builder: (column) => column,
  );
}

class $$OfflinePhotographyPacksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflinePhotographyPacksTable,
          OfflinePhotographyPackRow,
          $$OfflinePhotographyPacksTableFilterComposer,
          $$OfflinePhotographyPacksTableOrderingComposer,
          $$OfflinePhotographyPacksTableAnnotationComposer,
          $$OfflinePhotographyPacksTableCreateCompanionBuilder,
          $$OfflinePhotographyPacksTableUpdateCompanionBuilder,
          (
            OfflinePhotographyPackRow,
            BaseReferences<
              _$AppDatabase,
              $OfflinePhotographyPacksTable,
              OfflinePhotographyPackRow
            >,
          ),
          OfflinePhotographyPackRow,
          PrefetchHooks Function()
        > {
  $$OfflinePhotographyPacksTableTableManager(
    _$AppDatabase db,
    $OfflinePhotographyPacksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflinePhotographyPacksTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OfflinePhotographyPacksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflinePhotographyPacksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> dataTimestamp = const Value.absent(),
                Value<String?> routeJson = const Value.absent(),
                Value<String> placesJson = const Value.absent(),
                Value<String> windowsJson = const Value.absent(),
                Value<String> opportunityJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflinePhotographyPacksCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                dataTimestamp: dataTimestamp,
                routeJson: routeJson,
                placesJson: placesJson,
                windowsJson: windowsJson,
                opportunityJson: opportunityJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime createdAt,
                required DateTime dataTimestamp,
                Value<String?> routeJson = const Value.absent(),
                required String placesJson,
                required String windowsJson,
                required String opportunityJson,
                Value<int> rowid = const Value.absent(),
              }) => OfflinePhotographyPacksCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                dataTimestamp: dataTimestamp,
                routeJson: routeJson,
                placesJson: placesJson,
                windowsJson: windowsJson,
                opportunityJson: opportunityJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflinePhotographyPacksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflinePhotographyPacksTable,
      OfflinePhotographyPackRow,
      $$OfflinePhotographyPacksTableFilterComposer,
      $$OfflinePhotographyPacksTableOrderingComposer,
      $$OfflinePhotographyPacksTableAnnotationComposer,
      $$OfflinePhotographyPacksTableCreateCompanionBuilder,
      $$OfflinePhotographyPacksTableUpdateCompanionBuilder,
      (
        OfflinePhotographyPackRow,
        BaseReferences<
          _$AppDatabase,
          $OfflinePhotographyPacksTable,
          OfflinePhotographyPackRow
        >,
      ),
      OfflinePhotographyPackRow,
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
  $$SavedRoutesTableTableManager get savedRoutes =>
      $$SavedRoutesTableTableManager(_db, _db.savedRoutes);
  $$SavedJourneysTableTableManager get savedJourneys =>
      $$SavedJourneysTableTableManager(_db, _db.savedJourneys);
  $$ImportedRouteTracksTableTableManager get importedRouteTracks =>
      $$ImportedRouteTracksTableTableManager(_db, _db.importedRouteTracks);
  $$ProfilePreferenceRecordsTableTableManager get profilePreferenceRecords =>
      $$ProfilePreferenceRecordsTableTableManager(
        _db,
        _db.profilePreferenceRecords,
      );
  $$BaseRegionsTableTableManager get baseRegions =>
      $$BaseRegionsTableTableManager(_db, _db.baseRegions);
  $$SavedInspirationNotesTableTableManager get savedInspirationNotes =>
      $$SavedInspirationNotesTableTableManager(_db, _db.savedInspirationNotes);
  $$WildlifeMapLayerCachesTableTableManager get wildlifeMapLayerCaches =>
      $$WildlifeMapLayerCachesTableTableManager(
        _db,
        _db.wildlifeMapLayerCaches,
      );
  $$WatchedPhotographyOpportunitiesTableTableManager
  get watchedPhotographyOpportunities =>
      $$WatchedPhotographyOpportunitiesTableTableManager(
        _db,
        _db.watchedPhotographyOpportunities,
      );
  $$PhotographyOpportunityResultsTableTableManager
  get photographyOpportunityResults =>
      $$PhotographyOpportunityResultsTableTableManager(
        _db,
        _db.photographyOpportunityResults,
      );
  $$OfflinePhotographyPacksTableTableManager get offlinePhotographyPacks =>
      $$OfflinePhotographyPacksTableTableManager(
        _db,
        _db.offlinePhotographyPacks,
      );
}
