import 'dart:io';

Future<Map<String, String>> loadRuntimeLocalConfigImpl() async {
  final values = <String, String>{};
  await _readConfigFile(values, '.env');
  await _readConfigFile(values, 'android/local.properties');
  values.addAll(Platform.environment);
  return values;
}

Future<void> _readConfigFile(Map<String, String> values, String path) async {
  final file = File(path);
  if (!await file.exists()) return;

  final lines = await file.readAsLines();
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final separator = line.indexOf('=');
    if (separator <= 0) continue;

    final key = line.substring(0, separator).trim();
    final value = _unquote(line.substring(separator + 1).trim());
    if (key.isNotEmpty && value.isNotEmpty) {
      values[key] = value;
    }
  }
}

String _unquote(String value) {
  if (value.length < 2) return value;
  final first = value[0];
  final last = value[value.length - 1];
  if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
    return value.substring(1, value.length - 1);
  }
  return value;
}
