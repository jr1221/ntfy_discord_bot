import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nyxx/nyxx.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

class ServerBasepathDirective extends Table {
  IntColumn get id => integer()();
  TextColumn get basePath => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [ServerBasepathDirective])
class ConfDatabase extends _$ConfDatabase {
  ConfDatabase() : super(_openConnection());

  // you should bump this number whenever you change or add a table definition.
  // Migrations are covered later in the documentation.
  @override
  int get schemaVersion => 1;

  Future<ServerBasepathDirectiveData?> fetchBasepathDirective(Snowflake id) {
    return (select(serverBasepathDirective)
          ..where((tbl) => tbl.id.equals(id.value)))
        .getSingleOrNull();
  }

  Future<void> updateBasepath(Snowflake id, String basePath) {
    return into(serverBasepathDirective).insert(
        ServerBasepathDirectiveData(id: id.value, basePath: basePath),
        mode: InsertMode.insertOrReplace);
  }
}

LazyDatabase _openConnection() {
  // the LazyDatabase util lets us find the right location for the file async.
  return LazyDatabase(() async {
    // put the database file, called db.sqlite here, into the documents folder
    // for your app.
    final file = File(p.join(p.current, 'db.sqlite'));
    print(file.absolute.path);
    return NativeDatabase.createInBackground(file);
  });
}
