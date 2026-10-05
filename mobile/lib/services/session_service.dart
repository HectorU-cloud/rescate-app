import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

class SessionService {
  static const String _userIdKey = 'session_user_id';
  static const String _nameKey = 'session_name';
  static const String _emailKey = 'session_email';
  static const String _isBusinessKey = 'session_is_business';
  static const String _tokenKey = 'session_token';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  // -------------------------------------------------
  // GUARDAR SESIÓN (usuario + token)
  // -------------------------------------------------

  Future<void> saveUser(User user, {String? token}) async {
    await _prefs.setInt(_userIdKey, user.id);
    await _prefs.setString(_nameKey, user.name);
    await _prefs.setString(_emailKey, user.email);
    await _prefs.setBool(_isBusinessKey, user.isBusiness);

    if (token != null && token.isNotEmpty) {
      await _prefs.setString(_tokenKey, token);
    }
  }

  Future<void> saveToken(String token) async {
    await _prefs.setString(_tokenKey, token);
  }

  // -------------------------------------------------
  // LEER SESIÓN
  // -------------------------------------------------

  Future<User?> getUser() async {
    final userId = await _prefs.getInt(_userIdKey);
    final name = await _prefs.getString(_nameKey);
    final email = await _prefs.getString(_emailKey);
    final isBusiness = await _prefs.getBool(_isBusinessKey);

    if (userId == null ||
        name == null ||
        email == null ||
        isBusiness == null) {
      return null;
    }

    return User(
      id: userId,
      name: name,
      email: email,
      isBusiness: isBusiness,
    );
  }

  Future<String?> getToken() async {
    return _prefs.getString(_tokenKey);
  }

  Future<bool> hasSession() async {
    final userId = await _prefs.getInt(_userIdKey);
    final token = await _prefs.getString(_tokenKey);

    return userId != null && token != null;
  }

  // -------------------------------------------------
  // LIMPIAR SESIÓN
  // -------------------------------------------------

  Future<void> clearSession() async {
    await _prefs.remove(_userIdKey);
    await _prefs.remove(_nameKey);
    await _prefs.remove(_emailKey);
    await _prefs.remove(_isBusinessKey);
    await _prefs.remove(_tokenKey);
  }
}