import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

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
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _codeController = TextEditingController();
  String _role = 'user';
  bool _loading = false;
  bool _googleLoading = false;
  bool _verifying = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;
  // Non-null once registration succeeds — switches the screen from the
  // form to either a code-entry step or an admin-pending message,
  // depending on .status. Registering no longer signs you in directly.
  RegistrationResult? _pendingRegistration;
  // While _pendingRegistration.status == 'pending_admin_approval', this
  // ticks every few seconds and asks the server whether the super admin
  // has clicked approve/reject yet, so the screen can flip straight into
  // the signed-in app instead of asking the user to sign in again.
  Timer? _pollTimer;
  bool _polling = false;
  bool _rejected = false;

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
        username: _username.text.trim(),
        role: _role,
      );
      if (!mounted) return;
      setState(() => _pendingRegistration = result);
      if (result.status == 'pending_admin_approval' &&
          (result.pendingSessionToken ?? '').isNotEmpty) {
        _startPollingForApproval(result.pendingSessionToken!);
      }
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
      if (mounted) {
        widget.onSignedIn();
        // onSignedIn() flips the app's root content to the home screen,
        // but this screen is still sitting on top of it in the nav stack
        // (pushed from LoginScreen) — pop back to actually reveal it
        // instead of leaving the user stuck looking at this one.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
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
      if (mounted) {
        widget.onSignedIn();
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on ApiException catch (e) {
      // Closing the account picker isn't a failure — leave _error alone
      // instead of showing "Sign-in cancelled" as if something broke.
      if (!e.cancelled) setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = AppLocalizations.of(context)!.googleSignInFailed);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startPollingForApproval(String pendingSessionToken) {
    _pollTimer?.cancel();
    // Immediate first check — the super admin may already have clicked
    // approve (e.g. tester with the approval email open) by the time the
    // client sees the pending screen, so the user shouldn't have to sit
    // through the first 4-second gap just to learn they're already in.
    _pollAdminStatus(pendingSessionToken);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pollAdminStatus(pendingSessionToken),
    );
  }

  Future<void> _pollAdminStatus(String pendingSessionToken) async {
    // Guard against overlapping polls if the network is slow — a single
    // in-flight request is enough; the next tick will pick up wherever
    // this one leaves off.
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final status = await ApiService.instance.checkAdminRequestStatus(
        pendingSessionToken: pendingSessionToken,
      );
      if (!mounted) return;
      switch (status.status) {
        case PendingAdminStatusValue.pending:
          // Still waiting — nothing to do, keep polling.
          break;
        case PendingAdminStatusValue.approved:
          _pollTimer?.cancel();
          final accessToken = status.accessToken;
          final user = status.user;
          if (accessToken == null || user == null) {
            setState(() => _error = 'Approval response was incomplete.');
            return;
          }
          await widget.session.applyAdminApproval(
            accessToken: accessToken,
            user: user,
          );
          if (!mounted) return;
          widget.onSignedIn();
          // Same reason as _verifyCode — LoginScreen pushed us on top
          // of the app root, so popping actually reveals the now
          // signed-in home instead of leaving this screen in front.
          Navigator.of(context).popUntil((route) => route.isFirst);
          break;
        case PendingAdminStatusValue.rejected:
          _pollTimer?.cancel();
          setState(() => _rejected = true);
          break;
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // The pending session token has expired — polling can't
        // recover on its own, but the user still gets in by signing
        // in normally once approved (their account exists).
        _pollTimer?.cancel();
        if (mounted) {
          setState(() => _error =
              'Your registration session expired. Please sign in from the login screen once approved.');
        }
      }
      // Transient errors (5xx, network) are ignored — the next tick
      // just tries again.
    } catch (_) {
      // Same: swallow transient failures so a flaky connection
      // doesn't derail the wait.
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
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
                        : _pendingRegistration!.status == 'pending_verification'
                            ? _buildVerifyCode(l10n)
                            : _buildAdminPending(l10n),
                  ),
                ),
              ),
            ),
          ),
        ),
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
            controller: _username,
            decoration: const InputDecoration(
              labelText: 'Username',
              hintText: 'e.g. globe_traveler',
              prefixText: '@',
            ),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            validator: (value) {
              final username = value?.trim() ?? '';
              if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.]{2,23}$')
                  .hasMatch(username)) {
                return 'Use 3-24 letters, numbers, periods, or underscores.';
              }
              return null;
            },
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
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            // Re-validates confirm-password live as this field changes, so
            // fixing the original password also clears a stale mismatch
            // error on the field below instead of leaving it stuck.
            onChanged: (_) => _formKey.currentState?.validate(),
            validator: (v) => (v == null || v.length < 6)
                ? l10n.passwordValidatorError
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmPassword,
            decoration: InputDecoration(
              labelText: l10n.confirmPasswordLabel,
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            obscureText: _obscureConfirmPassword,
            validator: (v) => (v != _password.text)
                ? l10n.confirmPasswordValidatorError
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
    if (_rejected) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.adminPendingTitle,
              style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 12),
          const Text(
            'Your request was declined by the super admin.',
            style: TextStyle(color: AppColors.clay),
          ),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.adminPendingTitle,
            style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 12),
        Text(l10n.adminPendingMessage,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        // A subtle "we're watching for it" indicator so the user knows
        // they don't have to hit refresh or come back — the app will
        // move on by itself the moment the super admin clicks approve.
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Waiting for approval — you\u2019ll be signed in automatically.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.clay)),
        ],
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
