import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'common.dart';

/// A calculator with a basic pad and an optional scientific (advanced) mode
/// (trig, log/ln, powers, roots, π, e, factorial, parentheses). Expressions
/// are typed out and evaluated on '='.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _expr = '';
  String? _result; // shown large after '='
  bool _sci = false; // scientific (advanced) mode
  bool _deg = true; // trig in degrees (else radians)

  void _tap(String t, {bool isOp = false}) => setState(() {
        if (_result != null) {
          // After a result: operators continue from it, anything else restarts.
          _expr = isOp ? _result! + t : t;
          _result = null;
        } else {
          _expr += t;
        }
      });

  void _clear() => setState(() {
        _expr = '';
        _result = null;
      });

  void _back() => setState(() {
        _result = null;
        if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
      });

  void _equals() => setState(() {
        if (_expr.trim().isEmpty) return;
        try {
          _result = _fmt(_Calc(_deg).eval(_expr));
        } catch (_) {
          _result = 'Error';
        }
      });

  static String _fmt(double v) {
    if (v.isNaN || v.isInfinite) return 'Error';
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var s = v.toStringAsPrecision(12);
    if (s.contains('.') && !s.contains('e')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final op = scheme.primary;
    final fn = scheme.surfaceContainerHighest;
    final nm = scheme.surfaceContainerHigh;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Calculator'),
        actions: [
          IconButton(
            tooltip: _sci ? 'Basic' : 'Scientific',
            icon: Icon(_sci ? Icons.calculate_outlined : Icons.functions),
            onPressed: () => setState(() => _sci = !_sci),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              // Display — a styled "screen" showing the live expression above
              // and the result (or current entry) large below.
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_result == null ? '' : _expr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 22, color: scheme.outline)),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomRight,
                        child: Text(
                          _result ?? (_expr.isEmpty ? '0' : _expr),
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w300,
                              color: scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_sci) ...[
                _row([
                  _Btn(_deg ? 'Rad' : 'Deg', () => setState(() => _deg = !_deg),
                      color: fn, fontSize: 18),
                  _Btn('sin', () => _tap('sin('), color: fn, fontSize: 18),
                  _Btn('cos', () => _tap('cos('), color: fn, fontSize: 18),
                  _Btn('tan', () => _tap('tan('), color: fn, fontSize: 18),
                ]),
                _row([
                  _Btn('ln', () => _tap('ln('), color: fn, fontSize: 18),
                  _Btn('log', () => _tap('log('), color: fn, fontSize: 18),
                  _Btn('√', () => _tap('√('), color: fn, fontSize: 18),
                  _Btn('xʸ', () => _tap('^', isOp: true),
                      color: fn, fontSize: 18),
                ]),
                _row([
                  _Btn('x²', () => _tap('^2', isOp: true),
                      color: fn, fontSize: 18),
                  _Btn('π', () => _tap('π'), color: fn, fontSize: 18),
                  _Btn('e', () => _tap('e'), color: fn, fontSize: 18),
                  _Btn('!', () => _tap('!'), color: fn, fontSize: 18),
                ]),
              ],
              _row([
                _Btn('AC', _clear, color: fn),
                _Btn('⌫', _back, color: fn),
                _Btn('(', () => _tap('('), color: fn),
                _Btn(')', () => _tap(')'), color: fn),
              ]),
              _row([
                _Btn('7', () => _tap('7'), color: nm),
                _Btn('8', () => _tap('8'), color: nm),
                _Btn('9', () => _tap('9'), color: nm),
                _Btn('÷', () => _tap('÷', isOp: true), color: op, fg: Colors.white),
              ]),
              _row([
                _Btn('4', () => _tap('4'), color: nm),
                _Btn('5', () => _tap('5'), color: nm),
                _Btn('6', () => _tap('6'), color: nm),
                _Btn('×', () => _tap('×', isOp: true), color: op, fg: Colors.white),
              ]),
              _row([
                _Btn('1', () => _tap('1'), color: nm),
                _Btn('2', () => _tap('2'), color: nm),
                _Btn('3', () => _tap('3'), color: nm),
                _Btn('−', () => _tap('−', isOp: true), color: op, fg: Colors.white),
              ]),
              _row([
                _Btn('0', () => _tap('0'), color: nm),
                _Btn('.', () => _tap('.'), color: nm),
                _Btn('+', () => _tap('+', isOp: true), color: op, fg: Colors.white),
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
  const _Btn(this.label, this.onTap,
      {required this.color, this.fg, this.fontSize = 26});
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color? fg;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w500,
                      color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small recursive-descent evaluator for the calculator's expressions.
/// Supports + − × ÷ ^, unary minus, parentheses, factorial (!), the constants
/// π and e, and the functions sin/cos/tan/asin/acos/atan/ln/log/√(sqrt).
class _Calc {
  _Calc(this.degrees);
  final bool degrees;
  late String _s;
  late int _i;

  double eval(String s) {
    _s = s;
    _i = 0;
    final v = _expr();
    _skip();
    if (_i != _s.length) throw const FormatException('trailing');
    return v;
  }

  void _skip() {
    while (_i < _s.length && _s[_i] == ' ') {
      _i++;
    }
  }

  bool _eat(String c) {
    _skip();
    if (_i < _s.length && _s[_i] == c) {
      _i++;
      return true;
    }
    return false;
  }

  bool _word(String w) {
    _skip();
    if (_s.startsWith(w, _i)) {
      _i += w.length;
      return true;
    }
    return false;
  }

  double _expr() {
    var v = _term();
    while (true) {
      if (_eat('+')) {
        v += _term();
      } else if (_eat('−') || _eat('-')) {
        v -= _term();
      } else {
        return v;
      }
    }
  }

  double _term() {
    var v = _factor();
    while (true) {
      if (_eat('×') || _eat('*')) {
        v *= _factor();
      } else if (_eat('÷') || _eat('/')) {
        v /= _factor();
      } else {
        return v;
      }
    }
  }

  double _factor() {
    final base = _unary();
    if (_eat('^')) return math.pow(base, _factor()).toDouble();
    return base;
  }

  double _unary() {
    if (_eat('−') || _eat('-')) return -_unary();
    return _postfix();
  }

  double _postfix() {
    var v = _primary();
    while (_eat('!')) {
      v = _factorial(v);
    }
    return v;
  }

  double _primary() {
    _skip();
    if (_eat('(')) {
      final v = _expr();
      _eat(')');
      return v;
    }
    if (_word('π')) return math.pi;
    for (final f in const [
      'asin', 'acos', 'atan', 'sin', 'cos', 'tan', 'sqrt', '√', 'ln', 'log'
    ]) {
      if (_word(f)) {
        _eat('(');
        final a = _expr();
        _eat(')');
        return _func(f, a);
      }
    }
    if (_word('e')) return math.e;
    return _number();
  }

  double _number() {
    _skip();
    final start = _i;
    while (_i < _s.length &&
        (RegExp(r'[0-9.]').hasMatch(_s[_i]))) {
      _i++;
    }
    if (_i == start) throw const FormatException('number');
    return double.parse(_s.substring(start, _i));
  }

  double _func(String f, double a) {
    final r = degrees ? a * math.pi / 180 : a;
    switch (f) {
      case 'sin':
        return math.sin(r);
      case 'cos':
        return math.cos(r);
      case 'tan':
        return math.tan(r);
      case 'asin':
        return degrees ? math.asin(a) * 180 / math.pi : math.asin(a);
      case 'acos':
        return degrees ? math.acos(a) * 180 / math.pi : math.acos(a);
      case 'atan':
        return degrees ? math.atan(a) * 180 / math.pi : math.atan(a);
      case 'ln':
        return math.log(a);
      case 'log':
        return math.log(a) / math.ln10;
      case 'sqrt':
      case '√':
        return math.sqrt(a);
    }
    throw const FormatException('func');
  }

  double _factorial(double v) {
    if (v < 0 || v != v.roundToDouble() || v > 170) {
      throw const FormatException('factorial');
    }
    var r = 1.0;
    for (var k = 2; k <= v.toInt(); k++) {
      r *= k;
    }
    return r;
  }
}
