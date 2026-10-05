import 'package:flutter/material.dart';

import '../models/food_pack.dart';
import '../services/api_service.dart';

class BusinessEditPackPage extends StatefulWidget {
  final FoodPack pack;

  const BusinessEditPackPage({
    super.key,
    required this.pack,
  });

  @override
  State<BusinessEditPackPage> createState() =>
      _BusinessEditPackPageState();
}

class _BusinessEditPackPageState extends State<BusinessEditPackPage> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _originalPriceController = TextEditingController();
  final _quantityController = TextEditingController();

  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;

  TimeOfDay _pickupStart = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _pickupEnd = const TimeOfDay(hour: 21, minute: 0);

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _categoriesError;

  @override
  void initState() {
    super.initState();
    _prefill();
    _loadCategories();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _originalPriceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _prefill() {
    _titleController.text = widget.pack.title;
    _descriptionController.text = widget.pack.description;
    _priceController.text = widget.pack.price.toStringAsFixed(2);
    _originalPriceController.text =
        widget.pack.originalPrice.toStringAsFixed(2);

    // Extraer cantidad de "X disponibles"
    final remaining = widget.pack.remaining;
    final match = RegExp(r'^(\d+)').firstMatch(remaining);
    if (match != null) {
      _quantityController.text = match.group(1) ?? '';
    } else {
      _quantityController.text = '1';
    }

    // Parsear horario de "18:00 - 21:00"
    final parts = widget.pack.pickupTime.split(' - ');
    if (parts.length == 2) {
      _pickupStart = _parseTime(parts[0]) ?? _pickupStart;
      _pickupEnd = _parseTime(parts[1]) ?? _pickupEnd;
    }
  }

  TimeOfDay? _parseTime(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _apiService.getCategories();

      if (!mounted) return;

      setState(() {
        _categories = categories;
        _isLoading = false;

        // Preseleccionar la categoría actual del pack
        for (final cat in categories) {
          if (cat['name'] == widget.pack.category) {
            _selectedCategoryId = cat['id'] as int?;
            break;
          }
        }

        // Fallback
        _selectedCategoryId ??=
            categories.isNotEmpty ? categories.first['id'] as int? : null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _categoriesError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _pickupStart : _pickupEnd,
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        _pickupStart = picked;
      } else {
        _pickupEnd = picked;
      }
    });
  }

  DateTime _combineTodayWithTime(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategoryId == null) {
      setState(() {
        _errorMessage = 'Selecciona una categoría';
      });
      return;
    }

    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final originalPrice =
        double.tryParse(_originalPriceController.text.trim()) ?? 0;
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;

    if (originalPrice < price) {
      setState(() {
        _errorMessage =
            'El precio original no puede ser menor que el precio del pack';
      });
      return;
    }

    final pickupStart = _combineTodayWithTime(_pickupStart);
    final pickupEnd = _combineTodayWithTime(_pickupEnd);

    if (pickupEnd.isBefore(pickupStart) || pickupEnd == pickupStart) {
      setState(() {
        _errorMessage = 'La hora de fin debe ser mayor que la de inicio';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _apiService.updatePack(
        packId: int.parse(widget.pack.id),
        categoryId: _selectedCategoryId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        price: price,
        originalPrice: originalPrice,
        quantity: quantity,
        pickupStart: pickupStart,
        pickupEnd: pickupEnd,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        title: const Text(
          'Editar pack',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_categoriesError != null) ...[
                        _errorBox(
                          'No pudimos cargar las categorías: $_categoriesError',
                        ),
                        const SizedBox(height: 20),
                      ],

                      _label('Título del pack *'),
                      TextFormField(
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: 'Ej: Pack sorpresa de panadería',
                          prefixIcon: Icon(Icons.local_offer_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa un título';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      _label('Descripción'),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Ej: Incluye 4 panes y 2 pastelitos',
                          prefixIcon: Icon(Icons.description_outlined),
                        ),
                      ),

                      const SizedBox(height: 18),

                      _label('Categoría *'),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedCategoryId,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: _categories
                            .map(
                              (cat) => DropdownMenuItem<int>(
                                value: cat['id'] as int,
                                child: Text(cat['name'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedCategoryId = value;
                                });
                              },
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _label('Precio *'),
                                TextFormField(
                                  controller: _priceController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    hintText: '2.50',
                                    prefixText: '\$ ',
                                  ),
                                  validator: (value) {
                                    final p = double.tryParse(
                                        value?.trim() ?? '');
                                    if (p == null || p <= 0) {
                                      return 'Inválido';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _label('Precio original *'),
                                TextFormField(
                                  controller: _originalPriceController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    hintText: '6.00',
                                    prefixText: '\$ ',
                                  ),
                                  validator: (value) {
                                    final p = double.tryParse(
                                        value?.trim() ?? '');
                                    if (p == null || p <= 0) {
                                      return 'Inválido';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      _label('Cantidad disponible *'),
                      TextFormField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: 'Ej: 5',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        validator: (value) {
                          final q = int.tryParse(value?.trim() ?? '');
                          if (q == null || q <= 0) {
                            return 'Cantidad inválida';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      _label('Horario de retiro *'),
                      Row(
                        children: [
                          Expanded(
                            child: _timeButton(
                              label: 'Desde',
                              time: _pickupStart,
                              onTap: () => _pickTime(isStart: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _timeButton(
                              label: 'Hasta',
                              time: _pickupEnd,
                              onTap: () => _pickTime(isStart: false),
                            ),
                          ),
                        ],
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 18),
                        _errorBox(_errorMessage!),
                      ],

                      const SizedBox(height: 28),

                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _isSaving ? null : _submit,
                          child: _isSaving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Guardar cambios',
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
              ),
            ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _timeButton({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(
              Icons.access_time,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
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
                  _formatTime(time),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }
}