import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/food_pack.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'pack_detail_page.dart';

class MapPage extends StatefulWidget {
  final int userId;

  const MapPage({
    super.key,
    required this.userId,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();

  static const LatLng _defaultCenter = LatLng(-2.1340, -79.5939);

  // ---- Datos ----
  List<FoodPack> _allPacks = [];
  List<FoodPack> _visiblePacks = [];
  FoodPack? _selectedPack;
  LatLng? _userLocation;

  // ---- Estado de filtros ----
  String _searchQuery = '';
  String? _selectedCategory;
  String _sortBy = 'distance';
  double? _maxDistanceKm;

  // ---- Estado de UI ----
  bool _isLoading = true;
  bool _isLocating = false;
  String? _errorMessage;
  String? _locationMessage;

  final TextEditingController _searchController = TextEditingController();

  // ---- Helpers de categoría ----
  static const Map<String, IconData> _categoryIcons = {
    'Panadería': Icons.bakery_dining,
    'Cafetería': Icons.local_cafe,
    'Comida': Icons.restaurant,
    'Pizza': Icons.local_pizza,
    'Postres': Icons.cake,
  };

  static const Map<String, Color> _categoryColors = {
    'Panadería': Color(0xFFF59E0B), // ámbar
    'Cafetería': Color(0xFF8B5CF6), // violeta
    'Comida': Color(0xFFEF4444),    // rojo
    'Pizza': Color(0xFFF97316),     // naranja
    'Postres': Color(0xFFEC4899),   // rosa
  };

  IconData _iconForCategory(String category) {
    return _categoryIcons[category] ?? Icons.storefront;
  }

  Color _colorForCategory(String category) {
    return _categoryColors[category] ?? const Color(0xFF0F766E);
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadPacks();
    await _locateUser();
  }

  // ==========================================
  // CARGA DE DATOS
  // ==========================================

  Future<void> _loadPacks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final packs = await _apiService.getPacks();

      if (!mounted) return;

      setState(() {
        _allPacks = packs.where((p) => p.location != null).toList();
        _isLoading = false;
      });

      if (_userLocation != null) {
        _recalculateDistances(_userLocation!);
      }

      _applyFilters();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _locateUser({bool moveCamera = true}) async {
    setState(() {
      _isLocating = true;
      _locationMessage = null;
    });

    final location = await _locationService.getCurrentLocation();

    if (!mounted) return;

    if (location == null) {
      setState(() {
        _isLocating = false;
        _locationMessage =
            'No pudimos obtener tu ubicación. Activa el GPS.';
      });
      return;
    }

    setState(() {
      _userLocation = location;
      _isLocating = false;
    });

    _recalculateDistances(location);
    _applyFilters();

    if (moveCamera) {
      _mapController.move(location, 14);
    }
  }

  void _recalculateDistances(LatLng userLocation) {
    _allPacks = _allPacks.map((pack) {
      if (pack.location == null) return pack;

      final km = _locationService.distanceInKm(
        userLocation,
        pack.location!,
      );

      return pack.copyWithDistance(
        _locationService.formatDistance(km),
      );
    }).toList();
  }

  // ==========================================
  // FILTROS Y ORDEN
  // ==========================================

  List<String> get _availableCategories {
    final set = <String>{};
    for (final p in _allPacks) {
      set.add(p.category);
    }
    return set.toList()..sort();
  }

  void _applyFilters() {
    var result = List<FoodPack>.from(_allPacks);

    // Búsqueda
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((p) {
        return p.title.toLowerCase().contains(query) ||
            p.business.toLowerCase().contains(query);
      }).toList();
    }

    // Categoría
    if (_selectedCategory != null) {
      result = result
          .where((p) => p.category == _selectedCategory)
          .toList();
    }

    // Distancia máxima
    if (_maxDistanceKm != null && _userLocation != null) {
      result = result.where((p) {
        if (p.location == null) return false;
        final km = _locationService.distanceInKm(
          _userLocation!,
          p.location!,
        );
        return km <= _maxDistanceKm!;
      }).toList();
    }

    // Orden
    switch (_sortBy) {
      case 'distance':
        if (_userLocation != null) {
          result.sort((a, b) {
            if (a.location == null) return 1;
            if (b.location == null) return -1;
            final kmA = _locationService.distanceInKm(
              _userLocation!,
              a.location!,
            );
            final kmB = _locationService.distanceInKm(
              _userLocation!,
              b.location!,
            );
            return kmA.compareTo(kmB);
          });
        }
        break;
      case 'price_asc':
        result.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'price_desc':
        result.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'newest':
        result.sort((a, b) {
          final aDate = a.createdAt ?? DateTime(2000);
          final bDate = b.createdAt ?? DateTime(2000);
          return bDate.compareTo(aDate);
        });
        break;
    }

    setState(() {
      _visiblePacks = result;
    });
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _selectedCategory = null;
      _maxDistanceKm = null;
      _sortBy = 'distance';
    });
    _applyFilters();
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _selectedCategory != null ||
      _maxDistanceKm != null;

