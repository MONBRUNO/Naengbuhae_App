import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../state/guest_mode.dart';
import 'auth_storage.dart';

// 모든 인증 필요한 API 호출은 ApiClient를 통과시킨다.
// 웹 프론트의 utils/apiClient.ts와 같은 책임:
// - Authorization 헤더 자동 부착
// - 401/403 응답 시 refresh token으로 access token 재발급 + 1회 재시도
// - 동시 401 발생해도 refresh는 한 번만 실행 (inflightRefresh 공유)
// - 재발급 실패 시 토큰 정리 + 로그인 화면으로
class ApiClient {
  // Android 에뮬레이터: 호스트의 localhost = 10.0.2.2
  // iOS 시뮬레이터: localhost
  // 실기기: 빌드 시 --dart-define=API_BASE_URL=http://<PC_LAN_IP>:8080 로 override
  //   예: flutter run --dart-define=API_BASE_URL=http://192.168.80.251:8080
  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    if (kReleaseMode) return 'https://naengbuhae.onrender.com';
    if (Platform.isAndroid) return 'http://10.0.2.2:8080';
    return 'http://localhost:8080';
  }

  // 동시 401 시 refresh가 중복 호출되지 않도록 promise 공유
  static Future<bool>? _inflightRefresh;

  // 외부에서 listen 가능한 로그아웃 신호. UI에서 듣고 로그인 화면으로 이동.
  static final StreamController<void> _onLoggedOut = StreamController<void>.broadcast();
  static Stream<void> get onLoggedOut => _onLoggedOut.stream;

  static Future<Map<String, String>> _buildHeaders([Map<String, String>? extra]) async {
    final token = await AuthStorage.readAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      ...?extra,
    };
  }

  static Future<bool> _refreshAccessToken() async {
    final refresh = await AuthStorage.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    if (_inflightRefresh != null) return _inflightRefresh!;

    final completer = Completer<bool>();
    _inflightRefresh = completer.future;

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/user/token/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refresh}),
      );
      if (res.statusCode != 200) {
        completer.complete(false);
        return false;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newAccess = data['token'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (newAccess == null || newRefresh == null) {
        completer.complete(false);
        return false;
      }
      await AuthStorage.save(accessToken: newAccess, refreshToken: newRefresh);
      completer.complete(true);
      return true;
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      _inflightRefresh = null;
    }
  }

  // 메인 API 호출 진입점. response.body 그대로 반환하므로 caller가 jsonDecode.
  static Future<http.Response> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(path.startsWith('http') ? path : '$baseUrl$path');
    final encoded = body == null ? null : jsonEncode(body);

    Future<http.Response> doRequest() async {
      final h = await _buildHeaders(headers);
      switch (method.toUpperCase()) {
        case 'GET':
          return http.get(uri, headers: h);
        case 'POST':
          return http.post(uri, headers: h, body: encoded);
        case 'PUT':
          return http.put(uri, headers: h, body: encoded);
        case 'DELETE':
          return http.delete(uri, headers: h, body: encoded);
        case 'PATCH':
          return http.patch(uri, headers: h, body: encoded);
        default:
          throw ArgumentError('Unsupported method: $method');
      }
    }

    var res = await doRequest();

    // 인증 실패: refresh 시도 → 성공 시 1회 재시도, 실패 시 로그아웃 신호.
    // 게스트는 처음부터 토큰이 없으므로 401을 받아도 로그아웃으로 처리하지 않는다 (화면이 자체적으로 가드).
    if (res.statusCode == 401 || res.statusCode == 403) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        res = await doRequest();
      } else if (!GuestMode.currentlyGuest) {
        await AuthStorage.clear();
        _onLoggedOut.add(null);
      }
    }
    return res;
  }

  static Future<http.Response> get(String path) => request('GET', path);
  static Future<http.Response> post(String path, {Object? body}) => request('POST', path, body: body);
  static Future<http.Response> put(String path, {Object? body}) => request('PUT', path, body: body);
  static Future<http.Response> patch(String path, {Object? body}) => request('PATCH', path, body: body);
  static Future<http.Response> delete(String path) => request('DELETE', path);

  // 이미지 등 파일 업로드용 multipart 요청. 401 시 refresh 후 1회 재시도.
  static Future<http.Response> uploadFile(
    String path, {
    required String fieldName,
    required String filePath,
  }) async {
    final uri = Uri.parse(path.startsWith('http') ? path : '$baseUrl$path');

    Future<http.Response> doRequest() async {
      final token = await AuthStorage.readAccessToken();
      final req = http.MultipartRequest('POST', uri);
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      req.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    }

    var res = await doRequest();
    if (res.statusCode == 401 || res.statusCode == 403) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        res = await doRequest();
      } else if (!GuestMode.currentlyGuest) {
        await AuthStorage.clear();
        _onLoggedOut.add(null);
      }
    }
    return res;
  }

  // 서버에 refresh token 폐기까지 보내는 로그아웃 헬퍼
  static Future<void> logoutOnServer() async {
    final refresh = await AuthStorage.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return;
    try {
      await http.post(
        Uri.parse('$baseUrl/user/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refresh}),
      );
    } catch (_) {
      // 네트워크 오류여도 로컬 토큰은 어차피 비울 거라 무시
    }
  }
}
