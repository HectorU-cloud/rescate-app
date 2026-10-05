import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'session_service.dart';

/// Handler para mensajes en background.
/// Debe ser top-level (fuera de la clase).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 Notificación en background: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final ApiService _apiService = ApiService();
  final SessionService _sessionService = SessionService();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint('🔔 Permiso de notificaciones: ${settings.authorizationStatus}');

      await _setupLocalNotifications();

      final token = await _messaging.getToken();
      debugPrint('🎫 FCM Token: $token');

      if (token != null) {
        await _sendTokenToBackend(token);
      }

      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('🎫 Token renovado: $newToken');
        _sendTokenToBackend(newToken);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    } catch (e) {
      debugPrint('❌ Error inicializando notificaciones: $e');
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final user = await _sessionService.getUser();

      if (user == null) {
        debugPrint('⚠️ Sin sesión activa, no se envía el token');
        return;
      }

      await _apiService.registerDeviceToken(token);
      debugPrint('✅ Token registrado en el backend');
    } catch (e) {
      debugPrint('❌ Error al registrar token: $e');
    }
  }

  /// Vuelve a enviar el token tras login/registro.
  Future<void> syncTokenAfterLogin() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('❌ Error en syncTokenAfterLogin: $e');
    }
  }

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(initSettings);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('📩 Foreground: ${message.notification?.title}');

    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rescate_channel',
          'Rescate',
          channelDescription: 'Notificaciones de Rescate',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('👆 Usuario tocó notificación: ${message.data}');
  }
}