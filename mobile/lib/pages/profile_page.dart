import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/google_auth_service.dart';
import '../services/session_service.dart';
import 'login_page.dart';

class ProfilePage extends StatelessWidget {
  final User user;

  const ProfilePage({
    super.key,
    required this.user,
  });

  Future<void> _openUrl(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos abrir el enlace'),
        ),
      );
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final passwordController = TextEditingController();
    String? error;
    bool loading = false;

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Eliminar cuenta'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Esta acción es permanente. Borraremos tu nombre, '
                    'correo y datos de contacto, y no podrás volver a '
                    'entrar con esta cuenta.\n\n'
                    'Escribe tu contraseña para confirmar.',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    enabled: !loading,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      errorText: error,
                      errorMaxLines: 4,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                  onPressed: loading
                      ? null
                      : () async {
                          if (passwordController.text.isEmpty) {
                            setState(() {
                              error = 'Escribe tu contraseña';
                            });
                            return;
                          }

                          setState(() {
                            loading = true;
                            error = null;
                          });

                          try {
                            await ApiService()
                                .deleteAccount(passwordController.text);

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } catch (e) {
                            setState(() {
                              loading = false;
                              error = e
                                  .toString()
                                  .replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Eliminar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (deleted != true || !context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const LoginPage(),
      ),
      (route) => false,
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Cerrar sesión'),
          content: const Text(
            '¿Seguro que quieres cerrar tu sesión?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Cerrar sesión'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final sessionService = SessionService();

    await GoogleAuthService.instance.signOut();
    await sessionService.clearSession();

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const LoginPage(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor =
        Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        title: const Text(
          'Perfil',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),

          // Avatar
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F3F0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                user.isBusiness
                    ? Icons.storefront_outlined
                    : Icons.person_outline,
                size: 48,
                color: primaryColor,
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Nombre
          Text(
            user.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 6),

          // Tipo de cuenta
          Text(
            user.isBusiness
                ? 'Cuenta de negocio'
                : 'Cuenta personal',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 28),

          // Información
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _infoRow(
                  context,
                  Icons.person_outline,
                  'Nombre',
                  user.name,
                ),
                const Divider(height: 28),
                _infoRow(
                  context,
                  Icons.email_outlined,
                  'Correo',
                  user.email,
                ),
                const Divider(height: 28),
                _infoRow(
                  context,
                  user.isBusiness
                      ? Icons.storefront_outlined
                      : Icons.person_outline,
                  'Tipo de cuenta',
                  user.isBusiness
                      ? 'Negocio'
                      : 'Usuario',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Cerrar sesión
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout),
              label: const Text(
                'Cerrar sesión',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(
                  color: Colors.red.shade200,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Legales
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () =>
                    _openUrl(context, ApiService.termsUrl),
                child: const Text('Términos'),
              ),
              TextButton(
                onPressed: () =>
                    _openUrl(context, ApiService.privacyUrl),
                child: const Text('Privacidad'),
              ),
            ],
          ),

          // Eliminar cuenta
          Center(
            child: TextButton(
              onPressed: () => _deleteAccount(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
              ),
              child: const Text('Eliminar mi cuenta'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F3F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 21,
            color: Theme.of(context)
                .colorScheme
                .primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}