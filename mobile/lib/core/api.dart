import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Derleme sırasında: flutter build appbundle --dart-define=API_URL=https://api.ucuza.com
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000');

String get wsUrl => apiUrl.replaceFirst('http', 'ws');

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class Api {
  Api(this._storage) {
    dio = Dio(BaseOptions(
      baseUrl: apiUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 120), // AI uçları uzun sürebilir
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      final t = token ?? await _storage.read(key: 'token');
      if (t != null) o.headers['Authorization'] = 'Bearer $t';
      h.next(o);
    }));
  }

  final FlutterSecureStorage _storage;
  late final Dio dio;
  String? token;

  Future<void> saveToken(String? t) async {
    token = t;
    if (t == null) {
      await _storage.delete(key: 'token');
    } else {
      await _storage.write(key: 'token', value: t);
    }
  }

  Future<String?> loadToken() async => token = await _storage.read(key: 'token');

  Future<T> _wrap<T>(Future<Response> Function() call) async {
    try {
      final r = await call();
      return r.data as T;
    } on DioException catch (e) {
      final data = e.response?.data;
      var msg = 'Bağlantı hatası. İnternetinizi kontrol edin.';
      if (data is Map && data['detail'] != null) {
        msg = data['detail'] is String ? data['detail'] : 'Geçersiz istek';
      }
      throw ApiException(msg, e.response?.statusCode);
    }
  }

  Future<T> get<T>(String path, [Map<String, dynamic>? q]) =>
      _wrap(() => dio.get(path, queryParameters: q?..removeWhere((k, v) => v == null)));
  Future<T> post<T>(String path, [Object? body]) => _wrap(() => dio.post(path, data: body));
  Future<T> put<T>(String path, [Object? body]) => _wrap(() => dio.put(path, data: body));
  Future<T> patch<T>(String path, [Object? body]) => _wrap(() => dio.patch(path, data: body));
  Future<T> delete<T>(String path) => _wrap(() => dio.delete(path));

  Future<T> upload<T>(String path, FormData form, {void Function(double)? onProgress}) => _wrap(() => dio.post(
        path,
        data: form,
        onSendProgress: (s, t) => onProgress?.call(t > 0 ? s / t : 0),
      ));
}

final apiProvider = Provider<Api>((ref) => Api(const FlutterSecureStorage()));
