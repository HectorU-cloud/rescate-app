import 'dart:convert';

import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/food_pack.dart';
import '../models/reservation.dart';
import '../models/user.dart';
import 'session_service.dart';

class ApiService {
  // URL del backend. Se puede cambiar al compilar/ejecutar sin tocar el codigo:
  //   flutter run --dart-define=API_BASE_URL=https://api.tudominio.com
  // Por defecto apunta al emulador de Android (10.0.2.2 = tu PC).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.51:8000',
  );

  /// Paginas legales publicas (las sirve el propio backend).
  static String get privacyUrl => '$baseUrl/privacy';
  static String get termsUrl => '$baseUrl/terms';

  /// Convierte la ruta que devuelve el servidor ("/uploads/packs/x.jpg")
  /// en una URL completa que Image.network pueda abrir.
  static String? resolveImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '$baseUrl$path';
  }

  final SessionService _sessionService = SessionService();

  // -------------------------------------------------
  // HELPERS
  // -------------------------------------------------

  Future<Map<String, String>> _headers({
    bool withAuth = true,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (withAuth) {
      final token = await _sessionService.getToken();

      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

    Never _handleError(http.Response response) {
    if (response.statusCode == 401) {
      throw Exception('Tu sesión expiró. Vuelve a iniciar sesión.');
    }

    // 👇 Extraemos el mensaje ANTES de lanzarlo
    String message = 'Error del servidor (${response.statusCode})';

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      final detail = body['detail'];
      final msg = body['message'];

      if (detail != null && detail.toString().isNotEmpty) {
        message = detail.toString();
      } else if (msg != null && msg.toString().isNotEmpty) {
        message = msg.toString();
      }
    } catch (_) {
      // si no se puede parsear, dejamos el mensaje genérico
    }

    // 👇 Ahora lanzamos FUERA del try/catch
    throw Exception(message);
  }

  // -------------------------------------------------
  // AUTH
  // -------------------------------------------------

  Future<User> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    final user = User.fromJson(body);
    final token = body['access_token']?.toString() ?? '';

    await _sessionService.saveUser(user, token: token);

    return user;
  }

  Future<User> loginWithGoogle({
    required String idToken,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/google'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({
        'id_token': idToken,
      }),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    final user = User.fromJson(body);
    final token = body['access_token']?.toString() ?? '';

    await _sessionService.saveUser(user, token: token);

    return user;
  }

  Future<User> register({
    required String name,
    required String email,
    required String password,
    bool isBusiness = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'is_business': isBusiness,
      }),
    );

    if (response.statusCode != 201) {
      _handleError(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    final user = User.fromJson(body);
    final token = body['access_token']?.toString() ?? '';

    await _sessionService.saveUser(user, token: token);

    return user;
  }

  // -------------------------------------------------
  // PACKS (CLIENTE)
  // -------------------------------------------------

  Future<List<FoodPack>> getPacks() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/packs'),
          headers: await _headers(withAuth: false),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final data = jsonDecode(response.body) as List<dynamic>;

    return data
        .map((item) => FoodPack.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // -------------------------------------------------
  // RESERVAS (CLIENTE)
  // -------------------------------------------------

  Future<Map<String, dynamic>> createReservation({
    required int foodPackId,
    required int quantity,
    String paymentMethod = 'online',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/reservations'),
      headers: await _headers(),
      body: jsonEncode({
        'food_pack_id': foodPackId,
        'quantity': quantity,
        'payment_method': paymentMethod,
      }),
    );

    if (response.statusCode != 201) {
      _handleError(response);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Reservation>> getReservations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/reservations'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final data = jsonDecode(response.body) as List<dynamic>;

    return data
        .map((item) => Reservation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Reservation> cancelReservation({
    required int reservationId,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/reservations/$reservationId/cancel'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return Reservation.fromJson(body);
  }

  // -------------------------------------------------
  // NEGOCIO
  // -------------------------------------------------

  /// Devuelve el negocio del usuario logueado, o null si no tiene.
  Future<Map<String, dynamic>?> getMyBusiness() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/businesses/me'),
      headers: await _headers(),
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      _handleError(response);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createBusiness({
    required String name,
    String? description,
    required String address,
    required String city,
    double? latitude,
    double? longitude,
    String? phone,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/businesses'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'description': description,
        'address': address,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'phone': phone,
      }),
    );

    if (response.statusCode != 201) {
      _handleError(response);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<FoodPack>> getMyPacks() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/packs/me'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final data = jsonDecode(response.body) as List<dynamic>;

    return data
        .map((item) => FoodPack.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Sube la foto de un pack y devuelve la ruta para guardarla en
  /// `image_url` al crear o editar el pack.
  Future<String> uploadPackImage(XFile file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/uploads/pack-image'),
    );

    final headers = await _headers();
    headers.remove('Content-Type'); // lo define el multipart
    request.headers.addAll(headers);

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        await file.readAsBytes(),
        filename: file.name.isEmpty ? 'foto.jpg' : file.name,
      ),
    );

    final streamed = await request.send().timeout(
          const Duration(seconds: 30),
        );
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    return data['image_url'] as String;
  }

  Future<Map<String, dynamic>> createPack({
    required int categoryId,
    required String title,
    String? description,
    required double price,
    required double originalPrice,
    required int quantity,
    required DateTime pickupStart,
    required DateTime pickupEnd,
    String? imageUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/packs'),
      headers: await _headers(),
      body: jsonEncode({
        'category_id': categoryId,
        'title': title,
        'description': description,
        'price': price,
        'original_price': originalPrice,
        'quantity': quantity,
        'pickup_start': pickupStart.toUtc().toIso8601String(),
        'pickup_end': pickupEnd.toUtc().toIso8601String(),
        'image_url': imageUrl,
      }),
    );

    if (response.statusCode != 201) {
      _handleError(response);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Reservation>> getReceivedReservations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/reservations/received'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final data = jsonDecode(response.body) as List<dynamic>;

    return data
        .map((item) => Reservation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Reservation> validateReservation({
    required String reservationCode,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/reservations/$reservationCode/validate'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return Reservation.fromJson(body);
  }

    // -------------------------------------------------
  // CATEGORÍAS
  // -------------------------------------------------

  Future<List<Map<String, dynamic>>> getCategories() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/categories'),
      headers: await _headers(withAuth: false),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final data = jsonDecode(response.body) as List<dynamic>;

    return data.cast<Map<String, dynamic>>();
  }
    // -------------------------------------------------
  // NEGOCIO - EDITAR / ELIMINAR PACK
  // -------------------------------------------------

  Future<FoodPack> updatePack({
    required int packId,
    int? categoryId,
    String? title,
    String? description,
    double? price,
    double? originalPrice,
    int? quantity,
    DateTime? pickupStart,
    DateTime? pickupEnd,
    String? imageUrl,
    String? status,
  }) async {
    final body = <String, dynamic>{};

    if (categoryId != null) body['category_id'] = categoryId;
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (price != null) body['price'] = price;
    if (originalPrice != null) body['original_price'] = originalPrice;
    if (quantity != null) body['quantity'] = quantity;
    if (pickupStart != null) {
      body['pickup_start'] = pickupStart.toUtc().toIso8601String();
    }
    if (pickupEnd != null) {
      body['pickup_end'] = pickupEnd.toUtc().toIso8601String();
    }
    if (imageUrl != null) body['image_url'] = imageUrl;
    if (status != null) body['status'] = status;

    final response = await http.put(
      Uri.parse('$baseUrl/api/packs/$packId'),
      headers: await _headers(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    return FoodPack.fromJson(data);
  }

  Future<void> deletePack({required int packId}) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/packs/$packId'),
      headers: await _headers(),
    );

    if (response.statusCode != 204) {
      _handleError(response);
    }
  }

    // -------------------------------------------------
  // NEGOCIO - ESTADÍSTICAS
  // -------------------------------------------------

  Future<Map<String, dynamic>> getMyStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/businesses/me/stats'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
    // -------------------------------------------------
  // NEGOCIO - LIQUIDAR COMISIONES
  // -------------------------------------------------

  Future<Map<String, dynamic>> settleFees() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/businesses/me/settle-fees'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
    // -------------------------------------------------
  // NEGOCIO - NOTIFICACIONES IN-APP
  // -------------------------------------------------

  Future<int> getUnseenReservationsCount() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/reservations/unseen-count'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return (body['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markReservationsAsSeen() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/reservations/mark-seen'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }
  }
    // -------------------------------------------------
  // RECUPERAR CONTRASENA (codigo de 6 digitos por correo)
  // -------------------------------------------------

  /// Pide un codigo. El servidor responde igual exista o no el correo.
  Future<void> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/reset-password'),
      headers: await _headers(withAuth: false),
      body: jsonEncode({
        'email': email,
        'code': code,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }
  }

  // -------------------------------------------------
  // ELIMINAR CUENTA
  // -------------------------------------------------

  /// Elimina la cuenta del usuario actual (pide su contrasena).
  /// Si sale bien, tambien cierra la sesion guardada en el telefono.
  Future<void> deleteAccount(String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/delete-account'),
      headers: await _headers(),
      body: jsonEncode({'password': password}),
    );

    if (response.statusCode != 200) {
      _handleError(response);
    }

    await _sessionService.clearSession();
  }

  // -------------------------------------------------
  // NOTIFICACIONES - DEVICE TOKEN
  // -------------------------------------------------

  Future<void> registerDeviceToken(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/notifications/register-token'),
      headers: await _headers(),
      body: jsonEncode({
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      _handleError(response);
    }
  }
}