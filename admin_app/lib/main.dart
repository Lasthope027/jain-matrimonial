import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth_client.dart';
import 'login_screen.dart';

const apiUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
void main() => runApp(const MatrimonialApp());

class MatrimonialApp extends StatelessWidget {
  const MatrimonialApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Jain Consultancy Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF7C303C),
        ),
        home: LoginScreen(client: AuthClient(apiUrl, administrator: true)),
      );
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, this.client});
  final http.Client? client;
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  String status = 'Check your connection to the consultancy.';
  bool busy = false;
  Future<void> check() async {
    setState(() {
      busy = true;
      status = 'Connecting…';
    });
    var message = 'Unable to connect. Please try again.';
    try {
      final response =
          await (widget.client?.get(Uri.parse('$apiUrl/api/v1/ready')) ??
                  http.get(Uri.parse('$apiUrl/api/v1/ready')))
              .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 &&
          jsonDecode(response.body)['status'] == 'ready') {
        message = 'Connected to the consultancy.';
      } else {
        message =
            'The consultancy service is not ready. Please try again later.';
      }
    } catch (_) {
      /* Display a safe, actionable connection message. */
    }
    if (mounted)
      setState(() {
        busy = false;
        status = message;
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Jain Consultancy Admin')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_outline, size: 48),
                  const SizedBox(height: 24),
                  Text(
                    'Consultancy administration',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your family’s matrimonial journey, managed with care.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text(status, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : check,
                    child: Text(busy ? 'Connecting…' : 'Check connection'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
