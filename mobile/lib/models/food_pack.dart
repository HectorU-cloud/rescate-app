import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';

class FoodPack {
  final String id;
  final String business;
  final String title;
  final String description;
  final double price;
  final double originalPrice;
  final String distance;
  final String remaining;
  final String category;
  final String pickupTime;
  final String address;
  final String status;
  final LatLng? location;
  final DateTime? createdAt;

  /// URL completa de la foto (o null si el pack no tiene foto).
  final String? imageUrl;

  const FoodPack({
    required this.id,
    required this.business,
    required this.title,
    required this.description,
    required this.price,
    required this.originalPrice,
    required this.distance,
    required this.remaining,
    required this.category,
    required this.pickupTime,
    required this.address,
    this.status = 'available',
    this.location,
    this.createdAt,
    this.imageUrl,
  });

  /// ¿Fue publicado hoy?
  bool get isNew {
    if (createdAt == null) return false;

    final local = createdAt!.toLocal();
    final now = DateTime.now();

    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  FoodPack copyWithDistance(String newDistance) {
    return FoodPack(
      id: id,
      business: business,
      title: title,
      description: description,
      price: price,
      originalPrice: originalPrice,
      distance: newDistance,
      remaining: remaining,
      category: category,
      pickupTime: pickupTime,
      address: address,
      status: status,
      location: location,
      createdAt: createdAt,
      imageUrl: imageUrl,
    );
  }

    factory FoodPack.fromJson(Map<String, dynamic> json) {
    final businessName = json['business_name']?.toString() ?? 'Negocio';
    final categoryName = json['category_name']?.toString() ?? 'General';

    // 👇 Helper para parsear fechas naive como UTC
    DateTime? parseUtc(String? value) {
      if (value == null || value.isEmpty) return null;
      final hasTz = value.endsWith('Z') ||
          value.contains('+') ||
          RegExp(r'-\d{2}:?\d{2}$').hasMatch(value);
      return DateTime.tryParse(hasTz ? value : '${value}Z');
    }

    final start = parseUtc(json['pickup_start']?.toString());
    final end = parseUtc(json['pickup_end']?.toString());
    final created = parseUtc(json['created_at']?.toString());

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

    return FoodPack(
      id: json['id'].toString(),
      business: businessName,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      originalPrice: (json['original_price'] as num?)?.toDouble() ?? 0,
      distance: '--',
      remaining: '${json['quantity'] ?? 0} disponibles',
      category: categoryName,
      pickupTime: '${formatTime(start)} - ${formatTime(end)}',
      address: json['address']?.toString() ?? 'Dirección no disponible',
      status: json['status']?.toString() ?? 'available',
      location: location,
      createdAt: created,
      imageUrl: ApiService.resolveImageUrl(
        json['image_url']?.toString(),
      ),
    );
  }
}