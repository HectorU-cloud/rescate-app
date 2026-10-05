import 'package:flutter/material.dart';

import '../models/food_pack.dart';
import '../models/reservation.dart';
import '../services/api_service.dart';
import '../widgets/food_pack_card.dart';
import 'my_rescues_page.dart';
import 'pack_detail_page.dart';
import '../models/user.dart';
import 'profile_page.dart';
import 'map_page.dart';

class HomePage extends StatefulWidget {
  final User user;

  const HomePage({
    super.key,
    required this.user,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final ApiService _apiService = ApiService();

  List<FoodPack> _packs = [];
  bool _isLoading = true;
  String? _errorMessage;

  final TextEditingController _searchController =
      TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Minusculas y sin tildes, para que "panaderia" encuentre "Panadería".
  String _normalize(String text) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    var result = text.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result.trim();
  }

  bool get _hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _selectedCategory != null;

  List<FoodPack> get _filteredPacks {
    final query = _normalize(_searchQuery);
    final category = _selectedCategory == null
        ? null
        : _normalize(_selectedCategory!);

    return _packs.where((pack) {
      if (category != null &&
          _normalize(pack.category) != category) {
        return false;
      }

      if (query.isEmpty) return true;

      final haystack = _normalize(
        '${pack.title} ${pack.business} '
        '${pack.description} ${pack.category} '
        '${pack.address}',
      );

      return query
          .split(RegExp(r'\s+'))
          .every(haystack.contains);
    }).toList();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedCategory = null;
    });
  }

  void _toggleCategory(String name) {
    setState(() {
      _selectedCategory =
          _selectedCategory == name ? null : name;
    });
  }

  Future<void> _loadPacks() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final packs = await _apiService.getPacks();

      if (!mounted) return;

      setState(() {
        _packs = packs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage =
            'No pudimos cargar los packs disponibles.';
      });
    }
  }

  Future<void> _openPack(FoodPack pack) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PackDetailPage(
          pack: pack,
          userId: widget.user.id,
          onReserved: (Reservation reservation) {
            // La reserva ya se guardó en PostgreSQL.
            // Solo actualizamos los packs cuando volvamos.
            _loadPacks();
          },
        ),
      ),
    );

    if (!mounted) return;

    // Al regresar del detalle/reserva,
    // consultamos nuevamente el stock real.
    await _loadPacks();
  }

  void _onNavigationChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Cada vez que volvemos a Inicio,
    // obtenemos nuevamente el stock real.
    if (index == 0) {
      _loadPacks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onNavigationChanged,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.confirmation_number_outlined,
            ),
            selectedIcon: Icon(
              Icons.confirmation_number,
            ),
            label: 'Mis Rescates',
          ),
          NavigationDestination(
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
        return _buildHome();

      case 1:
        return MapPage(userId: widget.user.id);
      case 2:
        return MyRescuesPage(
          userId: widget.user.id,
        );

      case 3:
        return ProfilePage(
          user: widget.user,
        );

      default:
        return _buildHome();
    }
  }

  Widget _buildHome() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadPacks,
        child: SingleChildScrollView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            30,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola 👋',
                          style: TextStyle(
                            fontSize: 15,
                            color:
                                Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '¿Qué vamos a rescatar hoy?',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.notifications_none,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // LOCATION
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 18,
                    color: Theme.of(context)
                        .colorScheme
                        .primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Guayaquil, Ecuador',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // SEARCH
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText:
                      'Buscar comida, negocios...',
                  prefixIcon:
                      const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar búsqueda',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // CATEGORIES
              const Text(
                'Categorías',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection:
                      Axis.horizontal,
                  children: [
                    _category(
                      Icons.bakery_dining,
                      'Panadería',
                    ),
                    _category(
                      Icons.local_cafe,
                      'Cafetería',
                    ),
                    _category(
                      Icons.restaurant,
                      'Comida',
                    ),
                    _category(
                      Icons.local_pizza,
                      'Pizza',
                    ),
                    _category(
                      Icons.cake,
                      'Postres',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // NEARBY
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Cerca de ti',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_hasActiveFilters)
                    TextButton(
                      onPressed: _clearFilters,
                      child:
                          const Text('Ver todos'),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // PACKS
              _buildPacksSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPacksSection() {
    if (_isLoading) {
      return const Padding(
        padding:
            EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 40,
          horizontal: 10,
        ),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration:
                    const BoxDecoration(
                  color: Color(0xFFE8F3F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_outlined,
                  size: 40,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No pudimos cargar los packs',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadPacks,
                icon:
                    const Icon(Icons.refresh),
                label:
                    const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_packs.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(
          vertical: 50,
        ),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration:
                    const BoxDecoration(
                  color: Color(0xFFE8F3F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 40,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No hay packs disponibles',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Vuelve a intentarlo más tarde.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final packs = _filteredPacks;

    if (packs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 50,
        ),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration:
                    const BoxDecoration(
                  color: Color(0xFFE8F3F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_off,
                  size: 40,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Sin resultados',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Prueba con otra palabra o categoría.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _clearFilters,
                child: const Text(
                  'Quitar filtros',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: packs.map((pack) {
        return Padding(
          padding:
              const EdgeInsets.only(
            bottom: 14,
          ),
          child: FoodPackCard(
            pack: pack,
            onTap: () => _openPack(pack),
          ),
        );
      }).toList(),
    );
  }

  Widget _category(
    IconData icon,
    String title,
  ) {
    final selected = _selectedCategory == title;

    return GestureDetector(
      onTap: () => _toggleCategory(title),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 82,
        margin:
            const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFE8F3F0),
                borderRadius:
                    BorderRadius.circular(18),
              ),
              child: Icon(
                icon,
                color: selected
                    ? Colors.white
                    : const Color(0xFF0F766E),
                size: 27,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected
                    ? FontWeight.bold
                    : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(
    IconData icon,
    String title,
    String message,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF7F8F6),
      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight:
                FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration:
                    const BoxDecoration(
                  color:
                      Color(0xFFE8F3F0),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 50,
                  color:
                      const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign:
                    TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight:
                      FontWeight.bold,
                  color:
                      Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color:
                      Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}