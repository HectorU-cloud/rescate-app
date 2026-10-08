import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/google_auth_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import 'business_home_page.dart';
import 'home_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final ApiService _apiService = ApiService();
  final SessionService _sessionService = SessionService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isBusiness = false;
  bool _acceptedTerms = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_acceptedTerms) {
      setState(() {
        _errorMessage =
            'Debes aceptar los términos y la política de privacidad para crear tu cuenta.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final User user = await _apiService.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        isBusiness: _isBusiness,
      );

      await _sessionService.saveUser(user);

      // 👇 Sincronizar token FCM con el backend
      await NotificationService().syncTokenAfterLogin();

      if (!mounted) return;

      // 👇 Routing por rol
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => user.isBusiness
              ? BusinessHomePage(user: user)
              : HomePage(user: user),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _registerWithGoogle() async {
    if (_isLoading || _isGoogleLoading) return;

    if (!_acceptedTerms) {
      setState(() {
        _errorMessage =
            'Debes aceptar los términos y la política de privacidad para crear tu cuenta.';
      });
      return;
    }

    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });

    try {
      final firebaseIdToken =
          await GoogleAuthService.instance.signInAndGetIdToken();

      // Aqui el rol ya esta elegido con el interruptor "Soy un negocio".
      // Si la cuenta de Google ya existia, el servidor lo ignora.
      final User user = await _apiService.loginWithGoogle(
        idToken: firebaseIdToken,
        isBusiness: _isBusiness,
      );

      await _sessionService.saveUser(user);
      await NotificationService().syncTokenAfterLogin();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => user.isBusiness
              ? BusinessHomePage(user: user)
              : HomePage(user: user),
        ),
        (route) => false,
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
      appBar: AppBar(
        title: const Text('Crear cuenta'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),

                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3F0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.person_add_alt_1,
                    size: 38,
                    color: primaryColor,
                  ),
                ),

                const SizedBox(height: 22),

                const Text(
                  'Únete a Rescate',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Crea tu cuenta y empieza a rescatar alimentos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 30),

                const Text(
                  'Nombre',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Tu nombre',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa tu nombre';
                    }
                    if (value.trim().length < 2) {
                      return 'Ingresa un nombre válido';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 18),

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
                  textInputAction: TextInputAction.next,
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
                      return 'Ingresa una contraseña';
                    }
                    if (value.length < 6) {
                      return 'Usa al menos 6 caracteres';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 18),

                const Text(
                  'Confirmar contraseña',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  decoration: InputDecoration(
                    hintText: 'Repite tu contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirma tu contraseña';
                    }
                    if (value != _passwordController.text) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Soy un negocio',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Activa esta opción si vas a publicar alimentos.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isBusiness,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                                setState(() {
                                  _isBusiness = value;
                                });
                              },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                CheckboxListTile(
                  value: _acceptedTerms,
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          setState(() {
                            _acceptedTerms = value ?? false;
                            if (_acceptedTerms) _errorMessage = null;
                          });
                        },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Acepto los términos y condiciones y la política de privacidad',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(ApiService.termsUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Ver términos'),
                    ),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(ApiService.privacyUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Ver privacidad'),
                    ),
                  ],
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

                const SizedBox(height: 24),

                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed:
                        (_isLoading || _isGoogleLoading) ? null : _register,
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
                            'Crear cuenta',
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
                        'o',
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
                        : _registerWithGoogle,
                    icon: _isGoogleLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.account_circle_outlined),
                    label: Text(
                      _isGoogleLoading
                          ? 'Conectando con Google...'
                          : 'Registrarme con Google',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}