import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../models/device_model.dart';
import '../widgets/radar_widget.dart';
import 'settings_screen.dart';
import 'ota_screen.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final _ble = BleService();
  SensorStatus _status = const SensorStatus();
  bool _connecting = true;
  String? _error;
  StreamSubscription? _statusSub;
  StreamSubscription? _connSub;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    _connSub = _ble.connectionState.listen((state) {
      if (state == BleConnectionState.disconnected && mounted) {
        setState(() => _error = 'Соединение потеряно');
      }
    });

    _statusSub = _ble.statusStream.listen((json) {
      if (mounted) setState(() => _status = SensorStatus.fromJson(json));
    });

    try {
      await _ble.connect(widget.device);
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) setState(() { _connecting = false; _error = e.toString(); });
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _connSub?.cancel();
    _ble.disconnect();
    super.dispose();
  }

  String _fmtUptime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}ч ${m}м';
    if (m > 0) return '${m}м ${s}с';
    return '${s}с';
  }

  String _dirLabel(String dir) {
    switch (dir) {
      case 'approaching':
      case 'приближается': return 'Приближается';
      case 'leaving':
      case 'удаляется':    return 'Удаляется';
      default:             return 'На месте';
    }
  }

  IconData _dirIcon(String dir) {
    switch (dir) {
      case 'approaching':
      case 'приближается': return Icons.arrow_downward;
      case 'leaving':
      case 'удаляется':    return Icons.arrow_upward;
      default:             return Icons.remove;
    }
  }

  Color _dirColor(String dir) {
    switch (dir) {
      case 'approaching':
      case 'приближается': return Colors.greenAccent;
      case 'leaving':
      case 'удаляется':    return Colors.orangeAccent;
      default:             return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = widget.device.platformName.isNotEmpty
        ? widget.device.platformName
        : 'Сенсор';

    if (_connecting) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.lightBlueAccent),
              const SizedBox(height: 16),
              Text('Подключение к $deviceName...', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: AppBar(backgroundColor: const Color(0xFF16213E), foregroundColor: Colors.white),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () { setState(() { _error = null; _connecting = true; }); _connect(); },
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        title: Text(deviceName),
        actions: [
          // FW версия
          if (_status.fw.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text('v${_status.fw}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ),
          // OTA обновление
          IconButton(
            icon: const Icon(Icons.system_update_outlined),
            tooltip: 'Обновление прошивки',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OtaScreen(status: _status)),
            ),
          ),
          // Настройки
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Основные статусы
            Row(children: [
              Expanded(child: _StatusCard(
                label: 'Присутствие',
                value: _status.presence ? 'Есть' : 'Нет',
                icon: Icons.person,
                active: _status.presence,
                activeColor: Colors.greenAccent,
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatusCard(
                label: 'Активатор',
                value: _status.activator ? 'ВКЛ' : 'ВЫКЛ',
                icon: Icons.toggle_on,
                active: _status.activator,
                activeColor: Colors.orangeAccent,
              )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _StatusCard(
                label: 'Безопасность',
                value: _status.safety ? 'Тревога' : 'Норма',
                icon: Icons.security,
                active: _status.safety,
                activeColor: Colors.redAccent,
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatusCard(
                label: 'Расстояние',
                value: _status.dist > 0 ? '${_status.dist} мм' : '—',
                icon: Icons.straighten,
                active: _status.dist > 0,
                activeColor: Colors.lightBlueAccent,
              )),
            ]),
            const SizedBox(height: 12),

            // Радар
            AspectRatio(
              aspectRatio: 1,
              child: RadarWidget(status: _status, maxDist: 4000),
            ),
            const SizedBox(height: 12),

            // Направление
            _DirectionCard(dir: _status.dir, label: _dirLabel(_status.dir), icon: _dirIcon(_status.dir), color: _dirColor(_status.dir)),
            const SizedBox(height: 12),

            // Системная информация
            _InfoCard(children: [
              _InfoRow(label: 'WiFi', value: _status.wifiStatus),
              _InfoRow(label: 'MQTT', value: _status.mqttStatus),
              _InfoRow(label: 'Память', value: '${_status.heap} KB (мин ${_status.heapMin} KB)'),
              _InfoRow(label: 'Аптайм', value: _fmtUptime(_status.uptime)),
              if (_status.model.isNotEmpty)
                _InfoRow(label: 'Модель', value: _status.model),
            ]),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool active;
  final Color activeColor;

  const _StatusCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.active,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? activeColor.withValues(alpha: 0.5) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: active ? activeColor : Colors.white24, size: 28),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          Text(value, style: TextStyle(
            color: active ? activeColor : Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          )),
        ],
      ),
    );
  }
}

class _DirectionCard extends StatelessWidget {
  final String dir;
  final String label;
  final IconData icon;
  final Color color;
  const _DirectionCard({required this.dir, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Направление', style: TextStyle(color: Colors.white38, fontSize: 12)),
              Text(label, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
