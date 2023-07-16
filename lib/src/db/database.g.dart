// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ServerBasepathDirectiveTable extends ServerBasepathDirective
    with TableInfo<$ServerBasepathDirectiveTable, ServerBasepathDirectiveData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServerBasepathDirectiveTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _basePathMeta =
      const VerificationMeta('basePath');
  @override
  late final GeneratedColumn<String> basePath = GeneratedColumn<String>(
      'base_path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('https://ntfy.sh/'));
  @override
  List<GeneratedColumn> get $columns => [id, basePath];
  @override
  String get aliasedName => _alias ?? 'server_basepath_directive';
  @override
  String get actualTableName => 'server_basepath_directive';
  @override
  VerificationContext validateIntegrity(
      Insertable<ServerBasepathDirectiveData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('base_path')) {
      context.handle(_basePathMeta,
          basePath.isAcceptableOrUnknown(data['base_path']!, _basePathMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ServerBasepathDirectiveData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServerBasepathDirectiveData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      basePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_path'])!,
    );
  }

  @override
  $ServerBasepathDirectiveTable createAlias(String alias) {
    return $ServerBasepathDirectiveTable(attachedDatabase, alias);
  }
}

class ServerBasepathDirectiveData extends DataClass
    implements Insertable<ServerBasepathDirectiveData> {
  final int id;
  final String basePath;
  const ServerBasepathDirectiveData({required this.id, required this.basePath});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['base_path'] = Variable<String>(basePath);
    return map;
  }

  ServerBasepathDirectiveCompanion toCompanion(bool nullToAbsent) {
    return ServerBasepathDirectiveCompanion(
      id: Value(id),
      basePath: Value(basePath),
    );
  }

  factory ServerBasepathDirectiveData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServerBasepathDirectiveData(
      id: serializer.fromJson<int>(json['id']),
      basePath: serializer.fromJson<String>(json['basePath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'basePath': serializer.toJson<String>(basePath),
    };
  }

  ServerBasepathDirectiveData copyWith({int? id, String? basePath}) =>
      ServerBasepathDirectiveData(
        id: id ?? this.id,
        basePath: basePath ?? this.basePath,
      );
  @override
  String toString() {
    return (StringBuffer('ServerBasepathDirectiveData(')
          ..write('id: $id, ')
          ..write('basePath: $basePath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, basePath);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerBasepathDirectiveData &&
          other.id == this.id &&
          other.basePath == this.basePath);
}

class ServerBasepathDirectiveCompanion
    extends UpdateCompanion<ServerBasepathDirectiveData> {
  final Value<int> id;
  final Value<String> basePath;
  const ServerBasepathDirectiveCompanion({
    this.id = const Value.absent(),
    this.basePath = const Value.absent(),
  });
  ServerBasepathDirectiveCompanion.insert({
    this.id = const Value.absent(),
    this.basePath = const Value.absent(),
  });
  static Insertable<ServerBasepathDirectiveData> custom({
    Expression<int>? id,
    Expression<String>? basePath,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (basePath != null) 'base_path': basePath,
    });
  }

  ServerBasepathDirectiveCompanion copyWith(
      {Value<int>? id, Value<String>? basePath}) {
    return ServerBasepathDirectiveCompanion(
      id: id ?? this.id,
      basePath: basePath ?? this.basePath,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (basePath.present) {
      map['base_path'] = Variable<String>(basePath.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServerBasepathDirectiveCompanion(')
          ..write('id: $id, ')
          ..write('basePath: $basePath')
          ..write(')'))
        .toString();
  }
}

abstract class _$ConfDatabase extends GeneratedDatabase {
  _$ConfDatabase(QueryExecutor e) : super(e);
  late final $ServerBasepathDirectiveTable serverBasepathDirective =
      $ServerBasepathDirectiveTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [serverBasepathDirective];
}
