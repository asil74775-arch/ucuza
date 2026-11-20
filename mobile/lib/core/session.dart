import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';

class AuthState {
  const AuthState({this.user, this.loading = false, this.ready = false});
  final Map<String, dynamic>? user;
  final bool loading;
  final bool ready;
  bool get loggedIn => user != null;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this.api) : super(const AuthState()) {
    _restore();
  }
  final Api api;
  final changes = ValueNotifier<int>(0); // go_router yenilemesi için

  void _set(AuthState s) {
    state = s;
    changes.value++;
  }

  Future<void> _restore() async {
    if (await api.loadToken() != null) {
      try {
        final me = await api.get<Map<String, dynamic>>('/auth/me');
        _set(AuthState(user: me, ready: true));
        return;
      } catch (_) {
        await api.saveToken(null);
      }
    }
    _set(const AuthState(ready: true));
  }

  Future<void> login(String email, String password) async {
    final r = await api.post<Map<String, dynamic>>('/auth/login', {'email': email, 'password': password});
    await api.saveToken(r['token']);
    _set(AuthState(user: r['user'], ready: true));
  }

  Future<void> register(String email, String password, String name, List<String> interests) async {
    final r = await api.post<Map<String, dynamic>>('/auth/register',
        {'email': email, 'password': password, 'display_name': name, 'interests': interests});
    await api.saveToken(r['token']);
    _set(AuthState(user: r['user'], ready: true));
  }

  Future<void> logout() async {
    await api.saveToken(null);
    _set(const AuthState(ready: true));
  }

  Future<void> deleteAccount() async {
    await api.delete('/auth/me');
    await logout();
  }
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) => AuthController(ref.read(apiProvider)));

/// Zevk profili öğrenimi için davranış olayı gönderir (hata yutar).
Future<void> track(WidgetRef ref, String kind, {int? productId, Map<String, dynamic>? payload}) async {
  if (!ref.read(authProvider).loggedIn) return;
  try {
    await ref.read(apiProvider).post('/profile/events', {'kind': kind, 'product_id': productId, 'payload': payload ?? {}});
  } catch (_) {}
}
