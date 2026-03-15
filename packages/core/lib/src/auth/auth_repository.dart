import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sadece debug amaçlı: mevcut oturum ve kullanıcı bilgisini loglar.
  void debugPrintCurrentAuthState({String label = 'AUTH'}) {
    final session = _client.auth.currentSession;
    final user = _client.auth.currentUser;
    final token = session?.accessToken;
    final prefix = token == null
        ? 'null'
        : (token.length <= 10 ? token : '${token.substring(0, 10)}...');

    // ignore: avoid_print
    print('[$label] uid=${user?.id} hasSession=${session != null} '
        'tokenPrefix=$prefix');
  }
}
