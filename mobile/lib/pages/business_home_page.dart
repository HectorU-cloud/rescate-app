import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import 'business_dashboard_page.dart';
import 'business_packs_page.dart';
import 'business_reservations_page.dart';
import 'business_scanner_page.dart';
import 'business_setup_page.dart';
import 'profile_page.dart';

class BusinessHomePage extends StatefulWidget {
  final User user;

  const BusinessHomePage({
    super.key,
    required this.user,
  });

  @override
  State<BusinessHomePage> createState() => _BusinessHomePageState();
}

class _BusinessHomePageState extends State<BusinessHomePage> {
  int _currentIndex = 0;

  final ApiService _apiService = ApiService();

  Map<String, dynamic>? _business;
  bool _isLoading = true;
  String? _errorMessage;

  int _unseenCount = 0;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadBusiness();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBusiness() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final business = await _apiService.getMyBusiness();

      if (!mounted) return;

      setState(() {
        _business = business;
        _isLoading = false;
      });

      // 👇 Una vez cargado el negocio, arrancamos el polling
      _startPolling();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();

    // Chequeo inmediato
    _refreshUnseenCount();

    // Luego cada 30 segundos
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshUnseenCount(),
    );
  }

  Future<void> _refreshUnseenCount() async {
    try {
      final count = await _apiService.getUnseenReservationsCount();

      if (!mounted) return;

      setState(() {
        _unseenCount = count;
      });
    } catch (_) {
      // Silencioso, no molestamos si falla el polling
    }
  }

  Future<void> _markReservationsAsSeen() async {
    try {
      await _apiService.markReservationsAsSeen();

      if (!mounted) return;

      setState(() {
        _unseenCount = 0;
      });
    } catch (_) {
      // Silencioso
    }
  }

  Future<void> _openSetup() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const BusinessSetupPage(),
      ),
    );

    if (created == true && mounted) {
      await _loadBusiness();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Negocio creado con éxito! 🎉'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
    }
  }

  String get _businessName {
    return _business?['name']?.toString() ?? 'Negocio';
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    // 👇 Cuando el negocio entra a "Reservas", marcamos todo como visto
    if (index == 2) {
      _markReservationsAsSeen();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7F8F6),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_business == null) {
      return _buildNoBusinessState();
    }

    return Scaffold(
      body: _buildCurrentPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabChanged,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Inicio',
          ),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Packs',
          ),
          NavigationDestination(
            // 👇 Badge en Reservas
            icon: Badge(
              isLabelVisible: _unseenCount > 0,
              label: Text(
                _unseenCount > 99 ? '99+' : '$_unseenCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.red.shade600,
              child: const Icon(Icons.receipt_long_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _unseenCount > 0,
              label: Text(
                _unseenCount > 99 ? '99+' : '$_unseenCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.red.shade600,
              child: const Icon(Icons.receipt_long),
            ),
            label: 'Reservas',
          ),
          const NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Escanear',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return BusinessDashboardPage(businessName: _businessName);

      case 1:
        return const BusinessPacksPage();

      case 2:
        return const BusinessReservationsPage();

      case 3:
        return const BusinessScannerPage();

      case 4:
        return ProfilePage(user: widget.user);

      default:
        return BusinessDashboardPage(businessName: _businessName);
    }
  }

  Widget _buildNoBusinessState() {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Mi negocio',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F3F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  size: 50,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Aún no tienes un negocio',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Configura tu negocio para empezar a publicar packs.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _openSetup,
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'Configurar negocio',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 72,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 20),
              const Text(
                'No pudimos cargar tu negocio',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loadBusiness,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}