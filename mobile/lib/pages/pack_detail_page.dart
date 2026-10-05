import 'package:flutter/material.dart';
import '../models/food_pack.dart';
import '../widgets/pack_image.dart';
import 'reservation_page.dart';
import '../models/reservation.dart';

class PackDetailPage extends StatelessWidget {
  final FoodPack pack;
  final int userId;
  final Function(Reservation reservation) onReserved;

  const PackDetailPage({
    super.key,
    required this.pack,
    required this.userId,
    required this.onReserved,
  });
  @override
  Widget build(BuildContext context) {
    final savings = pack.originalPrice - pack.price;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Detalle'),
      ),

      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                20,
                10,
                20,
                30,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // Imagen
                  PackImage(
                    imageUrl: pack.imageUrl,
                    width: double.infinity,
                    height: 230,
                    borderRadius: 24,
                    iconSize: 90,
                  ),

                  const SizedBox(height: 24),

                  Text(
                    pack.business,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    pack.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        size: 20,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '4.8',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        pack.category,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Text(
                    pack.description,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 26),

                  _infoCard(
                    context,
                    Icons.access_time,
                    'Horario de retiro',
                    pack.pickupTime,
                  ),

                  const SizedBox(height: 12),

                  _infoCard(
                    context,
                    Icons.location_on_outlined,
                    'Ubicación',
                    pack.address,
                  ),

                  const SizedBox(height: 26),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3F0),
                      borderRadius:
                          BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.savings_outlined,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ahorras \$${savings.toStringAsFixed(2)} con este rescate.',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Barra inferior
          Container(
            padding: const EdgeInsets.fromLTRB(
              20,
              14,
              20,
              20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Precio',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        '\$${pack.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 20),

                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReservationPage(
                                    pack: pack,
                                    userId: userId,
                                    onReserved: onReserved,
                                  ),
                            ),
                          );
                        },
                        child: const Text(
                          'Reservar pack',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(
    BuildContext context,
    IconData icon,
    String title,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}