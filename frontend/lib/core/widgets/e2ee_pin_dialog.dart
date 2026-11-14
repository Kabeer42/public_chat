import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../crypto/e2ee_manager.dart';
import '../di/injection_container.dart';
import '../theme/app_colors.dart';

enum E2eePinDialogMode { setup, restore, change }

class E2eePinDialog extends StatefulWidget {
  final E2eePinDialogMode mode;

  const E2eePinDialog({super.key, required this.mode});

  static Future<bool> show(
    BuildContext context, {
    required E2eePinDialogMode mode,
    bool barrierDismissible = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => PopScope(
        canPop: barrierDismissible,
        child: E2eePinDialog(mode: mode),
      ),
    );
    return result ?? false;
  }

  @override
  State<E2eePinDialog> createState() => _E2eePinDialogState();
}

class _E2eePinDialogState extends State<E2eePinDialog> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _errorMessage = 'Please enter a 6-digit PIN.');
      return;
    }

    if (widget.mode == E2eePinDialogMode.setup || widget.mode == E2eePinDialogMode.change) {
      final confirmPin = _confirmPinController.text.trim();
      if (pin != confirmPin) {
        setState(() => _errorMessage = 'PINs do not match.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final e2ee = sl<E2eeManager>();

    try {
      if (widget.mode == E2eePinDialogMode.restore) {
        final result = await e2ee.restoreKeyWithPin(pin);
        if (result.success) {
          if (mounted) Navigator.of(context).pop(true);
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = result.error ?? 'Incorrect PIN. Please try again.';
          });
        }
      } else {
        // Setup or Change mode
        final result = await e2ee.setupPinBackup(pin);
        if (result.success) {
          if (mounted) Navigator.of(context).pop(true);
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = result.error ?? 'Failed to save PIN backup. Please try again.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('ApiException: ', '');
      });
    }
  }

  Future<void> _handleForgotPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amberAccent),
            SizedBox(width: 8),
            Text('Reset E2EE Keys?', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
          'If you forgot your PIN, your previous messages cannot be decrypted and will not be shown.\n\n'
          'A new encryption key pair will be generated for future messages.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset Keys'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final pin = _pinController.text.trim();
      final newPin = pin.length == 6 ? pin : '123456';

      setState(() => _isLoading = true);
      final e2ee = sl<E2eeManager>();
      final result = await e2ee.resetKeysAndStartFresh(newPin);
      if (result.success) {
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result.error ?? 'Failed to reset keys. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRestore = widget.mode == E2eePinDialogMode.restore;
    final isSetup = widget.mode == E2eePinDialogMode.setup;

    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isRestore
                  ? 'Restore Messages'
                  : isSetup
                      ? 'Secure Chat Backup'
                      : 'Change 6-Digit PIN',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isRestore
                  ? 'Enter your 6-digit E2EE PIN to unlock and restore your chat messages.'
                  : 'Set a 6-digit PIN to encrypt and securely back up your private chat key.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              autofocus: true,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 22,
                letterSpacing: 10,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: '••••••',
                counterText: '',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (!isRestore) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: 10,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'Confirm PIN',
                  counterText: '',
                  prefixIcon: const Icon(Icons.lock_reset_outlined, size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            if (isRestore) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: _isLoading ? null : _handleForgotPin,
                  child: const Text(
                    'Forgot PIN? Reset Keys',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.mode == E2eePinDialogMode.change)
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _isLoading ? null : _handleSubmit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(isRestore ? 'Unlock & Restore' : 'Save PIN'),
        ),
      ],
    );
  }
}
