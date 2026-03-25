import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/ble_service.dart';
import '../models/device_model.dart';

const String _otaBaseUrl = 'https://ota.mpcbchat.ru/firmware';
const int _chunkSize = 509; // MTU 512 - 3 bytes ATT header

enum _Phase { idle, checking, upToDate, updateAvailable, downloading, flashing, done, error }

class FirmwareManifest {
  final String version;
  final String changelog;
  final String url;
  final int size;

  const FirmwareManifest({
    required this.version,
    required this.changelog,
    required this.url,
    required this.size,
  });

  factory FirmwareManifest.fromJson(Map<String, dynamic> j) => FirmwareManifest(
        version:   j['version']   as String? ?? '',
        changelog: j['changelog'] as String? ?? '',
        url:       j['url']       as String? ?? '',
        size:      j['size']      as int?    ?? 0,
      );
}

class OtaScreen extends StatefulWidget {
  final SensorStatus status;

  const OtaScreen({super.key, required this.status});

  @override
  State<OtaScreen> createState() => _OtaScreenState();
}

class _OtaScreenState extends State<OtaScreen> {
  final _ble = BleService();

  _Phase _phase = _Phase.idle;
  FirmwareManifest? _manifest;
  String _errorMsg = '';

  // Прогресс загрузки и прошивки
  int _dlBytes = 0;
  int _dlTotal = 0;
  int _otaWritten = 0;
  int _otaTotal = 0;

  List<int>? _firmware;
  StreamSubscription? _otaSub;

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  @override
  void dispose() {
    _otaSub?.cancel();
    super.dispose();
  }

