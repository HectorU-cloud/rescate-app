import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda si una cuenta ya vio (o salto) el recorrido de bienvenida.
///
/// La marca es por usuario y NO se borra al cerrar sesion: asi quien vuelve a
/// entrar no ve el tour otra vez. Se puede repetir a mano desde Perfil.
class TourService {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static String _key(int userId) => 'tour_seen_$userId';

  Future<bool> hasSeen(int userId) async {
    return await _prefs.getBool(_key(userId)) ?? false;
  }

  Future<void> markSeen(int userId) async {
    await _prefs.setBool(_key(userId), true);
  }
}
