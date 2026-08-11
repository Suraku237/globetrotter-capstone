import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import 'api_service.dart';

/// Holds the signed-in user for the whole app. Kept deliberately simple —
/// a plain ChangeNotifier is enough for Phase 1 and avoids pulling in a
/// state-management package before it's actually needed.
class SessionState extends ChangeNotifier {
  AppUser? currentUser;

  bool get isSignedIn => currentUser != null;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '866694354094-pn5kec29qfaq8nebpi8t6hnkgujb6s62.apps.googleusercontent.com',
    scopes: ['email', 'profile', 'openid'],
  );

  Future<AppUser> login(String email, String password) async {
    try {
      final user = await ApiService.instance.login(
        email: email,
        password: password,
      );
      currentUser = user;
      notifyListeners();
      return user;
    } catch (e) {
      rethrow;
    }
  }

  // Doesn't sign in — see RegistrationResult.status for what happens next
  // (a code to verify, or an admin request pending approval).
  Future<RegistrationResult> register(
    String email,
    String password,
    String fullName, {
    required String role,
  }) {
    return ApiService.instance.register(
      email: email,
      password: password,
      fullName: fullName,
      role: role,
    );
  }

  Future<AppUser> verifyEmail(String email, String code) async {
    final user =
        await ApiService.instance.verifyEmail(email: email, code: code);
    currentUser = user;
    notifyListeners();
    return user;
  }

  Future<AppUser> signInWithGoogle() async {
    print('=== STARTING GOOGLE SIGN-IN ===');
    try {
      print('1. Opening Google Sign-In...');
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        throw ApiException('Sign-in cancelled');
      }

      print('2. User: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      print('3. Access token exists: ${googleAuth.accessToken != null}');
      print('4. ID token exists: ${googleAuth.idToken != null}');

      String tokenToSend;
      if (googleAuth.idToken != null && googleAuth.idToken!.isNotEmpty) {
        tokenToSend = googleAuth.idToken!;
        print('   Using ID token');
      } else if (googleAuth.accessToken != null &&
          googleAuth.accessToken!.isNotEmpty) {
        tokenToSend = googleAuth.accessToken!;
        print('   Using access token (ID token not available)');
      } else {
        throw ApiException('No token received from Google');
      }

      print('5. Sending token to backend...');
      final user = await ApiService.instance.loginWithGoogle(
        idToken: tokenToSend,
      );

      print('6. SUCCESS! User: ${user.fullName}');
      currentUser = user;
      notifyListeners();
      return user;
    } catch (e) {
      print('=== ERROR ===');
      print('Error: $e');
      rethrow;
    }
  }

  Future<void> updateProfile({String? fullName, XFile? avatarFile}) async {
    AppUser? updated;
    if (fullName != null && fullName.trim().isNotEmpty) {
      updated = await ApiService.instance.updateProfile(fullName: fullName.trim());
    }
    if (avatarFile != null) {
      updated = await ApiService.instance.uploadAvatar(avatarFile);
    }
    if (updated != null) {
      currentUser = updated;
      notifyListeners();
    }
  }

  void signOut() {
    ApiService.instance.setToken(null);
    _googleSignIn.signOut();
    currentUser = null;
    notifyListeners();
  }
}
