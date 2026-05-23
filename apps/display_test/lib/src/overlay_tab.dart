import 'package:flutter/material.dart';
import 'platform.dart';

class OverlayTab extends StatefulWidget {
  const OverlayTab({super.key});
  @override
  State<OverlayTab> createState() => _OverlayTabState();
}

class _OverlayTabState extends State<OverlayTab> {
  int _width = 200;
  int _height = 200;
  int _x = 100;
  int _y = 300;
  double _alpha = 1.0;
  int _color = 0xFFFF0000; // ARGB red
  bool _touchable = false;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final has = await Platform.hasOverlayPermission();
    if (mounted) setState(() => _hasPermission = has);
  }

  Future<void> _requestPermission() async {
    await Platform.requestOverlayPermission();
    // user กลับมาจาก Settings → check อีกครั้ง
    Future.delayed(const Duration(seconds: 1), _checkPermission);
  }

  Future<void> _show() async {
    if (!_hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ต้องอนุญาต overlay ก่อน')),
      );
      return;
    }
    await Platform.showOverlay(
      width: _width,
      height: _height,
      x: _x,
      y: _y,
      alpha: _alpha,
      color: _color,
      touchable: _touchable,
    );
  }

  Future<void> _hide() => Platform.hideOverlay();

  void _applyPreset(String name) {
    setState(() {
      switch (name) {
        case '1x1':
          _width = 1;
          _height = 1;
          _alpha = 0.01;
          _x = 0;
          _y = 0;
          _color = 0xFFFF0000;
          _touchable = false;
          break;
        case 'fullscreen50':
          _width = 1080;
          _height = 2340;
          _alpha = 0.5;
          _x = 0;
          _y = 0;
          _color = 0xFF00FF00;
          _touchable = false;
          break;
        case 'corner_badge':
          _width = 100;
          _height = 100;
          _alpha = 1.0;
          _x = 950;
          _y = 50;
          _color = 0xFFFFFF00;
          _touchable = false;
          break;
      }
    });
    _show();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: _hasPermission ? Colors.green.shade50 : Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  _hasPermission ? Icons.check_circle : Icons.warning,
                  color: _hasPermission ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hasPermission ? 'มีสิทธิ์ Overlay แล้ว' : 'ยังไม่มีสิทธิ์ — ต้องอนุญาต',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (!_hasPermission)
                  TextButton(
                    onPressed: _requestPermission,
                    child: const Text('ขอสิทธิ์'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        _section('Presets (เทคนิคที่น่าสนใจ)'),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _applyPreset('1x1'),
              child: const Text('1×1 ซ้อน (AirDroid)'),
            ),
            OutlinedButton(
              onPressed: () => _applyPreset('fullscreen50'),
              child: const Text('Fullscreen 50%'),
            ),
            OutlinedButton(
              onPressed: () => _applyPreset('corner_badge'),
              child: const Text('Corner badge'),
            ),
          ],
        ),

        _section('Size'),
        _slider('Width', _width.toDouble(), 1, 1080, (v) => setState(() => _width = v.toInt())),
        _slider('Height', _height.toDouble(), 1, 2340, (v) => setState(() => _height = v.toInt())),

        _section('Position'),
        _slider('X', _x.toDouble(), 0, 1080, (v) => setState(() => _x = v.toInt())),
        _slider('Y', _y.toDouble(), 0, 2340, (v) => setState(() => _y = v.toInt())),

        _section('Transparency'),
        _slider(
          'Alpha',
          _alpha,
          0.0,
          1.0,
          (v) => setState(() => _alpha = double.parse(v.toStringAsFixed(2))),
          divisions: 100,
        ),

        _section('Color'),
        Wrap(
          spacing: 6,
          children: [
            _colorChip(0xFFFF0000, 'Red'),
            _colorChip(0xFF00FF00, 'Green'),
            _colorChip(0xFF0000FF, 'Blue'),
            _colorChip(0xFFFFFF00, 'Yellow'),
            _colorChip(0xFFFFFFFF, 'White'),
            _colorChip(0xFF000000, 'Black'),
            _colorChip(0x00000000, 'Transparent'),
          ],
        ),

        const SizedBox(height: 8),
        SwitchListTile(
          value: _touchable,
          onChanged: (v) => setState(() => _touchable = v),
          title: const Text('Touchable (ดูดทุก touch)'),
          subtitle: const Text(
            'OFF = touch ทะลุผ่าน, ON = overlay กิน touch (ระวังกดออกไม่ได้)',
          ),
          contentPadding: EdgeInsets.zero,
        ),

        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _show,
                icon: const Icon(Icons.visibility),
                label: const Text('Show / Update'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _hide,
                icon: const Icon(Icons.visibility_off),
                label: const Text('Hide'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ค่าปัจจุบัน', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Size: ${_width} × ${_height} px'),
                Text('Position: ($_x, $_y)'),
                Text('Alpha: ${(_alpha * 100).toStringAsFixed(0)}%'),
                Text('Color: 0x${_color.toRadixString(16).toUpperCase().padLeft(8, '0')}'),
                Text('Touchable: ${_touchable ? "ON" : "OFF"}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
  }) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(value < 10 ? 2 : 0),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 60, child: Text(value.toStringAsFixed(value < 10 ? 2 : 0))),
      ],
    );
  }

  Widget _colorChip(int color, String name) {
    final selected = _color == color;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Color(color),
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(name),
        ],
      ),
      selected: selected,
      onSelected: (_) => setState(() => _color = color),
    );
  }
}
