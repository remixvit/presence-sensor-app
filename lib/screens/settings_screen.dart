import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ble = BleService();
  Map<String, dynamic> _settings = {};
  bool _loading = true;
  StreamSubscription? _settingsSub;

  // Контроллеры для полей ввода
  final _controllers = <String, TextEditingController>{};

  static const _settingsMeta = [
    {'key': 'device_name',         'label': 'Имя устройства',          'type': 'text'},
    {'key': 'wifi_enabled',        'label': 'WiFi включён',            'type': 'bool'},
    {'key': 'wifi_ssid',           'label': 'WiFi SSID',               'type': 'text'},
    {'key': 'wifi_pass',           'label': 'WiFi Пароль',             'type': 'password'},
    {'key': 'mqtt_enabled',        'label': 'MQTT включён',            'type': 'bool'},
    {'key': 'mqtt_broker',         'label': 'MQTT Брокер',             'type': 'text'},
    {'key': 'mqtt_port',           'label': 'MQTT Порт',               'type': 'number'},
    {'key': 'mqtt_user',           'label': 'MQTT Пользователь',       'type': 'text'},
    {'key': 'mqtt_pass',           'label': 'MQTT Пароль',             'type': 'password'},
    {'key': 'pub_interval',        'label': 'Интервал публикации мс',  'type': 'number'},
    {'key': 'sensor_maxdist',      'label': 'Макс. дистанция мм',      'type': 'number'},
    {'key': 'vl53_threshold',      'label': 'Порог VL53 мм',           'type': 'number'},
    {'key': 'door_approach_delta', 'label': 'Дельта приближения мм',   'type': 'number'},
    {'key': 'door_open_dist',      'label': 'Расст. активации мм',     'type': 'number'},
    {'key': 'door_close_delay',    'label': 'Задержка деактивации мс', 'type': 'number'},
  ];

  @override
  void initState() {
    super.initState();
    _settingsSub = _ble.settingsStream.listen((json) {
      if (mounted) {
        setState(() {
          _settings = json;
          _loading = false;
          // Обновляем контроллеры
          for (final meta in _settingsMeta) {
            final key = meta['key'] as String;
            final type = meta['type'] as String;
            if (type != 'bool' && json.containsKey(key)) {
              _controllers.putIfAbsent(key, () => TextEditingController());
              if (_controllers[key]!.text.isEmpty) {
                _controllers[key]!.text = json[key].toString();
              }
            }
          }
        });
      }
    });
    _ble.readSettings();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _sendSetting(String key, dynamic value) async {
    await _ble.sendCommand({key: value});
  }

  Future<void> _saveSetting(String key, String type) async {
    final ctrl = _controllers[key];
    if (ctrl == null) return;
    final text = ctrl.text.trim();
    if (type == 'password' && text.isEmpty) return; // не перезатирать пустым
    dynamic value = type == 'number' ? (int.tryParse(text) ?? 0) : text;
    await _sendSetting(key, value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сохранено: $key'), duration: const Duration(seconds: 1)),
      );
    }
    await _ble.readSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        title: const Text('Настройки'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _buildSections(),
            ),
    );
  }

  List<Widget> _buildSections() {
    final sections = <String, List<Map>>{
      'Устройство': _settingsMeta.where((m) => m['key'] == 'device_name').toList(),
      'WiFi': _settingsMeta.where((m) => (m['key'] as String).startsWith('wifi')).toList(),
      'MQTT': _settingsMeta.where((m) => (m['key'] as String).startsWith('mqtt') || m['key'] == 'pub_interval').toList(),
      'Сенсор': _settingsMeta.where((m) => (m['key'] as String).startsWith('sensor') || (m['key'] as String).startsWith('vl53')).toList(),
      'Активатор': _settingsMeta.where((m) => (m['key'] as String).startsWith('door')).toList(),
    };

    final widgets = <Widget>[];
    for (final entry in sections.entries) {
      widgets.add(_SectionHeader(title: entry.key));
      for (final meta in entry.value) {
        widgets.add(_buildField(meta));
        widgets.add(const SizedBox(height: 8));
      }
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }

  Widget _buildField(Map meta) {
    final key = meta['key'] as String;
    final label = meta['label'] as String;
    final type = meta['type'] as String;

    if (type == 'bool') {
      final value = _settings[key] == true || _settings[key] == 1;
      return _SettingCard(
        child: SwitchListTile(
          title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          value: value,
          activeThumbColor: Colors.lightBlueAccent,
          activeTrackColor: Colors.lightBlueAccent.withValues(alpha: 0.4),
          onChanged: (v) {
            setState(() => _settings[key] = v);
            _sendSetting(key, v);
          },
        ),
      );
    }

    _controllers.putIfAbsent(key, () => TextEditingController(
      text: _settings[key]?.toString() ?? '',
    ));

    return _SettingCard(
      child: TextField(
        controller: _controllers[key],
        style: const TextStyle(color: Colors.white),
        obscureText: type == 'password',
        keyboardType: type == 'number' ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: const Icon(Icons.check, color: Colors.lightBlueAccent),
            onPressed: () => _saveSetting(key, type),
          ),
        ),
        onSubmitted: (_) => _saveSetting(key, type),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.lightBlueAccent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final Widget child;
  const _SettingCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}
