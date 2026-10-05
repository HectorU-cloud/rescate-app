import 'package:flutter/material.dart';

/// Foto de un pack. Si no hay foto, o falla la carga, muestra un icono.
class PackImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;
  final double iconSize;

  const PackImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.iconSize = 42,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final placeholder = Container(
      width: width,
      height: height,
      color: const Color(0xFFE8F3F0),
      child: Icon(
        Icons.bakery_dining,
        size: iconSize,
        color: primary,
      ),
    );

    final url = imageUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: (url == null || url.isEmpty)
          ? placeholder
          : Image.network(
              url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return placeholder;
              },
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
    );
  }
}
