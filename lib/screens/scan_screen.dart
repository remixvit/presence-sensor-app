import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_service.dart';
import 'device_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ble = BleService();
  final _devices = <String, ScanResult>{};
  StreamSubscription? _scanSub;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> _startScan() async {
    setState(() {
      _devices.clear();
      _isScanning = true;
    });

    _scanSub?.cancel();
    _scanSub = _ble.scan().listen((result) {
      setState(() {
        _devices[result.device.remoteId.str] = result;
      });
    });

    // Автоостановка через 10 секунд
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    await _ble.stopScan();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeviceScreen(device: device)),
    );
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _ble.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Presence Sensor', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Кнопка сканирования
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: _isScanning
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.bluetooth_searching),
                label: Text(_isScanning ? 'Поиск...' : 'Найти устройства'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F3460),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // Список найденных устройств
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sensors, size: 64, color: Colors.white24),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning ? 'Ищем устройства...' : 'Нажмите "Найти устройства"',
                          style: const TextStyle(color: Colors.white38),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _devices.length,
                    itemBuilder: (ctx, i) {
                      final result = _devices.values.elementAt(i);
                      final device = result.device;
                      final name = device.platformName.isNotEmpty
                          ? device.platformName
                          : 'Sensor-${device.remoteId.str.replaceAll(':', '').substring(6)}';
                      final rssi = result.rssi;

                      return Card(
                        color: const Color(0xFF16213E),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F3460),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.sensors, color: Colors.lightBlueAccent),
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            device.remoteId.str,
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RssiIcon(rssi: rssi),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, color: Colors.white24),
                            ],
                          ),
                          onTap: () => _connectTo(device),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RssiIcon extends StatelessWidget {
  final int rssi;
  const _RssiIcon({required this.rssi});

  @override
  Widget build(BuildContext context) {
    final color = rssi > -60
        ? Colors.greenAccent
        : rssi > -80
            ? Colors.orangeAccent
            : Colors.redAccent;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.signal_cellular_alt, color: color, size: 20),
        Text('$rssi', style: TextStyle(color: color, fontSize: 10)),
      ],
    );
  }
}
