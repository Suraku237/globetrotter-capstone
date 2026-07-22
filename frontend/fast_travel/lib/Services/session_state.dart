import 'package:flutter/foundation.dart';
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

  void signOut() {
    ApiService.instance.setToken(null);
    currentUser = null;
    notifyListeners();
  }
}
