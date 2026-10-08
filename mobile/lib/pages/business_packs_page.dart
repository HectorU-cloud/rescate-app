import 'package:flutter/material.dart';

import '../models/food_pack.dart';
import '../services/api_service.dart';
import '../widgets/pack_image.dart';
import 'business_create_pack_page.dart';
import 'business_edit_pack_page.dart';

class BusinessPacksPage extends StatefulWidget {
  const BusinessPacksPage({super.key});

  @override
  State<BusinessPacksPage> createState() => _BusinessPacksPageState();
}

class _BusinessPacksPageState extends State<BusinessPacksPage> {
  final ApiService _apiService = ApiService();

  List<FoodPack> _packs = [];
  bool _isLoading = true;
  String? _errorMessage;
  int? _processingPackId;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final packs = await _apiService.getMyPacks();

      if (!mounted) return;

      setState(() {
        _packs = packs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openCreatePack() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const BusinessCreatePackPage(),
      ),
    );

    if (created == true && mounted) {
      await _loadPacks();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Pack publicado con éxito! 🎉'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
    }
  }

  Future<void> _openEditPack(FoodPack pack) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessEditPackPage(pack: pack),
      ),
    );

    if (updated == true && mounted) {
      await _loadPacks();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pack actualizado correctamente'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
    }
  }

  Future<void> _togglePause(FoodPack pack) async {
    final isPaused = pack.status == 'paused';
    final newStatus = isPaused ? 'available' : 'paused';

    setState(() {
      _processingPackId = int.parse(pack.id);
    });

    try {
      await _apiService.updatePack(
        packId: int.parse(pack.id),
        status: newStatus,
      );

      if (!mounted) return;

      await _loadPacks();

      if (!mounted) return;

      setState(() {
        _processingPackId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPaused
                ? 'Pack reactivado ✅'
                : 'Pack pausado. No aparecerá en el catálogo.',
          ),
          backgroundColor: const Color(0xFF0F766E),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _processingPackId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDelete(FoodPack pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Eliminar pack'),
          content: Text(
            '¿Seguro que quieres eliminar "${pack.title}"? '
            'Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _processingPackId = int.parse(pack.id);
    });

    try {
      await _apiService.deletePack(packId: int.parse(pack.id));

      if (!mounted) return;

      await _loadPacks();

      if (!mounted) return;

      setState(() {
        _processingPackId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pack eliminado correctamente'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _processingPackId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Mis Packs',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreatePack,
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Nuevo pack',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPacks,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.cloud_off_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 20),
          const Text(
            'No pudimos cargar tus packs',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          Center(
            child: FilledButton(
              onPressed: _loadPacks,
              child: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }

    if (_packs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.inventory_2_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          const Text(
            'Todavía no tienes packs',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Toca el botón "Nuevo pack" para publicar tu primer excedente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
      itemCount: _packs.length,
      itemBuilder: (context, index) {
        return _buildPackCard(_packs[index]);
      },
    );
  }

  Widget _buildPackCard(FoodPack pack) {
    final isAvailable = pack.status == 'available';
    final isPaused = pack.status == 'paused';
    final isProcessing = _processingPackId == int.parse(pack.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PackImage(
                imageUrl: pack.imageUrl,
                width: 58,
                height: 58,
                borderRadius: 16,
                iconSize: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.category,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pack.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Menú de opciones
              PopupMenuButton<String>(
                enabled: !isProcessing,
                icon: const Icon(Icons.more_vert),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _openEditPack(pack);
                      break;
                    case 'pause':
                    case 'resume':
                      _togglePause(pack);
                      break;
                    case 'delete':
                      _confirmDelete(pack);
                      break;
                  }
                },
                itemBuilder: (context) {
                  return [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (isAvailable)
                      const PopupMenuItem(
                        value: 'pause',
                        child: ListTile(
                          leading: Icon(Icons.pause_circle_outline),
                          title: Text('Pausar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (isPaused)
                      const PopupMenuItem(
                        value: 'resume',
                        child: ListTile(
                          leading: Icon(Icons.play_circle_outline),
                          title: Text('Reactivar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        title: Text(
                          'Eliminar',
                          style: TextStyle(color: Colors.red),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          _statusBadge(pack.status),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _infoItem(
                  Icons.attach_money,
                  'Precio',
                  '\$${pack.price.toStringAsFixed(2)}',
                ),
              ),
              Expanded(
                child: _infoItem(
                  Icons.inventory_2_outlined,
                  'Stock',
                  pack.remaining,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(Icons.access_time, 'Retiro', pack.pickupTime),

          if (isProcessing)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bgColor;
    Color textColor;
    String label;
    IconData? icon;

    switch (status) {
      case 'available':
        bgColor = const Color(0xFFE8F3F0);
        textColor = const Color(0xFF0F766E);
        label = 'Disponible';
        icon = Icons.check_circle_outline;
        break;
      case 'sold_out':
        bgColor = const Color(0xFFFFF3CD);
        textColor = const Color(0xFF856404);
        label = 'Agotado';
        icon = Icons.remove_shopping_cart_outlined;
        break;
      case 'paused':
        bgColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        label = 'Pausado';
        icon = Icons.pause_circle_outline;
        break;
      case 'expired':
        bgColor = Colors.grey.shade200;
        textColor = Colors.grey.shade700;
        label = 'Expirado';
        icon = Icons.schedule;
        break;
      default:
        bgColor = Colors.grey.shade200;
        textColor = Colors.grey.shade700;
        label = status;
        icon = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}