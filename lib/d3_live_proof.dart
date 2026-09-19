import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/platform/network/method_channel_private_network_runtime.dart';

void main() => runApp(const D3LiveProofApp());

class D3LiveProofApp extends StatelessWidget {
  const D3LiveProofApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: D3LiveProofPage(),
      );
}

class D3LiveProofPage extends StatefulWidget {
  const D3LiveProofPage({super.key});

  @override
  State<D3LiveProofPage> createState() => _D3LiveProofPageState();
}

class _D3LiveProofPageState extends State<D3LiveProofPage> {
  final _setupCode = TextEditingController();
  final PrivateNetworkRuntime _runtime = MethodChannelPrivateNetworkRuntime();

  PrivateNetworkStatus? _status;
  String? _result;
  bool _busy = false;

  @override
  void dispose() {
    _setupCode.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await operation();
    } on FamilyEnrollmentException catch (error) {
      _setResult(error.failure.name);
    } on PrivateNetworkException catch (error) {
      _setResult(error.failure.name);
    } catch (error) {
      _setResult(error.runtimeType.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(PrivateNetworkStatus status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _result = 'completed';
    });
  }

  void _setResult(String result) {
    if (mounted) setState(() => _result = result);
  }

  Future<void> _bootstrap() => _run(() async {
        final setupCode = _setupCode.text.trim();
        _setupCode.clear();
        final enrollmentClient = FamilyEnrollmentClient();
        try {
          final enrollment = await enrollmentClient.enroll(setupCode);
          final bootstrap = PrivateNetworkBootstrap.fromEnrollment(enrollment);
          _setStatus(await _runtime.bootstrap(bootstrap));
        } finally {
          enrollmentClient.close();
        }
      });

  Future<void> _ping() => _run(() async {
        _setResult(await _runtime.confirmHostAvailable() ? 'available' : 'unavailable');
      });

  Future<void> _statusNow() => _run(() async => _setStatus(await _runtime.status()));

  Future<void> _resume() => _run(() async => _setStatus(await _runtime.resume()));

  Future<void> _stop() => _run(() async {
        await _runtime.stop();
        _setStatus(await _runtime.status());
      });

  Future<void> _reset() => _run(() async {
        await _runtime.reset();
        _setStatus(await _runtime.status());
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('RodPlayer D3 Live Proof')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _setupCode,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Family Setup code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _action('Bootstrap once', _bootstrap),
                  _action('Ping native host', _ping),
                  _action('Status', _statusNow),
                  _action('Resume', _resume),
                  _action('Stop', _stop),
                  _action('Reset', _reset),
                  OutlinedButton(
                    onPressed: _busy ? null : () => exit(0),
                    child: const Text('Quit process'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_busy) const LinearProgressIndicator(),
              if (_result != null) ...[
                const SizedBox(height: 16),
                Text('Result: $_result'),
              ],
              if (_status != null) ...[
                const SizedBox(height: 16),
                const Text('Private network status', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('state: ${_status!.state.name}'),
                Text('path: ${_status!.path.name}'),
                Text('hasPersistedIdentity: ${_status!.hasPersistedIdentity}'),
                Text('unavailableReason: ${_status!.unavailableReason.name}'),
                Text('gatewayBaseUrl: ${_status!.gatewayBaseUrl}'),
              ],
            ],
          ),
        ),
      );

  Widget _action(String label, Future<void> Function() action) => FilledButton(
        onPressed: _busy ? null : action,
        child: Text(label),
      );
}
