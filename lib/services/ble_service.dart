import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// UUID нашего BLE сервиса и характеристик
class BleUuids {
  static const String service    = '0000181a-0000-1000-8000-00805f9b34fb';
  static const String status     = '00002a6e-0000-1000-8000-00805f9b34fb'; // NOTIFY
  static const String settings   = '00002a6f-0000-1000-8000-00805f9b34fb'; // READ
  static const String command    = '00002a70-0000-1000-8000-00805f9b34fb'; // WRITE

  /// Manufacturer data маркер для фильтрации наших устройств
  static const int manufacturerId = 0xFFFF;
  static const List<int> manufacturerMagic = [0x50, 0x53]; // 'PS'
}

/// Статус подключения
enum BleConnectionState { disconnected, scanning, connecting, connected }

class BleService {
  static final BleService _instance = BleService._();
  factory BleService() => _instance;
  BleService._();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _settingsChar;
  BluetoothCharacteristic? _commandChar;
  StreamSubscription? _statusSub;
  StreamSubscription? _stateSub;

  final _connectionStateController = StreamController<BleConnectionState>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _settingsController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<BleConnectionState> get connectionState => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get settingsStream => _settingsController.stream;

  BleConnectionState _state = BleConnectionState.disconnected;
  BleConnectionState get state => _state;

  void _setState(BleConnectionState s) {
    _state = s;
    _connectionStateController.add(s);
  }

  /// Сканирование — возвращает только наши устройства
  Stream<ScanResult> scan() {
    _setState(BleConnectionState.scanning);
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      withServices: [Guid(BleUuids.service)],
    );
    return FlutterBluePlus.scanResults.expand((results) => results).where(_isOurDevice);
  }

  bool _isOurDevice(ScanResult r) {
    // Проверяем manufacturer data если есть (после добавления в прошивку)
    final mfr = r.advertisementData.manufacturerData;
    if (mfr.containsKey(BleUuids.manufacturerId)) {
      final data = mfr[BleUuids.manufacturerId]!;
      if (data.length >= 2) {
        return data[0] == BleUuids.manufacturerMagic[0] &&
               data[1] == BleUuids.manufacturerMagic[1];
      }
    }
    // Пока маркер не добавлен в прошивку — пропускаем все устройства с нашим сервисом
    return true;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    if (_state == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    _setState(BleConnectionState.connecting);
    _device = device;

    _stateSub?.cancel();
    _stateSub = device.connectionState.listen((s) {
      // Сообщаем об отключении только если уже были подключены
      if (s == BluetoothConnectionState.disconnected &&
          _state == BleConnectionState.connected) {
        _setState(BleConnectionState.disconnected);
        _cleanup();
      }
    });

    await device.connect(timeout: const Duration(seconds: 15));
    // Запрашиваем увеличенный MTU для передачи больших JSON
    await device.requestMtu(512);
    await _discoverServices();
    _setState(BleConnectionState.connected);
    await readSettings();
  }

  Future<void> _discoverServices() async {
    final services = await _device!.discoverServices();
    for (final svc in services) {
      debugPrint('[BLE] Service: ${svc.uuid}');
      for (final char in svc.characteristics) {
        debugPrint('[BLE]   Char: ${char.uuid} props: ${char.properties}');
      }
    }
    for (final svc in services) {
      final svcUuid = svc.uuid.toString().toLowerCase();
      if (svcUuid == BleUuids.service || svcUuid == '181a') {
        for (final char in svc.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid == BleUuids.status   || uuid == '2a6e') _statusChar   = char;
          if (uuid == BleUuids.settings || uuid == '2a6f') _settingsChar = char;
          if (uuid == BleUuids.command  || uuid == '2a70') _commandChar  = char;
        }
      }
    }
    debugPrint('[BLE] status=$_statusChar settings=$_settingsChar command=$_commandChar');

    if (_statusChar != null) {
      await _statusChar!.setNotifyValue(true);
      _statusSub = _statusChar!.onValueReceived.listen((data) {
        try {
          final str = utf8.decode(data);
          debugPrint('[BLE] Status: $str');
          final json = jsonDecode(str) as Map<String, dynamic>;
          _statusController.add(json);
        } catch (e) {
          debugPrint('[BLE] Parse error: $e');
        }
      });
    }
  }

  Future<void> readSettings() async {
    if (_settingsChar == null) return;
    final data = await _settingsChar!.read();
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      _settingsController.add(json);
    } catch (_) {}
  }

  Future<void> sendCommand(Map<String, dynamic> cmd) async {
    if (_commandChar == null) return;
    final data = utf8.encode(jsonEncode(cmd));
    await _commandChar!.write(data, withoutResponse: false);
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _cleanup();
    _setState(BleConnectionState.disconnected);
  }

  void _cleanup() {
    _statusSub?.cancel();
    _statusSub = null;
    _statusChar = null;
    _settingsChar = null;
    _commandChar = null;
  }

  void dispose() {
    _stateSub?.cancel();
    _connectionStateController.close();
    _statusController.close();
    _settingsController.close();
  }
}
