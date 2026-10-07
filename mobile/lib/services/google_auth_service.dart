import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';

/// Maneja exclusivamente la autenticación Google/Firebase.
/// El backend de Rescate sigue siendo quien entrega el JWT de la aplicación.
class GoogleAuthService {
  GoogleAuthService._();

  static final GoogleAuthService instance = GoogleAuthService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;

    await _googleSignIn.initialize();
    _initialized = true;
  }

  Future<String> signInAndGetIdToken() async {
    await _initialize();

    final googleUser = await _googleSignIn.authenticate();
    final googleAuth = googleUser.authentication;

    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google no devolvió un ID token válido.');
    }

    final credential = firebase_auth.GoogleAuthProvider.credential(
      idToken: idToken,
    );

    await _firebaseAuth.signInWithCredential(credential);

    // Obtenemos el ID token de Firebase después de completar el login.
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      throw Exception('No se pudo completar la autenticación con Firebase.');
    }

    final firebaseIdToken = await firebaseUser.getIdToken(true);
    if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
      throw Exception('Firebase no devolvió un ID token válido.');
    }

    return firebaseIdToken;
  }

  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
    } catch (_) {
      // No impedimos cerrar la sesión local si Firebase falla.
    }

    try {
      await _initialize();
      await _googleSignIn.signOut();
    } catch (_) {
      // Tampoco impedimos cerrar la sesión local.
    }
  }
}
