import 'package:drift/drift.dart';

import 'local_database_connection_stub.dart'
    if (dart.library.io) 'local_database_connection_io.dart';

bool isLocalDatabaseSupported() => supportsConnection();

QueryExecutor openLocalDatabaseConnection() => openConnection();
