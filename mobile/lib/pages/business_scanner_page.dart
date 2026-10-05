import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/reservation.dart';
import '../services/api_service.dart';

class BusinessScannerPage extends StatefulWidget {
  const BusinessScannerPage({super.key});

  @override
  State<BusinessScannerPage> createState() => _BusinessScannerPageState();
}

class _BusinessScannerPageState extends State<BusinessScannerPage>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;
  bool _torchOn = false;
  Reservation? _lastValidated;
  String? _lastError;
  String? _lastScannedCode;
  bool _isAlreadyValidated = false; // 👈 nuevo

  late AnimationController _feedbackController;
  late Animation<double> _feedbackScale;

  @override
  void initState() {
    super.initState();

    _feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _feedbackScale = CurvedAnimation(
      parent: _feedbackController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;

    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue;

    if (code == null || code.isEmpty) return;

    // Evita volver a procesar el mismo código en el mismo segundo
    if (_lastScannedCode == code && _lastError == null) return;

    setState(() {
      _isProcessing = true;
      _lastScannedCode = code;
      _lastError = null;
      _lastValidated = null;
      _isAlreadyValidated = false;
    });

    await _controller.stop();

    try {
      final reservation = await _apiService.validateReservation(
        reservationCode: code,
      );

      if (!mounted) return;

      setState(() {
        _lastValidated = reservation;
        _lastError = null;
        _isAlreadyValidated = false;
        _isProcessing = false;
      });

      _feedbackController.forward(from: 0);

      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) return;

      setState(() {
        _lastValidated = null;
        _lastScannedCode = null;
      });

      _feedbackController.reset();
      await _controller.start();
    } catch (e) {
      if (!mounted) return;

      final message = e.toString().replaceFirst('Exception: ', '');

      // 👇 Detectamos si el error es "ya fue validada"
      final alreadyValidated = message
              .toLowerCase()
              .contains('ya fue validada') ||
          message.toLowerCase().contains('ya fue entregada');

      setState(() {
        _lastError = message;
        _isAlreadyValidated = alreadyValidated;
        _isProcessing = false;
      });

      _feedbackController.forward(from: 0);

      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) return;

      setState(() {
        _lastError = null;
        _isAlreadyValidated = false;
        _lastScannedCode = null;
      });

      _feedbackController.reset();
      await _controller.start();
    }
  }

  void _toggleTorch() async {
    await _controller.toggleTorch();
    setState(() {
      _torchOn = !_torchOn;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Escanear QR',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _toggleTorch,
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
          ),

          _buildScanOverlay(),

          Positioned(
            top: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Apunta al código QR del cliente',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          if (_lastValidated != null ||
              _lastError != null)
            _buildResultOverlay(),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return Center(
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF4ADE80),
            width: 4,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }

  Widget _buildResultOverlay() {
    final isSuccess = _lastValidated != null;
    final isInfo = _isAlreadyValidated;

    // 🎨 Colores según el tipo de resultado
    Color iconColor;
    IconData iconData;
    String title;

    if (isSuccess) {
      iconColor = const Color(0xFF4ADE80);
      iconData = Icons.check_rounded;
      title = '¡Reserva validada!';
    } else if (isInfo) {
      iconColor = const Color(0xFF60A5FA); // azul info
      iconData = Icons.info_outline_rounded;
      title = 'Reserva ya entregada';
    } else {
      iconColor = Colors.red.shade400;
      iconData = Icons.close_rounded;
      title = 'No se pudo validar';
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          child: ScaleTransition(
            scale: _feedbackScale,
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icono
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: iconColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      iconData,
                      size: 70,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 30),

                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Contenido
                  if (isSuccess && _lastValidated != null) ...[
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _lastValidated!.customerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_lastValidated!.quantity}x ${_lastValidated!.pack.title}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Código: ${_lastValidated!.id}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (isInfo) ...[
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _lastError ?? '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Esta reserva ya fue entregada. '
                            'Pídele al cliente que revise su historial.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (!isSuccess && !isInfo && _lastError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        _lastError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  Text(
                    isInfo
                        ? 'Listo para el siguiente escaneo...'
                        : isSuccess
                            ? 'Entregando el pack al cliente...'
                            : 'Reintentando en unos segundos...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}