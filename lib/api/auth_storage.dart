import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// 토큰을 OS 보안 저장소(Android Keystore / iOS Keychain)에 저장.
// 웹의 localStorage/sessionStorage 분기보다 안전 — 앱은 자체 샌드박스라 다른 앱이 못 읽음.
class AuthStorage {
  static const _storage = FlutterSecureStorage();
  static const _kAccessToken = 'authToken';
  static const _kRefreshToken = 'refreshToken';

  static Future<void> save({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
  }

  static Future<String?> readAccessToken() => _storage.read(key: _kAccessToken);
  static Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  static Future<bool> hasToken() async {
    final token = await readAccessToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
  }
}
