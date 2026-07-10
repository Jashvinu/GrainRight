import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

bool supportsConnection() => true;

QueryExecutor openConnection() {
  return DatabaseConnection.delayed(_openWasmConnection());
}

Future<DatabaseConnection> _openWasmConnection() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('/sqlite3.wasm'));
  sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  return DatabaseConnection(WasmDatabase.inMemory(sqlite));
}
