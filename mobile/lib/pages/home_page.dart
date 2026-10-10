import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../models/food_pack.dart';
import '../models/reservation.dart';
import '../services/api_service.dart';
import '../services/tour_service.dart';
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

  // ----- Tour de bienvenida -----
  final TourService _tourService = TourService();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _categoriesKey = GlobalKey();
  final GlobalKey _firstPackKey = GlobalKey();
  final GlobalKey _mapTabKey = GlobalKey();
  final GlobalKey _rescuesTabKey = GlobalKey();

  // true cuando ya se decidio (lo vio antes, o ya se le mostro) en esta sesion
  bool _tourChecked = false;
  bool _tourScheduling = false;
  TutorialCoachMark? _tour;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  @override
  void dispose() {
    try {
      _tour?.skip();
    } catch (_) {
      // el overlay ya no existe: nada que cerrar
    }

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

      _scheduleTourIfNeeded();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage =
            'No pudimos cargar los packs disponibles.';
      });
    }
  }

  // =================================================
  // TOUR DE BIENVENIDA (tutorial_coach_mark)
  // =================================================

  /// Si la cuenta nunca vio el tour, lo muestra cuando ya cargaron los packs.
  void _scheduleTourIfNeeded() {
    if (_tourChecked || _tourScheduling) return;

    _tourScheduling = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;

        final seen = await _tourService.hasSeen(widget.user.id);

        if (!mounted) return;

        if (seen) {
          _tourChecked = true;
          return;
        }

        // Pausa corta para que termine de pintarse la pantalla.
        await Future<void>.delayed(const Duration(milliseconds: 600));

        if (!mounted) return;

        _startTour();
      } finally {
        _tourScheduling = false;
      }
    });
  }

  /// Repite el tour a pedido (boton "Ver tutorial" en Perfil).
  Future<void> _replayTour() async {
    setState(() {
      _currentIndex = 0;
    });

    // Al volver a Inicio se recargan los packs; esperamos a que terminen
    // para que la tarjeta de ejemplo exista.
    await _loadPacks();

    if (!mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    _startTour();
  }

  void _onTourEnded() {
    _tour = null;
  }

  /// Devuelve true si el tour se mostro.
  bool _startTour() {
    if (!mounted || _currentIndex != 0) return false;

    final steps = _buildTourSteps();

    // Con menos de 2 pasos no vale la pena; se reintenta mas tarde sin
    // marcarlo como visto.
    if (steps.length < 2) return false;

    final targets = <TargetFocus>[];

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];

      targets.add(
        TargetFocus(
          identify: step.id,
          keyTarget: step.key,
          shape: ShapeLightFocus.RRect,
          radius: step.radius,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: step.align,
              child: _tourBubble(
                title: step.title,
                text: step.text,
                position: i + 1,
                total: steps.length,
              ),
            ),
          ],
        ),
      );
    }

    try {
      _tour = TutorialCoachMark(
        targets: targets,
        colorShadow: const Color(0xFF042F2E),
        opacityShadow: 0.9,
        paddingFocus: 8,
        textSkip: 'SALTAR',
        alignSkip: Alignment.topRight,
        textStyleSkip: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
        onFinish: _onTourEnded,
        onSkip: () {
          _onTourEnded();
          return true;
        },
      )..show(context: context);

      // Se marca como visto al MOSTRARLO, no al terminarlo: si alguien lo cierra
      // con el boton "atras", no reaparece solo. Puede repetirlo desde Perfil.
      _tourChecked = true;
      _tourService.markSeen(widget.user.id);

      return true;
    } catch (_) {
      // Si algun elemento no se pudo ubicar, el tour no debe romper la app.
      _tour = null;
      return false;
    }
  }

  /// Pasos del tour. Solo entran los elementos que existen y se ven de
  /// verdad en pantalla en este momento.
  List<_TourStep> _buildTourSteps() {
    final candidates = <_TourStep>[
      _TourStep(
        id: 'buscador',
        key: _searchKey,
        title: 'Busca lo que se te antoje',
        text:
            'Escribe el nombre de un pack o de un negocio y te mostramos '
            'solo lo que coincide.',
        radius: 30,
      ),
      _TourStep(
        id: 'categorias',
        key: _categoriesKey,
        title: 'Elige una categoría',
        text:
            'Toca panadería, cafetería, pizza... para filtrar. Tócala otra '
            'vez para quitar el filtro.',
        radius: 18,
      ),
      _TourStep(
        id: 'pack',
        key: _firstPackKey,
        title: 'Esto es un pack',
        text:
            'Cada pack muestra el negocio, el precio rebajado, cuántos '
            'quedan y la hora de retiro. Tócalo para ver el detalle y '
            'reservar.',
        radius: 20,
      ),
      _TourStep(
        id: 'mapa',
        key: _mapTabKey,
        title: 'Mira qué hay cerca',
        text:
            'En el mapa ves los negocios con packs disponibles y a qué '
            'distancia están de ti.',
        radius: 20,
      ),
      _TourStep(
        id: 'rescates',
        key: _rescuesTabKey,
        title: 'Tus reservas',
        text:
            'Aquí está el código QR de cada reserva, para mostrarlo en el '
            'local cuando vayas a retirar.',
        radius: 20,
      ),
    ];

    return candidates
        .where((step) => _isVisibleOnScreen(step.key))
        .map((step) => step.withAlign(_alignFor(step.key)))
        .toList();
  }

  /// true si el widget existe y esta entero dentro del area visible
  /// (sin quedar tapado por la barra inferior).
  bool _isVisibleOnScreen(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();

    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return false;
    }

    final media = MediaQuery.of(context);
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final bottom = top + renderObject.size.height;

    // La barra de navegacion mide 80 y se dibuja sobre el contenido.
    final visibleTop = media.padding.top;
    final visibleBottom = media.size.height - media.padding.bottom - 80;

    // Los elementos de la propia barra inferior siempre se consideran visibles.
    final isNavItem = key == _mapTabKey || key == _rescuesTabKey;

    if (isNavItem) return top >= visibleBottom - 1;

    return top >= visibleTop && bottom <= visibleBottom;
  }

  /// El texto va debajo del elemento si este esta en la mitad de arriba de
  /// la pantalla, y encima si esta abajo.
  ContentAlign _alignFor(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();

    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return ContentAlign.bottom;
    }

    final centerY = renderObject.localToGlobal(Offset.zero).dy +
        renderObject.size.height / 2;

    return centerY > MediaQuery.of(context).size.height / 2
        ? ContentAlign.top
        : ContentAlign.bottom;
  }

  Widget _tourBubble({
    required String title,
    required String text,
    required int position,
    required int total,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$position de $total',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          position == total
              ? 'Toca para terminar'
              : 'Toca para continuar',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
      ],
    );
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
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            key: _mapTabKey,
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            key: _rescuesTabKey,
            icon: const Icon(
              Icons.confirmation_number_outlined,
            ),
            selectedIcon: const Icon(
              Icons.confirmation_number,
            ),
            label: 'Mis Rescates',
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
          onReplayTour: _replayTour,
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
                key: _searchKey,
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
                key: _categoriesKey,
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
      children: List.generate(packs.length, (index) {
        final pack = packs[index];

        final card = FoodPackCard(
          pack: pack,
          onTap: () => _openPack(pack),
        );

        return Padding(
          padding:
              const EdgeInsets.only(
            bottom: 14,
          ),
          // La primera tarjeta lleva llave para poder senalarla en el tour.
          child: index == 0
              ? KeyedSubtree(key: _firstPackKey, child: card)
              : card,
        );
      }),
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


/// Un paso del tour de bienvenida.
class _TourStep {
  final String id;
  final GlobalKey key;
  final String title;
  final String text;
  final double radius;
  final ContentAlign align;

  const _TourStep({
    required this.id,
    required this.key,
    required this.title,
    required this.text,
    required this.radius,
    this.align = ContentAlign.bottom,
  });

  _TourStep withAlign(ContentAlign newAlign) {
    return _TourStep(
      id: id,
      key: key,
      title: title,
      text: text,
      radius: radius,
      align: newAlign,
    );
  }
}
