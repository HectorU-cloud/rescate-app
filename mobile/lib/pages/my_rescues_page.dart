import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/reservation.dart';
import '../services/api_service.dart';

class MyRescuesPage extends StatefulWidget {
  final int userId;

  const MyRescuesPage({
    super.key,
    required this.userId,
  });

  @override
  State<MyRescuesPage> createState() => _MyRescuesPageState();
}

class _MyRescuesPageState extends State<MyRescuesPage> {
  final ApiService _apiService = ApiService();

  List<Reservation> _rescues = [];

  bool _isLoading = true;
  String? _errorMessage;
  int? _cancellingReservationId;

  @override
  void initState() {
    super.initState();
    _loadReservations();
  }

  Future<void> _loadReservations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final reservations = await _apiService.getReservations();

      if (!mounted) return;

      setState(() {
        _rescues = reservations;
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

  Future<void> _cancelReservation(Reservation reservation) async {
    final reservationId = reservation.reservationId;

    if (reservationId <= 0) {
      _showMessage('No se pudo identificar la reserva.');
      return;
    }

    final confirmed = await _showCancelConfirmation(reservation);

    if (!confirmed || !mounted) return;

    setState(() {
      _cancellingReservationId = reservationId;
    });

    try {
      await _apiService.cancelReservation(reservationId: reservationId);

      if (!mounted) return;

      setState(() {
        _cancellingReservationId = null;
      });

      await _loadReservations();

      if (!mounted) return;

      _showMessage('Reserva cancelada correctamente.');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _cancellingReservationId = null;
      });

      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<bool> _showCancelConfirmation(Reservation reservation) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Cancelar rescate'),
          content: Text(
            '¿Seguro que quieres cancelar '
            'tu reserva de "${reservation.pack.title}"?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Sí, cancelar'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
        ),
      );
  }

  void _showQrDialog(Reservation reservation) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Código de rescate',
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                  data: reservation.id,
                  size: 220,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Muestra este código en el negocio '
                  'al momento de retirar tu rescate.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  reservation.id,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Mis Rescates',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadReservations,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
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
            'No pudimos cargar tus rescates',
            textAlign: TextAlign.center,
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
          Center(
            child: FilledButton(
              onPressed: _loadReservations,
              child: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }

    if (_rescues.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.eco_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          const Text(
            'Todavía no tienes rescates',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Cuando reserves un pack, aparecerá aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 15,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      itemCount: _rescues.length,
      itemBuilder: (context, index) {
        final reservation = _rescues[index];
        return _buildReservationCard(reservation);
      },
    );
  }

  Widget _buildReservationCard(Reservation reservation) {
    final isReserved = reservation.status == 'Reservado';
    final reservationId = reservation.reservationId;
    final isCancelling = _cancellingReservationId == reservationId;

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
          // ---- Cabecera del pack (única) ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3F0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.restaurant_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reservation.pack.business,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reservation.pack.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _statusBadge(reservation.status),
            ],
          ),

          // ---- Badge de método de pago ----
          if (isReserved) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: reservation.isCash
                    ? Colors.orange.shade50
                    : const Color(0xFFE8F3F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: reservation.isCash
                      ? Colors.orange.shade200
                      : const Color(0xFF0F766E).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    reservation.isCash
                        ? Icons.payments_outlined
                        : Icons.check_circle_outline,
                    size: 18,
                    color: reservation.isCash
                        ? Colors.orange.shade800
                        : const Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reservation.isCash
                          ? 'Paga \$${reservation.total.toStringAsFixed(2)} en efectivo al retirar'
                          : 'Pago procesado',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: reservation.isCash
                            ? Colors.orange.shade900
                            : const Color(0xFF0F766E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          // ---- Info rows ----
          _infoRow(
            Icons.confirmation_number_outlined,
            'Código',
            reservation.id,
          ),
          const SizedBox(height: 10),
          _infoRow(
            Icons.access_time,
            'Retiro',
            reservation.pack.pickupTime,
          ),
          const SizedBox(height: 10),
          _infoRow(
            Icons.location_on_outlined,
            'Lugar',
            reservation.pack.address,
          ),
          const SizedBox(height: 10),
          _infoRow(
            Icons.shopping_bag_outlined,
            'Cantidad',
            '${reservation.quantity}',
          ),

          const Divider(height: 28),

          // ---- Desglose de precio ----
          if (reservation.serviceFee > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pack',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  '\$${reservation.subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Servicio de app',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  '\$${reservation.serviceFee.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '\$${reservation.total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ---- Botones ----
          if (isReserved) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: isCancelling
                    ? null
                    : () => _showQrDialog(reservation),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Mostrar código QR'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: isCancelling
                    ? null
                    : () => _cancelReservation(reservation),
                child: isCancelling
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Cancelar reserva'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: status == 'Reservado'
            ? const Color(0xFFE8F3F0)
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: status == 'Reservado'
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 19,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}