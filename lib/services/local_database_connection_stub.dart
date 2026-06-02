import 'package:drift/drift.dart';

bool supportsConnection() => false;

QueryExecutor openConnection() {
  throw UnsupportedError('Local offline database is not available here.');
}
