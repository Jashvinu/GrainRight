import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

bool supportsConnection() => true;

QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'grainright_offline.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
