import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/models.dart';
import 'api_service.dart';

/// Holds the signed-in user for the whole app. Kept deliberately simple —
/// a plain ChangeNotifier is enough for Phase 1 and avoids pulling in a
/// state-management package before it's actually needed.
class SessionState extends ChangeNotifier {
  AppUser? currentUser;

  bool get isSignedIn => currentUser != null;

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

  Future<AppUser> register(
    String email,
    String password,
    String fullName, {
    required String role,
  }) async {
    try {
      final user = await ApiService.instance.register(
        email: email,
        password: password,
        fullName: fullName,
        role: role,
      );
      currentUser = user;
      notifyListeners();
      return user;
    } catch (e) {
      rethrow;
    }
  }

  /// Signs in with Google - sends the Google ID token directly to your backend
  Future<AppUser> signInWithGoogle() async {
    print('=== STARTING GOOGLE SIGN-IN ===');
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId:
            '866694354094-pn5kec29qfaq8nebpi8t6hnkgujb6s62.apps.googleusercontent.com',
      );

      print('1. Opening Google Sign-In...');
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        throw ApiException('Sign-in cancelled');
      }

      print('2. User: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      print('3. Got ID token: ${googleAuth.idToken?.substring(0, 30)}...');

      if (googleAuth.idToken == null) {
        throw ApiException('No ID token received from Google');
      }

      print('4. Sending token to backend...');
      final user = await ApiService.instance.loginWithGoogle(
        idToken: googleAuth.idToken!,
      );

      print('5. SUCCESS! User: ${user.fullName}');
      currentUser = user;
      notifyListeners();
      return user;
    } catch (e) {
      print('=== ERROR ===');
      print('Error: $e');
      rethrow;
    }
  }

  void signOut() {
    ApiService.instance.setToken(null);
    GoogleSignIn().signOut();
    currentUser = null;
    notifyListeners();
  }
}
