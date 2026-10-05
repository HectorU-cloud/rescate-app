import 'package:flutter/material.dart';

import '../models/food_pack.dart';
import '../models/reservation.dart';
import '../services/api_service.dart';

class ReservationPage extends StatefulWidget {
  final FoodPack pack;
  final int userId;
  final Function(Reservation reservation) onReserved;

  const ReservationPage({
    super.key,
    required this.pack,
    required this.userId,
    required this.onReserved,
  });

  @override
  State<ReservationPage> createState() => _ReservationPageState();
}

class _ReservationPageState extends State<ReservationPage> {
  final ApiService _apiService = ApiService();

  // 💰 Tarifa fija de servicio
  static const double _serviceFee = 0.25;

  int quantity = 1;
  String _paymentMethod = 'cash'; // por defecto: efectivo
  bool _isLoading = false;
  String? _errorMessage;

  double get _subtotal => widget.pack.price * quantity;
  double get _total => _subtotal + _serviceFee;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        title: const Text('Reservar'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tu rescate',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ---- Info del pack ----
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.pack.business,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.pack.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Cantidad'),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed:
                                        quantity > 1 && !_isLoading
                                            ? () {
                                                setState(() {
                                                  quantity--;
                                                });
                                              }
                                            : null,
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  Text(
                                    '$quantity',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: !_isLoading
                                        ? () {
                                            setState(() {
                                              quantity++;
                                            });
                                          }
                                        : null,
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ---- Desglose ----
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          _buildRow(
                            'Pack',
                            '\$${_subtotal.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 10),
                          _buildRow(
                            'Servicio de app',
                            '\$${_serviceFee.toStringAsFixed(2)}',
                            subtitle:
                                'Ayuda a mantener la plataforma funcionando',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Divider(height: 1),
                          ),
                          _buildRow(
                            'Total a pagar',
                            '\$${_total.toStringAsFixed(2)}',
                            isBold: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ---- Selector de pago ----
                    const Text(
                      '¿Cómo quieres pagar?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildPaymentOption(
                      value: 'cash',
                      icon: Icons.payments_outlined,
                      title: 'Efectivo al recoger',
                      subtitle:
                          'Le pagas \$${_total.toStringAsFixed(2)} al negocio al retirar tu pack',
                      color: const Color(0xFF0F766E),
                    ),

                    const SizedBox(height: 10),

                    _buildPaymentOption(
                      value: 'online',
                      icon: Icons.credit_card,
                      title: 'Pagar ahora (online)',
                      subtitle: 'Pago con tarjeta - Próximamente',
                      color: Colors.grey,
                      disabled: true,
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
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
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _isLoading ? null : _confirmReservation,
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
                        'Confirmar reserva',
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
    );
  }

  Widget _buildRow(
    String label,
    String value, {
    bool isBold = false,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight:
                      isBold ? FontWeight.bold : FontWeight.normal,
                  fontSize: isBold ? 17 : 14,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 20 : 15,
            fontWeight:
                isBold ? FontWeight.bold : FontWeight.w600,
            color: isBold
                ? const Color(0xFF0F766E)
                : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentOption({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool disabled = false,
  }) {
    final isSelected = _paymentMethod == value;
    final effectiveColor =
        disabled ? Colors.grey : color;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: disabled || _isLoading
            ? null
            : () {
                setState(() {
                  _paymentMethod = value;
                });
              },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected && !disabled
                  ? effectiveColor
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: effectiveColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: disabled
                            ? Colors.grey
                            : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (disabled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Próximamente',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: effectiveColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReservation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.createReservation(
        foodPackId: int.parse(widget.pack.id),
        quantity: quantity,
        paymentMethod: _paymentMethod,
      );

      if (!mounted) return;

      final reservationCode =
          response['reservation_code']?.toString() ??
          'RES-${DateTime.now().millisecondsSinceEpoch}';

      final reservation = Reservation(
        reservationId: (response['id'] as num?)?.toInt() ?? 0,
        id: reservationCode,
        pack: widget.pack,
        quantity: quantity,
        total: (response['total'] as num?)?.toDouble() ?? _total,
        status: 'Reservado',
        createdAt: DateTime.now(),
        paymentMethod: _paymentMethod,
        serviceFee:
            (response['service_fee'] as num?)?.toDouble() ?? _serviceFee,
        amountToCollect:
            (response['amount_to_collect'] as num?)?.toDouble() ?? 0,
      );

      widget.onReserved(reservation);

      setState(() {
        _isLoading = false;
      });

      _showSuccessDialog(reservationCode);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _showSuccessDialog(String reservationCode) {
    final isCash = _paymentMethod == 'cash';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            '¡Rescate reservado! 🎉',
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isCash
                    ? 'Recuerda llevar \$${_total.toStringAsFixed(2)} en efectivo al momento de recoger.'
                    : 'Tu reserva ha sido creada correctamente.',
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3F0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Código de reserva',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      reservationCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context)
                  ..pop()
                  ..pop();
              },
              child: const Text('Ver mi rescate'),
            ),
          ],
        );
      },
    );
  }
}