  // ==========================================
  // ACCIONES
  // ==========================================

  void _onMarkerTap(FoodPack pack) {
    setState(() {
      _selectedPack = pack;
    });

    if (pack.location != null) {
      _mapController.move(pack.location!, 15);
    }
  }

  void _openPackDetail(FoodPack pack) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PackDetailPage(
          pack: pack,
          userId: widget.userId,
          onReserved: (_) {
            _loadPacks();
          },
        ),
      ),
    );
  }

  Future<void> _openDirections(FoodPack pack) async {
    if (pack.location == null) return;

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${pack.location!.latitude},${pack.location!.longitude}'
      '&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos abrir Google Maps'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos abrir Google Maps'),
        ),
      );
    }
  }

  // ==========================================
  // BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Mapa',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          if (_hasActiveFilters)
            IconButton(
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Limpiar filtros',
            ),
          IconButton(
            onPressed: _loadPacks,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 20),
              const Text(
                'No pudimos cargar el mapa',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loadPacks,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // ---- MAPA ----
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: 13,
            minZoom: 5,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.vectora.rescate',
            ),

            // Pin del usuario
            if (_userLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _userLocation!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),

            // Clustering de packs
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 60,
                size: const Size(48, 48),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(50),
                markers: _visiblePacks.map((pack) {
                  final isSelected = _selectedPack?.id == pack.id;
                  final color = _colorForCategory(pack.category);
                  final icon = _iconForCategory(pack.category);

                  return Marker(
                    point: pack.location!,
                    width: 60,
                    height: 60,
                    child: GestureDetector(
                      onTap: () => _onMarkerTap(pack),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected ? color : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          icon,
                          color: isSelected ? Colors.white : color,
                          size: 24,
                        ),
                      ),
                    ),
                  );
                }).toList(),
                builder: (context, markers) {
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        markers.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        // ---- Contador clickeable ----
        Positioned(
          top: 16,
          left: 16,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _visiblePacks.isEmpty ? null : _showPacksList,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.place,
                      size: 16,
                      color: Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_visiblePacks.length} ${_visiblePacks.length == 1 ? "pack" : "packs"}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_up,
                      size: 18,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ---- Botón "mi ubicación" ----
        Positioned(
          right: 16,
          bottom: _selectedPack != null ? 180 : 30,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0F766E),
            elevation: 4,
            onPressed: _isLocating ? null : () => _locateUser(),
            child: _isLocating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.my_location),
          ),
        ),

        // ---- Mensaje de ubicación ----
        if (_locationMessage != null && _selectedPack == null)
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _locationMessage!,
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _locationMessage = null;
                      });
                    },
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ---- Sin packs ----
        if (_visiblePacks.isEmpty && _selectedPack == null)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F3F0),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _hasActiveFilters
                          ? Icons.filter_alt_off
                          : Icons.inventory_2_outlined,
                      color: const Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _hasActiveFilters
                          ? 'No hay packs que coincidan con tus filtros.'
                          : 'No hay packs con ubicación disponible ahora.',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  if (_hasActiveFilters)
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Limpiar'),
                    ),
                ],
              ),
            ),
          ),

        // ---- Tarjeta del pack seleccionado ----
        if (_selectedPack != null)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: _buildPackCard(_selectedPack!),
          ),
      ],
    );
  }

  // ==========================================
  // TARJETA DEL PACK SELECCIONADO
  // ==========================================

  Widget _buildPackCard(FoodPack pack) {
    final color = _colorForCategory(pack.category);
    final icon = _iconForCategory(pack.category);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 8,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openPackDetail(pack),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          icon,
                          size: 34,
                          color: color,
                        ),
                      ),
                      if (pack.isNew)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'NUEVO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                pack.business,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                pack.category,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pack.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              '\$${pack.price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (pack.distance != '--') ...[
                              const Icon(
                                Icons.near_me,
                                size: 12,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                pack.distance,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else
                              Text(
                                pack.remaining,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedPack = null;
                      });
                    },
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Botón "Cómo llegar"
              SizedBox(
                width: double.infinity,
                height: 42,
                child: FilledButton.icon(
                  onPressed: () => _openDirections(pack),
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text(
                    'Cómo llegar',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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

  // ==========================================
  // BOTTOM SHEET PRO
  // ==========================================

  void _showPacksList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF7F8F6),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Título
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.place,
                              color: Color(0xFF0F766E),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_visiblePacks.length} ${_visiblePacks.length == 1 ? "pack" : "packs"}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_hasActiveFilters)
                              TextButton(
                                onPressed: () {
                                  _clearFilters();
                                  setSheetState(() {});
                                },
                                child: const Text('Limpiar'),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Buscador
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            _searchQuery = value;
                            _applyFilters();
                            setSheetState(() {});
                          },
                          decoration: InputDecoration(
                            hintText: 'Buscar pack o negocio...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _searchQuery = '';
                                      _applyFilters();
                                      setSheetState(() {});
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Chips de categoría
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                          ),
                          children: [
                            _buildCategoryChip(
                              'Todos',
                              null,
                              setSheetState,
                            ),
                            ..._availableCategories.map((cat) {
                              return _buildCategoryChip(
                                cat,
                                cat,
                                setSheetState,
                              );
                            }),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Filtros de orden
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                          ),
                          children: [
                            _buildSortChip(
                              'Cercanos',
                              'distance',
                              Icons.near_me,
                              setSheetState,
                            ),
                            _buildSortChip(
                              'Nuevos',
                              'newest',
                              Icons.fiber_new,
                              setSheetState,
                            ),
                            _buildSortChip(
                              'Precio ↑',
                              'price_asc',
                              Icons.arrow_upward,
                              setSheetState,
                            ),
                            _buildSortChip(
                              'Precio ↓',
                              'price_desc',
                              Icons.arrow_downward,
                              setSheetState,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Lista
                      Expanded(
                        child: _visiblePacks.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(30),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.search_off,
                                        size: 64,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No hay packs que coincidan',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Prueba con otros filtros o términos de búsqueda.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  30,
                                ),
                                itemCount: _visiblePacks.length,
                                itemBuilder: (context, index) {
                                  final pack = _visiblePacks[index];

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 12,
                                    ),
                                    child: _buildListPackCard(pack),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryChip(
    String label,
    String? category,
    StateSetter setSheetState,
  ) {
    final isSelected = _selectedCategory == category;
    final color = category == null
        ? const Color(0xFF0F766E)
        : _colorForCategory(category);
    final icon = category == null
        ? Icons.apps
        : _iconForCategory(category);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 16,
          color: isSelected ? Colors.white : color,
        ),
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        backgroundColor: Colors.white,
        selectedColor: color,
        onSelected: (_) {
          _selectedCategory = category;
          _applyFilters();
          setSheetState(() {});
        },
      ),
    );
  }

  Widget _buildSortChip(
    String label,
    String value,
    IconData icon,
    StateSetter setSheetState,
  ) {
    final isSelected = _sortBy == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 16,
          color: isSelected
              ? Colors.white
              : const Color(0xFF0F766E),
        ),
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF0F766E),
        onSelected: (_) {
          _sortBy = value;
          _applyFilters();
          setSheetState(() {});
        },
      ),
    );
  }

  Widget _buildListPackCard(FoodPack pack) {
    final color = _colorForCategory(pack.category);
    final icon = _iconForCategory(pack.category);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.pop(context);
          _onMarkerTap(pack);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      size: 30,
                      color: color,
                    ),
                  ),
                  if (pack.isNew)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'NUEVO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.business,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      pack.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '\$${pack.price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        if (pack.distance != '--') ...[
                          const SizedBox(width: 10),
                          Icon(
                            Icons.near_me,
                            size: 11,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            pack.distance,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pack.category,
                            style: TextStyle(
                              fontSize: 9,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}