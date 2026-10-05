import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'pack_image.dart';

/// Selector de foto para crear/editar un pack.
///
/// No sube nada: avisa con [onChanged] cuando el usuario elige o quita una
/// foto, y la pantalla que lo usa se encarga de subirla al guardar.
class PackImagePicker extends StatefulWidget {
  /// URL de la foto que ya tiene el pack (al editar).
  final String? existingImageUrl;
  final ValueChanged<XFile?> onChanged;

  const PackImagePicker({
    super.key,
    required this.onChanged,
    this.existingImageUrl,
  });

  @override
  State<PackImagePicker> createState() => _PackImagePickerState();
}

class _PackImagePickerState extends State<PackImagePicker> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _previewBytes;
  String? _error;

  Future<void> _pick() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (file == null) return; // el usuario cerro el selector

      final bytes = await file.readAsBytes();

      if (!mounted) return;

      setState(() {
        _previewBytes = bytes;
        _error = null;
      });

      widget.onChanged(file);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No pudimos abrir tus fotos. Revisa los permisos.';
      });
    }
  }

  void _remove() {
    setState(() {
      _previewBytes = null;
      _error = null;
    });

    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final hasNew = _previewBytes != null;
    final hasExisting = (widget.existingImageUrl ?? '').isNotEmpty;

    Widget preview;

    if (hasNew) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.memory(
          _previewBytes!,
          width: double.infinity,
          height: 180,
          fit: BoxFit.cover,
        ),
      );
    } else if (hasExisting) {
      preview = PackImage(
        imageUrl: widget.existingImageUrl,
        width: double.infinity,
        height: 180,
        borderRadius: 18,
        iconSize: 60,
      );
    } else {
      preview = Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F3F0),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo_outlined,
              size: 40,
              color: Color(0xFF0F766E),
            ),
            SizedBox(height: 8),
            Text('Agregar una foto del pack'),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _pick,
          child: preview,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                (hasNew || hasExisting) ? 'Cambiar foto' : 'Elegir foto',
              ),
            ),
            if (hasNew)
              TextButton.icon(
                onPressed: _remove,
                icon: const Icon(Icons.close),
                label: const Text('Quitar'),
              ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            style: const TextStyle(color: Colors.red),
          ),
      ],
    );
  }
}
