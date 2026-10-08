import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/google_auth_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import 'business_home_page.dart';
import 'forgot_password_page.dart';
import 'home_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final ApiService _apiService = ApiService();
  final SessionService _sessionService = SessionService();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final User user = await _apiService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      await _sessionService.saveUser(user);

      // 👇 Sincronizar token FCM con el backend
      await NotificationService().syncTokenAfterLogin();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => user.isBusiness
              ? BusinessHomePage(user: user)
              : HomePage(user: user),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Pregunta si la cuenta nueva es de cliente o de negocio.
  /// Devuelve true = negocio, false = cliente, null = cancelo.
  Future<bool?> _askRole() {
    Future<void> open(String url) =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('¿Cómo vas a usar Rescate?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Elige el tipo de cuenta. No podrás cambiarlo después.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, false),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('Soy cliente'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Soy un negocio'),
              ),
              const SizedBox(height: 14),
              Text(
                'Al continuar aceptas los términos y condiciones y la '
                'política de privacidad.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => open(ApiService.termsUrl),
                    child: const Text('Ver términos'),
                  ),
                  TextButton(
                    onPressed: () => open(ApiService.privacyUrl),
                    child: const Text('Ver privacidad'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loginWithGoogle() async {
    if (_isLoading || _isGoogleLoading) return;

    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });

    try {
      final firebaseIdToken =
          await GoogleAuthService.instance.signInAndGetIdToken();

      User user;

      try {
        user = await _apiService.loginWithGoogle(idToken: firebaseIdToken);
      } catch (e) {
        if (!e.toString().contains('ROLE_REQUIRED')) rethrow;

        // Cuenta nueva: se pregunta el tipo y se reutiliza el mismo token.
        final isBusiness = await _askRole();

        if (isBusiness == null) {
          await GoogleAuthService.instance.signOut();

          if (!mounted) return;

          setState(() => _isGoogleLoading = false);
          return;
        }

        user = await _apiService.loginWithGoogle(
          idToken: firebaseIdToken,
          isBusiness: isBusiness,
        );
      }

      await _sessionService.saveUser(user);
      await NotificationService().syncTokenAfterLogin();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => user.isBusiness
              ? BusinessHomePage(user: user)
              : HomePage(user: user),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isGoogleLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3F0),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      Icons.eco,
                      size: 48,
                      color: primaryColor,
                    ),
                  ),

                  const SizedBox(height: 28),

                  const Text(
                    'Bienvenido a Rescate',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Rescata comida, ahorra dinero y evita desperdicios.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(height: 34),

                  const Text(
                    'Correo electrónico',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'tu@email.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';

                      if (email.isEmpty) {
                        return 'Ingresa tu correo';
                      }

                      if (!email.contains('@')) {
                        return 'Ingresa un correo válido';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'Contraseña',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      hintText: 'Tu contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingresa tu contraseña';
                      }
                      return null;
                    },
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ForgotPasswordPage(
                                    initialEmail:
                                        _emailController.text.trim(),
                                  ),
                                ),
                              );
                            },
                      child: const Text('¿Olvidaste tu contraseña?'),
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 26),

                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Iniciar sesión',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'o continúa con',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: (_isLoading || _isGoogleLoading)
                          ? null
                          : _loginWithGoogle,
                      icon: _isGoogleLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.account_circle_outlined),
                      label: Text(
                        _isGoogleLoading
                            ? 'Conectando con Google...'
                            : 'Continuar con Google',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RegisterPage(),
                        ),
                      );
                    },
                    child: const Text(
                      '¿No tienes una cuenta? Crear cuenta',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}