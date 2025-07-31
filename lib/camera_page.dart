import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'login_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({Key? key}) : super(key: key);

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  String? _detectedPlate;
  bool _processing = false;
  bool _flashOn = false;
  final TextEditingController _manualPlateController = TextEditingController();
  bool _showManualInput = false;
  List<String> _imageUrls = []; // Ahora es una lista

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;
    _controller = CameraController(
      firstCamera,
      ResolutionPreset.high,
    );
    _initializeControllerFuture = _controller!.initialize();
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _sendPlateAndShowInfo(String plate) async {
    setState(() {
      _processing = true;
      _imageUrls = [];
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        setState(() {
          _detectedPlate = 'Token no encontrado. Inicia sesión de nuevo.';
          _processing = false;
        });
        return;
      }

      final url = Uri.parse('https://api.aurora2.vibracom.eu/tui/getPlateInfo');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'plate': plate}),
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        // Token inválido o expirado
        await prefs.remove('token');
        await prefs.remove('userName');
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }

      final data = jsonDecode(response.body);
      setState(() {
        _detectedPlate = data['message'] ?? 'Sin mensaje';
        _imageUrls = (data['image'] is List)
            ? List<String>.from(data['image'])
            : [];
        _processing = false;
      });
    } catch (e) {
      setState(() {
        _detectedPlate = 'Error al consultar la matrícula: $e';
        _processing = false;
      });
    }
  }

  Future<void> _captureAndDetect() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _processing = true;
      _detectedPlate = null;
    });
    try {
      final XFile file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      img.Image? original = img.decodeImage(bytes);
      if (original == null) throw Exception('No se pudo decodificar la imagen');

      // Calcula la región del recuadro central (300x100)
      final int cropWidth = 300;
      final int cropHeight = 100;
      final int centerX = original.width ~/ 2;
      final int centerY = original.height ~/ 2;
      final int left = (centerX - cropWidth ~/ 2).clamp(0, original.width - cropWidth);
      final int top = (centerY - cropHeight ~/ 2).clamp(0, original.height - cropHeight);

      img.Image cropped = img.copyCrop(
        original,
        x: left,
        y: top,
        width: cropWidth,
        height: cropHeight,
      );

      // Guarda la imagen recortada temporalmente
      final tempDir = Directory.systemTemp;
      final croppedFile = await File('${tempDir.path}/cropped_plate.jpg').writeAsBytes(img.encodeJpg(cropped));

      // Ahora usa la imagen recortada para el OCR
      final inputImage = InputImage.fromFilePath(croppedFile.path);
      final textRecognizer = TextRecognizer();
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      // Busca la primera "matrícula" (España, España antigua, Portugal, Portugal antigua)
      String? plate;
      final List<RegExp> plateRegexes = [
        // España actual: 1234ABC
        RegExp(r'\b\d{4}[A-Z]{3}\b', caseSensitive: false),
        // España antigua: B-1234-AB, M-1234-AB, etc.
        RegExp(r'\b[A-Z]{1,2}-\d{4}-[A-Z]{1,2}\b', caseSensitive: false),
        // Portugal actual y antigua: 00-AA-00, AA-00-00, 00-00-AA
        RegExp(r'\b\d{2}-[A-Z]{2}-\d{2}\b', caseSensitive: false),
        RegExp(r'\b[A-Z]{2}-\d{2}-\d{2}\b', caseSensitive: false),
        RegExp(r'\b\d{2}-\d{2}-[A-Z]{2}\b', caseSensitive: false),
      ];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final text = line.text.replaceAll(' ', '');
          for (final regExp in plateRegexes) {
            final match = regExp.firstMatch(text);
            if (match != null) {
              plate = match.group(0);
              break;
            }
          }
          if (plate != null) break;
        }
        if (plate != null) break;
      }
      if (plate != null) {
        await _sendPlateAndShowInfo(plate);
      } else {
        setState(() {
          _detectedPlate = 'No se detectó ninguna matrícula.';
          _processing = false;
        });
      }
    } catch (e) {
      setState(() {
        _detectedPlate = 'Error al procesar la imagen: $e';
        _processing = false;
      });
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    _flashOn = !_flashOn;
    await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || _initializeControllerFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      // Elimino la AppBar con logout
      body: Stack(
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return SizedBox.expand(
                  child: CameraPreview(_controller!),
                );
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
          // Overlay de recuadro guía
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 300,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 4),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
          if (_detectedPlate != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 100,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _detectedPlate!,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    if (_imageUrls.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: _imageUrls.map((url) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: Image.network(
                                url,
                                height: 80,
                                fit: BoxFit.contain,
                              ),
                            )).toList(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Campo de matrícula manual (solo si _showManualInput)
          if (_showManualInput)
            Positioned(
              left: 0,
              right: 0,
              bottom: 110,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualPlateController,
                        decoration: InputDecoration(
                          hintText: 'Escribe la matrícula',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        autofocus: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _processing
                          ? null
                          : () {
                              final plate = _manualPlateController.text.trim().replaceAll(' ', '');
                              if (plate.isNotEmpty) {
                                _sendPlateAndShowInfo(plate);
                                setState(() {
                                  _showManualInput = false;
                                  _manualPlateController.clear();
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Icon(Icons.search),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cerrar',
                      onPressed: () {
                        setState(() {
                          _showManualInput = false;
                          _manualPlateController.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          // Botones flotantes
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Botón mostrar campo manual (izquierda del logout)
                FloatingActionButton(
                  heroTag: 'showManualInputBtn',
                  onPressed: () {
                    setState(() {
                      _showManualInput = !_showManualInput;
                    });
                  },
                  backgroundColor: Colors.green.shade700,
                  child: const Icon(Icons.edit, color: Colors.white),
                ),
                const SizedBox(width: 16),
                // Botón de cerrar sesión (izquierda)
                FloatingActionButton(
                  heroTag: 'logoutBtn',
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('token');
                    await prefs.remove('userName');
                    if (mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const LoginPage()),
                        (route) => false,
                      );
                    }
                  },
                  backgroundColor: Colors.red.shade700,
                  child: const Icon(Icons.logout, color: Colors.white),
                ),
                const SizedBox(width: 32),
                // Botón de cámara (centro)
                FloatingActionButton(
                  onPressed: _processing ? null : _captureAndDetect,
                  backgroundColor: Colors.blue.shade800,
                  child: _processing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.camera_alt),
                ),
                const SizedBox(width: 32),
                // Botón de flash (derecha)
                FloatingActionButton(
                  heroTag: 'flashBtn',
                  onPressed: _toggleFlash,
                  backgroundColor: _flashOn ? Colors.yellow.shade700 : Colors.grey.shade800,
                  child: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 