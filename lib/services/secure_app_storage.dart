import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureAppStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> readString(
    String key, {
    bool migrateFromSharedPreferences = true,
  }) async {
    final value = await _storage.read(key: key);
    if (value != null || !migrateFromSharedPreferences) return value;

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy == null) return null;

    await _storage.write(key: key, value: legacy);
    await prefs.remove(key);
    return legacy;
  }

  Future<void> writeString(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  Future<int?> readInt(
    String key, {
    bool migrateFromSharedPreferences = true,
  }) async {
    final value = await readString(
      key,
      migrateFromSharedPreferences: migrateFromSharedPreferences,
    );
    if (value != null) return int.tryParse(value);
    if (!migrateFromSharedPreferences) return null;

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getInt(key);
    if (legacy == null) return null;

    await writeInt(key, legacy);
    await prefs.remove(key);
    return legacy;
  }

  Future<void> writeInt(String key, int value) {
    return writeString(key, value.toString());
  }

  Future<Map<String, dynamic>?> readJsonMap(String key) async {
    final value = await readString(key);
    if (value == null || value.isEmpty) return null;
    final decoded = jsonDecode(value);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<void> writeJson(String key, Object value) {
    return writeString(key, jsonEncode(value));
  }

  Future<void> remove(String key) async {
    await _storage.delete(key: key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
