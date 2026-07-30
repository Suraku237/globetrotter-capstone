import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  /// Signs in with Google via Firebase Auth, then exchanges the Firebase
  /// ID token for this app's own JWT (same one email/password login uses).
  Future<AppUser> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      // User cancelled the picker — not an error, just no-op.
      throw ApiException('Sign-in cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final firebaseUserCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final firebaseIdToken = await firebaseUserCredential.user!.getIdToken();

    final user = await ApiService.instance.loginWithGoogle(
      idToken: firebaseIdToken!,
    );
    currentUser = user;
    notifyListeners();
    return user;
  }

  void signOut() {
    ApiService.instance.setToken(null);
    FirebaseAuth.instance.signOut();
    GoogleSignIn().signOut();
    currentUser = null;
    notifyListeners();
  }
}
