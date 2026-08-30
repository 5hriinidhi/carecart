import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pin_lock.dart';
import '../../core/text.dart';
import '../../core/theme.dart';

/// Ask for the medications PIN before an add / delete. If none is set yet, this
/// walks the user through creating one first. Returns true only when the PIN was
/// created or correctly entered.
Future<bool> showMedPinDialog(
  BuildContext context,
  WidgetRef ref, {
  required String actionLabel, // e.g. "add this medication"
}) async {
  final lock = ref.read(pinLockProvider);
  final exists = await lock.isSet();
  if (!context.mounted) return false;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PinDialog(
      lock: lock,
      create: !exists,
      actionLabel: actionLabel,
    ),
  );
  return ok ?? false;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({
    required this.lock,
    required this.create,
    required this.actionLabel,
  });
  final PinLock lock;
  final bool create;
  final String actionLabel;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  int _tries = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _pin.text.trim();

    if (widget.create) {
      if (!isValidPin(pin)) {
        setState(() => _error = 'Pick a 4–6 digit PIN.');
        return;
      }
      if (_confirm.text.trim() != pin) {
        setState(() => _error = "Those two didn't match.");
        return;
      }
      setState(() => _busy = true);
      await widget.lock.setPin(pin);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    setState(() => _busy = true);
    final good = await widget.lock.verify(pin);
    if (!mounted) return;
    if (good) {
      Navigator.of(context).pop(true);
      return;
    }
    _tries++;
    setState(() {
      _busy = false;
      _pin.clear();
      _error = _tries >= 3
          ? 'Too many wrong tries.'
          : 'Wrong PIN. Try again.';
    });
    if (_tries >= 3 && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final digits = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ];

    return AlertDialog(
      backgroundColor: Cc.paper,
      title: Text(widget.create ? 'Set a medications PIN' : 'Enter your PIN',
          style: CcText.h3),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.create
                ? 'A short PIN protects your medicine list. You’ll enter it '
                    'whenever you add or remove one.'
                : 'Enter your PIN to ${widget.actionLabel}.',
            style: CcText.bodySm.copyWith(color: Cc.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('pin-field'),
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(
              labelText: widget.create ? 'New PIN' : 'PIN',
              counterText: '',
            ),
            onSubmitted: (_) => widget.create ? null : _submit(),
          ),
          if (widget.create) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('pin-confirm-field'),
              controller: _confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: const InputDecoration(
                  labelText: 'Confirm PIN', counterText: ''),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                key: const Key('pin-error'),
                style: CcText.bodySm.copyWith(color: Cc.avoid)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('pin-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(widget.create ? 'Save PIN' : 'Confirm'),
        ),
      ],
    );
  }
}
