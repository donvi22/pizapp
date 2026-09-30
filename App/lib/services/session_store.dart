import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStore {
  static const _key = 'pizapp_auth_token';
  final _storage = const FlutterSecureStorage();

  Future<String?> readToken() => _storage.read(key: _key);

  Future<void> saveToken(String token) => _storage.write(key: _key, value: token);

  Future<void> clearToken() => _storage.delete(key: _key);
}
