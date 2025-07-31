import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _showPassword = true;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final url = Uri.parse('https://api.aurora2.vibracom.eu/tui/login');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user': _userController.text,
        'password': _passwordController.text,
      }),
    );
    setState(() {
      _isLoading = false;
    });

      print('=== RESPUESTA COMPLETA DEL LOGIN ===');
      print(response.body);
      print('===================================');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      switch (data['status']) {
        case 0:
          if (data['agentrole'] == 'police') {
            // Guarda el token
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('token', data['token']);
            await prefs.setString('userName', data['name']);

            // Login correcto y rol permitido
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => MyHomePage(
                  title: 'TUI',
                  token: data['token'],
                  userName: data['name'],
                ),
              ),
            );
          } else {
            _showError('Acceso denegado. Solo los agentes de policía pueden entrar.');
          }
          break;
        case 1:
          _showError('Faltan datos. Por favor, completa todos los campos.');
          break;
        case 2:
          _showError('Usuario o contraseña incorrectos.');
          break;
        case 3:
          _showError('Error interno del servidor. Inténtalo más tarde.');
          break;
        default:
          _showError(data['message'] ?? 'Error desconocido');
      }
    } else {
      if (response.statusCode == 401) {
        _showError('No autorizado. Verifica tu usuario y contraseña.');
      } else if (response.statusCode == 500) {
        _showError('Error interno del servidor. Inténtalo más tarde.');
      } else {
        _showError('Error de red: [${response.statusCode}]');
      }
    }
  }

  void _showError(String message) {
    setState(() {
      _error = message;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_error!),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          action: SnackBarAction(
            label: 'Cerrar',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade800, Colors.blue.shade500],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 100,
                    child: Image.asset('assets/icon/logo.png'),
                  ),
                  const SizedBox(height: 24),

                  //Nombre de la aplicación
                  const Text(
                    'TUI',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 48),

                  //Tarjeta de login
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Iniciar sesión',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),

                            //Campo de usuario
                            TextFormField(
                              controller: _userController,
                              decoration: InputDecoration(
                                labelText: 'Usuario',
                                hintText: 'Ingrese su usuario',
                                prefixIcon: Icon(Icons.person),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide(color: Colors.blue.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide(color: Colors.blue.shade800, width: 2),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Porfavor, ingrese su usuario';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            //Campo de contraseña
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _showPassword,
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                hintText: 'Ingrese su contraseña',
                                prefixIcon: Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _showPassword ? Icons.visibility : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showPassword = !_showPassword;
                                    });
                                  },
                                  tooltip: _showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide(color: Colors.blue.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide(color: Colors.blue.shade800, width: 2),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Porfavor, ingrese su contraseña';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),

                             ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Iniciar Sesión',
                                      style: TextStyle(fontSize: 16),
                                    ),
                            ),
                          ],
                        ),
                      ),
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