  bool _isNewer(String remote, String current) {
    try {
      final r = remote.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();
      for (int i = 0; i < max(r.length, c.length); i++) {
        final rv = i < r.length ? r[i] : 0;
        final cv = i < c.length ? c[i] : 0;
        if (rv > cv) return true;
        if (rv < cv) return false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _checkUpdate() async {
    setState(() => _phase = _Phase.checking);
    try {
      final model = widget.status.model.isNotEmpty ? widget.status.model : 'presence-c3-v1';
      final url = '$_otaBaseUrl/$model/manifest.json';
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final manifest = FirmwareManifest.fromJson(
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);

      setState(() {
        _manifest = manifest;
        _phase = _isNewer(manifest.version, widget.status.fw)
            ? _Phase.updateAvailable
            : _Phase.upToDate;
      });
    } catch (e) {
      setState(() { _phase = _Phase.error; _errorMsg = e.toString(); });
    }
  }

  Future<void> _startUpdate() async {
    if (_manifest == null) return;
    if (!_ble.hasOta) {
      setState(() { _phase = _Phase.error; _errorMsg = 'OTA сервис не найден на устройстве'; });
      return;
    }

    // 1. Скачиваем прошивку
    setState(() { _phase = _Phase.downloading; _dlBytes = 0; _dlTotal = _manifest!.size; });
    try {
      final req = http.Request('GET', Uri.parse(_manifest!.url));
      final resp = await req.send().timeout(const Duration(minutes: 2));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final bytes = <int>[];
      await for (final chunk in resp.stream) {
        bytes.addAll(chunk);
        setState(() => _dlBytes = bytes.length);
      }
      _firmware = bytes;
    } catch (e) {
      setState(() { _phase = _Phase.error; _errorMsg = 'Ошибка загрузки: $e'; });
      return;
    }

    // 2. Подписываемся на статус OTA
    setState(() { _phase = _Phase.flashing; _otaWritten = 0; _otaTotal = _firmware!.length; });
    try {
      await _ble.otaSubscribeStatus();
      // Пауза: Android BLE не любит быстрые последовательные операции
      await Future.delayed(const Duration(milliseconds: 500));

      _otaSub = _ble.otaStatusStream().listen(_onOtaStatus, onError: (e) {
        setState(() { _phase = _Phase.error; _errorMsg = e.toString(); });
      });

      // 3. Отправляем START
      await Future.delayed(const Duration(milliseconds: 200));
      await _ble.sendOtaCommand({'cmd': 'start', 'size': _firmware!.length});
      // Дальше управление переходит к _onOtaStatus
    } catch (e) {
      setState(() { _phase = _Phase.error; _errorMsg = 'Ошибка BLE: $e'; });
    }
  }

  Future<void> _sendChunks() async {
    final fw = _firmware!;
    int chunkIndex = 0;
    for (int offset = 0; offset < fw.length; offset += _chunkSize) {
      if (_phase != _Phase.flashing) return; // прерывание
      final end = min(offset + _chunkSize, fw.length);
      await _ble.sendOtaChunk(fw.sublist(offset, end));
      chunkIndex++;
      // Пауза каждые 50 чанков (~25KB) чтобы не переполнить BLE буфер
      if (chunkIndex % 50 == 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
    // Пауза перед END чтобы все чанки успели дойти
    await Future.delayed(const Duration(milliseconds: 200));
    await _ble.sendOtaCommand({'cmd': 'end'});
  }

  void _onOtaStatus(Map<String, dynamic> status) {
    final state = status['state'] as String? ?? '';
    final written = status['written'] as int? ?? 0;
    final total = status['total'] as int? ?? 0;

    switch (state) {
      case 'ready':
        // ESP32 готов принимать данные
        _sendChunks();
        break;
      case 'progress':
        setState(() { _otaWritten = written; _otaTotal = total; });
        break;
      case 'done':
        _otaSub?.cancel();
        setState(() => _phase = _Phase.done);
        break;
      case 'error':
        _otaSub?.cancel();
        final msg = status['msg'] as String? ?? 'неизвестная ошибка';
        setState(() { _phase = _Phase.error; _errorMsg = 'OTA ошибка: $msg'; });
        break;
    }
  }

  Future<void> _abort() async {
    try { await _ble.sendOtaCommand({'cmd': 'abort'}); } catch (_) {}
    _otaSub?.cancel();
    setState(() => _phase = _Phase.updateAvailable);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        title: const Text('Обновление прошивки'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Версии
            _VersionRow(
              label: 'Текущая',
              version: widget.status.fw,
              model: widget.status.model,
            ),
            if (_manifest != null) ...[
              const SizedBox(height: 8),
              _VersionRow(
                label: 'На сервере',
                version: _manifest!.version,
                highlight: _phase == _Phase.updateAvailable,
              ),
            ],
            const SizedBox(height: 32),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.checking:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.lightBlueAccent),
              SizedBox(height: 16),
              Text('Проверка обновлений...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        );

      case _Phase.upToDate:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 64),
              SizedBox(height: 16),
              Text('Прошивка актуальна', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
        );

      case _Phase.updateAvailable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Доступно обновление', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_manifest!.changelog.isNotEmpty) ...[
              const Text('Что нового:', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_manifest!.changelog, style: const TextStyle(color: Colors.white70)),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Размер: ${(_manifest!.size / 1024).toStringAsFixed(0)} KB',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.system_update),
                label: const Text('Установить обновление'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlueAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _startUpdate,
              ),
            ),
          ],
        );

      case _Phase.downloading:
        final progress = _dlTotal > 0 ? _dlBytes / _dlTotal : 0.0;
        return _ProgressView(
          label: 'Загрузка прошивки...',
          sub: '${(_dlBytes / 1024).toStringAsFixed(0)} / ${(_dlTotal / 1024).toStringAsFixed(0)} KB',
          progress: progress,
          canAbort: false,
        );

      case _Phase.flashing:
        final progress = _otaTotal > 0 ? _otaWritten / _otaTotal : 0.0;
        return _ProgressView(
          label: 'Прошивка устройства...',
          sub: '${(_otaWritten / 1024).toStringAsFixed(0)} / ${(_otaTotal / 1024).toStringAsFixed(0)} KB',
          progress: progress,
          canAbort: true,
          onAbort: _abort,
        );

      case _Phase.done:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.greenAccent, size: 64),
              SizedBox(height: 16),
              Text('Обновление завершено!', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Устройство перезагружается...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        );

      case _Phase.error:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              Text(_errorMsg, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _checkUpdate,
                child: const Text('Повторить'),
              ),
            ],
          ),
        );
    }
  }
}

class _VersionRow extends StatelessWidget {
  final String label;
  final String version;
  final String? model;
  final bool highlight;

  const _VersionRow({
    required this.label,
    required this.version,
    this.model,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ),
        Text(
          'v$version',
          style: TextStyle(
            color: highlight ? Colors.lightBlueAccent : Colors.white,
            fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            fontSize: 16,
          ),
        ),
        if (model != null) ...[
          const SizedBox(width: 8),
          Text('($model)', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ],
    );
  }
}

class _ProgressView extends StatelessWidget {
  final String label;
  final String sub;
  final double progress;
  final bool canAbort;
  final VoidCallback? onAbort;

  const _ProgressView({
    required this.label,
    required this.sub,
    required this.progress,
    required this.canAbort,
    this.onAbort,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.white12,
          color: Colors.lightBlueAccent,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Text('${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        if (canAbort) ...[
          const SizedBox(height: 32),
          TextButton(
            onPressed: onAbort,
            child: const Text('Отменить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ],
    );
  }
}
