import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'common.dart';

/// On-device wallet lock: an optional 4-digit PIN gating the wallet section.
///
/// The PIN lives in secure storage and is checked client-side only — it's a
/// privacy shield against someone holding the phone, not account security
/// (the backend session is unaffected). Unlocking lasts until the app
/// restarts or the wallet lock is toggled.
class WalletLock {
  WalletLock._();

  static final WalletLock instance = WalletLock._();

  static const _key = 'okayspace.wallet_pin';
  static const _storage = FlutterSecureStorage();

  bool _unlocked = false;

  /// Whether a PIN is configured.
  Future<bool> get enabled async {
    try {
      final pin = await _storage.read(key: _key);
      return pin != null && pin.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Whether the wallet has been unlocked this session.
  bool get unlocked => _unlocked;

  Future<bool> verify(String pin) async {
    try {
      final stored = await _storage.read(key: _key);
      if (stored != null && stored == pin) {
        _unlocked = true;
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> setPin(String pin) async {
    await _storage.write(key: _key, value: pin);
    _unlocked = true;
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
    _unlocked = false;
  }

  /// Relocks until the next successful [verify] (e.g. after disabling).
  void relock() => _unlocked = false;

  /// Whether the device can authenticate with biometrics (never on web).
  Future<bool> get biometricsAvailable async {
    if (kIsWeb) return false;
    try {
      final auth = LocalAuthentication();
      return await auth.canCheckBiometrics || await auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Unlocks via fingerprint/Face ID. Only meaningful while a PIN is set.
  Future<bool> unlockWithBiometrics() async {
    if (kIsWeb) return false;
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock your wallet',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok) _unlocked = true;
      return ok;
    } catch (_) {
      return false; // unsupported/cancelled — the PIN pad still works
    }
  }
}

final walletLock = WalletLock.instance;

/// Full-screen PIN pad. In entry mode it verifies against the stored PIN and
/// pops `true` on success; in setup mode it asks twice and saves.
class WalletPinScreen extends StatefulWidget {
  const WalletPinScreen({super.key, this.setup = false});

  /// True to create/replace the PIN instead of verifying it.
  final bool setup;

  @override
  State<WalletPinScreen> createState() => _WalletPinScreenState();
}

class _WalletPinScreenState extends State<WalletPinScreen> {
  String _entered = '';
  String? _firstPass;
  String? _error;
  bool _biometrics = false;

  @override
  void initState() {
    super.initState();
    if (!widget.setup) {
      walletLock.biometricsAvailable.then((ok) {
        if (mounted && ok) setState(() => _biometrics = true);
      });
    }
  }

  Future<void> _tryBiometrics() async {
    if (await walletLock.unlockWithBiometrics()) {
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  String get _title => widget.setup
      ? (_firstPass == null ? 'Choose a 4-digit PIN' : 'Confirm your PIN')
      : 'Enter your wallet PIN';

  Future<void> _submit() async {
    final pin = _entered;
    setState(() => _entered = '');
    if (widget.setup) {
      if (_firstPass == null) {
        setState(() {
          _firstPass = pin;
          _error = null;
        });
        return;
      }
      if (_firstPass != pin) {
        setState(() {
          _firstPass = null;
          _error = 'PINs didn\'t match — try again';
        });
        return;
      }
      await walletLock.setPin(pin);
      if (mounted) {
        showInfo(context, 'Wallet lock enabled');
        Navigator.of(context).pop(true);
      }
      return;
    }
    if (await walletLock.verify(pin)) {
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'Wrong PIN');
    }
  }

  void _tap(String k) {
    if (k == '<') {
      if (_entered.isNotEmpty) {
        setState(
            () => _entered = _entered.substring(0, _entered.length - 1));
      }
      return;
    }
    if (_entered.length >= 4) return;
    setState(() {
      _entered += k;
      _error = null;
    });
    if (_entered.length == 4) _submit();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Wallet lock')),
      body: MaxWidth(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 44, color: scheme.primary),
            const SizedBox(height: 12),
            Text(_title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 17)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!,
                    style: TextStyle(color: scheme.error, fontSize: 13)),
              ),
            const SizedBox(height: 20),
            // PIN dots.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _entered.length ? scheme.primary : null,
                      border: Border.all(color: scheme.primary, width: 1.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            for (final row in [
              const ['1', '2', '3'],
              const ['4', '5', '6'],
              const ['7', '8', '9'],
              [_biometrics ? '@' : '', '0', '<'],
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final k in row)
                    SizedBox(
                      width: 88,
                      height: 60,
                      child: k.isEmpty
                          ? null
                          : InkWell(
                              // '@' is the biometric key on the entry pad.
                              onTap: k == '@' ? _tryBiometrics : () => _tap(k),
                              borderRadius: BorderRadius.circular(14),
                              child: Center(
                                child: k == '<'
                                    ? const Icon(Icons.backspace_outlined,
                                        size: 22)
                                    : k == '@'
                                        ? const Icon(Icons.fingerprint,
                                            size: 26)
                                        : Text(k,
                                            style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight:
                                                    FontWeight.w600)),
                              ),
                            ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
