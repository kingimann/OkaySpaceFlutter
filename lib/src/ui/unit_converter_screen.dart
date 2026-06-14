import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';

/// A self-contained unit converter (length, mass, temperature, volume, speed,
/// area, data, time). No network — conversions are computed locally.
class UnitConverterScreen extends StatefulWidget {
  const UnitConverterScreen({super.key});

  @override
  State<UnitConverterScreen> createState() => _UnitConverterScreenState();
}

class _Category {
  const _Category(this.name, this.icon, this.units, {this.temperature = false});
  final String name;
  final IconData icon;
  final Map<String, double> units; // unit -> factor to the base unit
  final bool temperature;
}

const _categories = <_Category>[
  _Category('Length', Icons.straighten, {
    'Meter': 1,
    'Kilometer': 1000,
    'Centimeter': 0.01,
    'Millimeter': 0.001,
    'Mile': 1609.344,
    'Yard': 0.9144,
    'Foot': 0.3048,
    'Inch': 0.0254,
  }),
  _Category('Mass', Icons.scale, {
    'Kilogram': 1,
    'Gram': 0.001,
    'Milligram': 0.000001,
    'Tonne': 1000,
    'Pound': 0.45359237,
    'Ounce': 0.028349523,
    'Stone': 6.35029318,
  }),
  _Category('Temperature', Icons.thermostat,
      {'Celsius': 1, 'Fahrenheit': 1, 'Kelvin': 1},
      temperature: true),
  _Category('Volume', Icons.local_drink_outlined, {
    'Liter': 1,
    'Milliliter': 0.001,
    'Cubic meter': 1000,
    'Gallon (US)': 3.785411784,
    'Quart (US)': 0.946352946,
    'Pint (US)': 0.473176473,
    'Cup (US)': 0.2365882365,
    'Fluid ounce (US)': 0.0295735296,
  }),
  _Category('Speed', Icons.speed, {
    'Meter/sec': 1,
    'Kilometer/hour': 0.277777778,
    'Mile/hour': 0.44704,
    'Knot': 0.514444444,
    'Foot/sec': 0.3048,
  }),
  _Category('Area', Icons.crop_square, {
    'Square meter': 1,
    'Square kilometer': 1000000,
    'Square mile': 2589988.110336,
    'Square foot': 0.09290304,
    'Acre': 4046.8564224,
    'Hectare': 10000,
  }),
  _Category('Data', Icons.storage, {
    'Byte': 1,
    'Kilobyte': 1024,
    'Megabyte': 1048576,
    'Gigabyte': 1073741824,
    'Terabyte': 1099511627776,
    'Bit': 0.125,
  }),
  _Category('Time', Icons.schedule, {
    'Second': 1,
    'Minute': 60,
    'Hour': 3600,
    'Day': 86400,
    'Week': 604800,
  }),
];

class _UnitConverterScreenState extends State<UnitConverterScreen> {
  final _input = TextEditingController(text: '1');
  int _cat = 0;
  late String _from;
  late String _to;

  @override
  void initState() {
    super.initState();
    _resetUnits();
    _input.addListener(() => setState(() {}));
  }

  void _resetUnits() {
    final keys = _categories[_cat].units.keys.toList();
    _from = keys.first;
    _to = keys.length > 1 ? keys[1] : keys.first;
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  double _toBaseTemp(double v, String unit) {
    switch (unit) {
      case 'Fahrenheit':
        return (v - 32) * 5 / 9;
      case 'Kelvin':
        return v - 273.15;
      default:
        return v; // Celsius
    }
  }

  double _fromBaseTemp(double c, String unit) {
    switch (unit) {
      case 'Fahrenheit':
        return c * 9 / 5 + 32;
      case 'Kelvin':
        return c + 273.15;
      default:
        return c;
    }
  }

  double? get _result {
    final v = double.tryParse(_input.text.trim());
    if (v == null) return null;
    final cat = _categories[_cat];
    if (cat.temperature) {
      return _fromBaseTemp(_toBaseTemp(v, _from), _to);
    }
    return v * cat.units[_from]! / cat.units[_to]!;
  }

  String _fmt(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var s = v.toStringAsPrecision(8);
    if (s.contains('.') && !s.contains('e')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  void _swap() => setState(() {
        final t = _from;
        _from = _to;
        _to = t;
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cat = _categories[_cat];
    final units = cat.units.keys.toList();
    final result = _result;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Converter')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          // Category chips
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _categories[i];
                final sel = i == _cat;
                return ChoiceChip(
                  avatar: Icon(c.icon,
                      size: 18,
                      color: sel ? scheme.onPrimary : scheme.onSurfaceVariant),
                  label: Text(c.name),
                  selected: sel,
                  onSelected: (_) => setState(() {
                    _cat = i;
                    _resetUnits();
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _field(scheme, 'From', _from, units, true,
              (u) => setState(() => _from = u!)),
          Center(
            child: IconButton.filledTonal(
              onPressed: _swap,
              icon: const Icon(Icons.swap_vert),
              tooltip: 'Swap',
            ),
          ),
          _field(scheme, 'To', _to, units, false,
              (u) => setState(() => _to = u!),
              resultText: result == null ? '—' : _fmt(result)),
        ],
      ),
    );
  }

  Widget _field(ColorScheme scheme, String label, String unit,
      List<String> units, bool editable, ValueChanged<String?> onUnit,
      {String? resultText}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: scheme.outline, fontSize: 12)),
          Row(
            children: [
              Expanded(
                child: editable
                    ? TextField(
                        controller: _input,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.\-]')),
                        ],
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                            border: InputBorder.none, isCollapsed: true),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(resultText ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w500)),
                      ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: unit,
                underline: const SizedBox.shrink(),
                items: [
                  for (final u in units)
                    DropdownMenuItem(value: u, child: Text(u)),
                ],
                onChanged: onUnit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
