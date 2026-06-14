import 'package:flutter/material.dart';

import 'common.dart';

/// A simple calculator (add / subtract / multiply / divide, percent, sign).
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _display = '0';
  double? _acc; // left-hand accumulator
  String? _op; // pending operator
  bool _fresh = true; // next digit starts a new number

  double get _value => double.tryParse(_display) ?? 0;

  void _input(String d) => setState(() {
        if (_display == 'Error') _display = '0';
        if (_fresh) {
          _display = d == '.' ? '0.' : d;
          _fresh = false;
        } else if (d == '.') {
          if (!_display.contains('.')) _display += '.';
        } else if (_display == '0') {
          _display = d;
        } else if (_display.replaceAll('-', '').replaceAll('.', '').length < 12) {
          _display += d;
        }
      });

  void _setOp(String op) => setState(() {
        if (_op != null && !_fresh) {
          _compute();
        } else {
          _acc = _value;
        }
        _op = op;
        _fresh = true;
      });

  void _compute() {
    final b = _value;
    final a = _acc ?? b;
    double r;
    switch (_op) {
      case '+':
        r = a + b;
      case '−': // −
        r = a - b;
      case '×': // ×
        r = a * b;
      case '÷': // ÷
        r = b == 0 ? double.nan : a / b;
      default:
        r = b;
    }
    _acc = r;
    _display = _fmt(r);
  }

  void _equals() => setState(() {
        if (_op != null) {
          _compute();
          _op = null;
          _fresh = true;
        }
      });

  void _clear() => setState(() {
        _display = '0';
        _acc = null;
        _op = null;
        _fresh = true;
      });

  void _negate() => setState(() {
        if (_display == '0' || _display == 'Error') return;
        _display = _display.startsWith('-')
            ? _display.substring(1)
            : '-$_display';
      });

  void _percent() => setState(() {
        _display = _fmt(_value / 100);
        _fresh = true;
      });

  static String _fmt(double v) {
    if (v.isNaN || v.isInfinite) return 'Error';
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var s = v.toStringAsPrecision(12);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final op = scheme.primary;
    final fn = scheme.surfaceContainerHighest;
    final num = scheme.surfaceContainerHigh;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Calculator')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          child: Column(
            children: [
              // Display
              Expanded(
                child: Container(
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(20),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomRight,
                    child: Text(
                      _display,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 64, fontWeight: FontWeight.w300),
                    ),
                  ),
                ),
              ),
              _row([
                _Btn('AC', _clear, color: fn),
                _Btn('±', _negate, color: fn),
                _Btn('%', _percent, color: fn),
                _Btn('÷', () => _setOp('÷'),
                    color: op, fg: Colors.white),
              ]),
              _row([
                _Btn('7', () => _input('7'), color: num),
                _Btn('8', () => _input('8'), color: num),
                _Btn('9', () => _input('9'), color: num),
                _Btn('×', () => _setOp('×'),
                    color: op, fg: Colors.white),
              ]),
              _row([
                _Btn('4', () => _input('4'), color: num),
                _Btn('5', () => _input('5'), color: num),
                _Btn('6', () => _input('6'), color: num),
                _Btn('−', () => _setOp('−'),
                    color: op, fg: Colors.white),
              ]),
              _row([
                _Btn('1', () => _input('1'), color: num),
                _Btn('2', () => _input('2'), color: num),
                _Btn('3', () => _input('3'), color: num),
                _Btn('+', () => _setOp('+'), color: op, fg: Colors.white),
              ]),
              _row([
                _Btn('0', () => _input('0'), color: num, flex: 2),
                _Btn('.', () => _input('.'), color: num),
                _Btn('=', _equals, color: op, fg: Colors.white),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(List<_Btn> btns) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: btns),
        ),
      );
}

class _Btn extends StatelessWidget {
  const _Btn(this.label, this.onTap, {required this.color, this.fg, this.flex = 1});
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color? fg;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w500, color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}
