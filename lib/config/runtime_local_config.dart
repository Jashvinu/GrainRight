import 'runtime_local_config_stub.dart'
    if (dart.library.io) 'runtime_local_config_io.dart';

Future<Map<String, String>> loadRuntimeLocalConfig() {
  return loadRuntimeLocalConfigImpl();
}
