/// Модель типа устройства — определяет какие поля показывать в UI
class DeviceCapabilities {
  final bool hasVl53;      // датчик расстояния VL53L1X
  final bool hasLd2410;    // радар LD2410
  final bool hasActivator; // логика активатора (двери)

  const DeviceCapabilities({
    this.hasVl53 = true,
    this.hasLd2410 = true,
    this.hasActivator = true,
  });

  factory DeviceCapabilities.fromJson(Map<String, dynamic> json) {
    final caps = json['caps'] as List<dynamic>? ?? [];
    return DeviceCapabilities(
      hasVl53: caps.contains('vl53'),
      hasLd2410: caps.contains('ld2410'),
      hasActivator: caps.contains('activator'),
    );
  }
}

/// Текущий статус сенсора (приходит по BLE NOTIFY)
class SensorStatus {
  final bool presence;
  final bool activator;
  final bool safety;
  final int dist;
  final String dir;       // approaching / leaving / stationary
  final String wifiStatus;
  final String mqttStatus;
  final int heap;
  final int heapMin;
  final int uptime;       // секунды
  final String model;     // "presence-c3-v1"
  final String fw;        // "1.1.0"
  final DeviceCapabilities caps;

  const SensorStatus({
    this.presence = false,
    this.activator = false,
    this.safety = false,
    this.dist = 0,
    this.dir = 'stationary',
    this.wifiStatus = '',
    this.mqttStatus = '',
    this.heap = 0,
    this.heapMin = 0,
    this.uptime = 0,
    this.model = '',
    this.fw = '',
    this.caps = const DeviceCapabilities(),
  });

  factory SensorStatus.fromJson(Map<String, dynamic> json) {
    return SensorStatus(
      presence: json['presence'] == true,
      activator: json['activator'] == 'on',
      safety: json['safety'] == true,
      dist: (json['dist'] as num?)?.toInt() ?? 0,
      dir: json['dir'] as String? ?? 'stationary',
      wifiStatus: json['wifi'] as String? ?? '',
      mqttStatus: json['mqtt'] as String? ?? '',
      heap: (json['heap'] as num?)?.toInt() ?? 0,
      heapMin: (json['heap_min'] as num?)?.toInt() ?? 0,
      uptime: (json['uptime'] as num?)?.toInt() ?? 0,
      model: json['model'] as String? ?? '',
      fw: json['fw'] as String? ?? '',
      caps: DeviceCapabilities.fromJson(json),
    );
  }
}

/// Сохранённое устройство (в локальном хранилище)
class SavedDevice {
  final String id;           // remoteId из BLE
  final String name;         // кастомное имя
  final String model;
  final DateTime lastSeen;

  const SavedDevice({
    required this.id,
    required this.name,
    required this.model,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'model': model,
    'lastSeen': lastSeen.toIso8601String(),
  };

  factory SavedDevice.fromJson(Map<String, dynamic> json) => SavedDevice(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    model: json['model'] as String? ?? '',
    lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
  );
}
