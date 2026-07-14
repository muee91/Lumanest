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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SavedPlacesTable savedPlaces = $SavedPlacesTable(this);
  late final $RecentRouteDestinationsTable recentRouteDestinations =
      $RecentRouteDestinationsTable(this);
  late final $ProfilePreferenceRecordsTable profilePreferenceRecords =
      $ProfilePreferenceRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    savedPlaces,
    recentRouteDestinations,
    profilePreferenceRecords,
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
  $$ProfilePreferenceRecordsTableTableManager get profilePreferenceRecords =>
      $$ProfilePreferenceRecordsTableTableManager(
        _db,
        _db.profilePreferenceRecords,
      );
}
