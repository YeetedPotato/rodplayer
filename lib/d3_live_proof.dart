import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/platform/network/method_channel_private_network_runtime.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const D3LiveProofApp());
  if (Platform.environment['RODPLAYER_D3_STDIO'] == '1') {
    unawaited(_D3StdioController(MethodChannelPrivateNetworkRuntime()).run());
  }
}

Future<PrivateNetworkStatus> _bootstrapPrivateNetwork(
  PrivateNetworkRuntime runtime,
  String setupCode,
) async {
  final enrollmentClient = FamilyEnrollmentClient();
  try {
    final enrollment = await enrollmentClient.enroll(setupCode);
    return runtime.bootstrap(PrivateNetworkBootstrap.fromEnrollment(enrollment));
  } finally {
    enrollmentClient.close();
  }
}

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
        _setStatus(await _bootstrapPrivateNetwork(_runtime, setupCode));
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

class _D3StdioController {
  _D3StdioController(this._runtime);

  final PrivateNetworkRuntime _runtime;

  Future<void> run() async {
    final input = StreamIterator<String>(
      stdin.transform(utf8.decoder).transform(const LineSplitter()),
    );
    _writeHelp();
    while (await input.moveNext()) {
      switch (input.current.trim()) {
        case 'ping':
          await _run(() async {
            _result(await _runtime.confirmHostAvailable() ? 'available' : 'unavailable');
          });
        case 'status':
          await _run(() async => _status(await _runtime.status()));
        case 'bootstrap':
          await _bootstrap(input);
        case 'resume':
          await _run(() async => _status(await _runtime.resume()));
        case 'stop':
          await _run(() async {
            await _runtime.stop();
            _status(await _runtime.status());
          });
        case 'reset':
          await _run(() async {
            await _runtime.reset();
            _status(await _runtime.status());
          });
        case 'help':
          _writeHelp();
        case 'quit':
          exit(0);
        default:
          _result('unknown_command');
      }
    }
  }

  Future<void> _bootstrap(StreamIterator<String> input) async {
    final setupCode = await _readSetupCode(input);
    if (setupCode == null) return;
    await _run(() async => _status(await _bootstrapPrivateNetwork(_runtime, setupCode)));
  }

  Future<String?> _readSetupCode(StreamIterator<String> input) async {
    final terminal = stdin.hasTerminal;
    final previousEchoMode = terminal ? stdin.echoMode : false;
    try {
      if (terminal) stdin.echoMode = false;
      stdout.write('SETUP_CODE> ');
      if (!await input.moveNext()) return null;
      return input.current.trim();
    } finally {
      if (terminal) stdin.echoMode = previousEchoMode;
      stdout.writeln();
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } on FamilyEnrollmentException catch (error) {
      stdout.writeln('ERROR family=${error.failure.name}');
    } on PrivateNetworkException catch (error) {
      stdout.writeln('ERROR private=${error.failure.name}');
    } catch (error) {
      stdout.writeln('ERROR unknown=${error.runtimeType}');
    }
  }

  void _status(PrivateNetworkStatus status) {
    _result('completed');
    stdout.writeln('STATUS state=${status.state.name}');
    stdout.writeln('STATUS path=${status.path.name}');
    stdout.writeln('STATUS hasPersistedIdentity=${status.hasPersistedIdentity}');
    stdout.writeln('STATUS unavailableReason=${status.unavailableReason.name}');
    stdout.writeln('STATUS gatewayBaseUrl=${status.gatewayBaseUrl}');
  }

  void _result(String value) => stdout.writeln('RESULT $value');

  void _writeHelp() => stdout.writeln(
        'COMMANDS ping status bootstrap resume stop reset help quit',
      );
}
