import 'dart:convert';

import 'package:http/http.dart' as http;

import '../state/guest_mode.dart';
import '../state/local_ingredient_store.dart';
import 'api_client.dart';

// 식재료 CRUD를 한 곳에서 분기.
// - 게스트(GuestMode.isGuest): SharedPreferences 기반 LocalIngredientStore
// - 로그인: ApiClient를 통해 /api/ingredients 호출
// 호출부가 거의 그대로 동작하도록 http.Response 모양으로 반환한다.
class IngredientRepo {
  static http.Response _ok(Object json) => http.Response(
        jsonEncode(json),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  static http.Response _notFound() => http.Response('not found', 404);

  static Future<http.Response> list({int? fridgeId}) async {
    if (await GuestMode.isGuest()) {
      final items = await LocalIngredientStore.list();
      return _ok(items);
    }
    final path = fridgeId != null
        ? '/api/ingredients?fridgeId=$fridgeId'
        : '/api/ingredients';
    return ApiClient.get(path);
  }

  static Future<http.Response> add(Map<String, dynamic> body) async {
    if (await GuestMode.isGuest()) {
      final row = await LocalIngredientStore.add(body);
      return _ok(row);
    }
    return ApiClient.post('/api/ingredients', body: body);
  }

  static Future<http.Response> update(int id, Map<String, dynamic> body) async {
    if (await GuestMode.isGuest()) {
      final ok = await LocalIngredientStore.update(id, body);
      return ok ? _ok({'id': id, ...body}) : _notFound();
    }
    return ApiClient.put('/api/ingredients/$id', body: body);
  }

  static Future<http.Response> delete(int id) async {
    if (await GuestMode.isGuest()) {
      final ok = await LocalIngredientStore.delete(id);
      return ok ? _ok({'success': true}) : _notFound();
    }
    return ApiClient.delete('/api/ingredients/$id');
  }
}
