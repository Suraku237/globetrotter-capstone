import 'dart:ui';

import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_background.dart';

class RegisterScreen extends StatefulWidget {
  final SessionState session;
  final VoidCallback onSignedIn;

  const RegisterScreen({
    super.key,
    required this.session,
    required this.onSignedIn,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _codeController = TextEditingController();
  String _role = 'user';
  bool _loading = false;
  bool _googleLoading = false;
  bool _verifying = false;
  String? _error;
  // Non-null once registration succeeds — switches the screen from the
  // form to either a code-entry step or an admin-pending message,
  // depending on .status. Registering no longer signs you in directly.
  RegistrationResult? _pendingRegistration;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.session.register(
        _email.text.trim(),
        _password.text,
        _name.text.trim(),
        role: _role,
      );
      if (mounted) setState(() => _pendingRegistration = result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Registration failed with a non-API error: $e');
      setState(
        () => _error = AppLocalizations.of(context)!.couldNotReachServer,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await widget.session.verifyEmail(
          _pendingRegistration!.email, _codeController.text.trim());
      if (mounted) widget.onSignedIn();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(
        () => _error = AppLocalizations.of(context)!.couldNotReachServer,
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await widget.session.signInWithGoogle();
      if (mounted) widget.onSignedIn();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = AppLocalizations.of(context)!.googleSignInFailed);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.canopy,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Stack(
        children: [
          const Positioned.fill(child: AuthBackground()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Card(
                      color: AppColors.sand.withValues(alpha: 0.35),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: _pendingRegistration == null
                            ? _buildForm(l10n)
                            : _pendingRegistration!.status ==
                                    'pending_verification'
                                ? _buildVerifyCode(l10n)
                                : _buildAdminPending(l10n),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.createYourAccount,
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.registerSubtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(
              labelText: l10n.fullNameLabel,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l10n.requiredField : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _email,
            decoration: InputDecoration(labelText: l10n.emailLabel),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v == null || !v.contains('@'))
                ? l10n.emailValidatorError
                : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: InputDecoration(labelText: l10n.roleLabel),
            items: [
              DropdownMenuItem(value: 'user', child: Text(l10n.roleUser)),
              DropdownMenuItem(value: 'worker', child: Text(l10n.roleWorker)),
              DropdownMenuItem(value: 'admin', child: Text(l10n.roleAdmin)),
            ],
            onChanged: (value) => setState(() => _role = value ?? 'user'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            decoration: InputDecoration(
              labelText: l10n.passwordLabel,
            ),
            obscureText: true,
            validator: (v) => (v == null || v.length < 6)
                ? l10n.passwordValidatorError
                : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.clay),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(l10n.createAccount),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: AppColors.inkSoft.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                ),
                child: Text(
                  l10n.or,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: Divider(
                  color: AppColors.inkSoft.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _googleLoading ? null : _submitGoogle,
              icon: _googleLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.g_mobiledata_rounded, size: 26),
              label: Text(l10n.continueWithGoogle),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.alreadyHaveAccount),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyCode(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.verifyEmailTitle,
            style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 4),
        Text(
          l10n.verifyEmailSubtitle(_pendingRegistration!.email),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: AppColors.clay)),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _codeController,
          decoration: InputDecoration(labelText: l10n.verificationCodeLabel),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _verifying ? null : _verifyCode,
            child: _verifying
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(l10n.verifyButton),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminPending(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.adminPendingTitle,
            style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 12),
        Text(l10n.adminPendingMessage,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.backToSignIn),
          ),
        ),
      ],
    );
  }
}
