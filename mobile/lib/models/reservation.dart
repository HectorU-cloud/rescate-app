import 'package:latlong2/latlong.dart';

import 'food_pack.dart';

class Reservation {
  final int reservationId;
  final String id;
  final FoodPack pack;
  final int quantity;
  final double total;
  final String status;
  final DateTime createdAt;
  final String customerName;

  // 👇 NUEVOS CAMPOS
  final String paymentMethod;
  final double serviceFee;
  final double amountToCollect;
  final bool feeSettled;

  const Reservation({
    required this.reservationId,
    required this.id,
    required this.pack,
    required this.quantity,
    required this.total,
    required this.status,
    required this.createdAt,
    this.customerName = 'Cliente',
    this.paymentMethod = 'online',
    this.serviceFee = 0,
    this.amountToCollect = 0,
    this.feeSettled = false,
  });

  bool get isCash => paymentMethod == 'cash';

  double get subtotal => total - serviceFee;

  factory Reservation.fromJson(Map<String, dynamic> json) {
    DateTime? parseUtc(String? value) {
        if (value == null || value.isEmpty) return null;
        final hasTz = value.endsWith('Z') ||
            value.contains('+') ||
            RegExp(r'-\d{2}:?\d{2}$').hasMatch(value);
        return DateTime.tryParse(hasTz ? value : '${value}Z');
      }

      final pickupStart = parseUtc(json['pickup_start']?.toString());
      final pickupEnd = parseUtc(json['pickup_end']?.toString());

    String formatTime(DateTime? value) {
      if (value == null) return '--:--';
      final local = value.toLocal();
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    LatLng? location;
    final lat = json['business_latitude'];
    final lng = json['business_longitude'];

    if (lat is num && lng is num) {
      location = LatLng(lat.toDouble(), lng.toDouble());
    }

    final foodPack = FoodPack(
      id: json['food_pack_id'].toString(),
      business: json['business_name']?.toString() ?? 'Negocio',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      originalPrice: (json['original_price'] as num?)?.toDouble() ?? 0,
      distance: '--',
      remaining: 'Reservado',
      category: 'Rescate',
      pickupTime:
          '${formatTime(pickupStart)} - ${formatTime(pickupEnd)}',
      address:
          json['address']?.toString() ?? 'Dirección no disponible',
      status: 'available',
      location: location,
    );

    return Reservation(
      reservationId: (json['id'] as num?)?.toInt() ?? 0,
      id: json['reservation_code']?.toString() ?? '',
      pack: foodPack,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      status: _formatStatus(json['status']?.toString() ?? ''),
      createdAt: parseUtc(json['created_at']?.toString()) ?? DateTime.now(),
      customerName:
          json['customer_name']?.toString() ?? 'Cliente',
      paymentMethod:
          json['payment_method']?.toString() ?? 'online',
      serviceFee: (json['service_fee'] as num?)?.toDouble() ?? 0,
      amountToCollect:
          (json['amount_to_collect'] as num?)?.toDouble() ?? 0,
      feeSettled: json['fee_settled'] as bool? ?? false,
    );
  }

  static String _formatStatus(String status) {
    switch (status) {
      case 'reserved':
        return 'Reservado';
      case 'cancelled':
        return 'Cancelado';
      case 'picked_up':
        return 'Completado';
      case 'expired':
        return 'Expirado';
      case 'no_show':
        return 'No retirado';
      case 'completed':
        return 'Completado';
      default:
        return status;
    }
  }
}