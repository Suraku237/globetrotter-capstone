// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navDiscover => 'Discover';

  @override
  String get navFeed => 'Feed';

  @override
  String get navMyTrips => 'My Trips';

  @override
  String get navMap => 'Map';

  @override
  String get navProfile => 'Profile';

  @override
  String get askAi => 'Ask AI';

  @override
  String get titleDiscover => 'Discover Yaoundé';

  @override
  String get titleFeed => 'Feed';

  @override
  String get titleMyTrips => 'My Trips';

  @override
  String get titleExploreMap => 'Explore Map';

  @override
  String get titleProfile => 'Profile';

  @override
  String get reviewDestinationsTooltip => 'Review destinations';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get signInSubtitle => 'Sign in to keep planning your Cameroon trips.';

  @override
  String get emailLabel => 'Email';

  @override
  String get emailValidatorError => 'Enter a valid email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordValidatorError => 'At least 6 characters';

  @override
  String get couldNotReachServer =>
      'Could not reach the server. Is the backend running?';

  @override
  String get couldNotReachServerShort => 'Could not reach the server.';

  @override
  String get googleSignInFailed => 'Google sign-in failed. Please try again.';

  @override
  String get signIn => 'Sign in';

  @override
  String get or => 'or';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get newHereCreateAccount => 'New here? Create an account';

  @override
  String get createYourAccount => 'Create your account';

  @override
  String get registerSubtitle =>
      'Choose a role and explore Yaoundé-based travel plans.';

  @override
  String get fullNameLabel => 'Full name';

  @override
  String get requiredField => 'Required';

  @override
  String get roleLabel => 'Role';

  @override
  String get roleUser => 'User';

  @override
  String get roleWorker => 'Worker';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get createAccount => 'Create account';

  @override
  String get alreadyHaveAccount => 'Already have an account? Sign in';

  @override
  String get verifyEmailTitle => 'Verify your email';

  @override
  String verifyEmailSubtitle(String email) {
    return 'We sent a 6-digit code to $email. Enter it below to finish creating your account.';
  }

  @override
  String get verificationCodeLabel => 'Verification code';

  @override
  String get verifyButton => 'Verify';

  @override
  String get adminPendingTitle => 'Request sent';

  @override
  String get adminPendingMessage =>
      'Your admin account request has been sent for approval. You\'ll get an email once it\'s reviewed.';

  @override
  String get backToSignIn => 'Back to sign in';

  @override
  String get searchHint => 'Search destinations, regions, or vibes...';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get noResultsMessage =>
      'Try searching for something else or clear the filter.';

  @override
  String get cantReachServer => 'Can\'t reach the server';

  @override
  String get suggestDestination => 'Suggest a destination';

  @override
  String get addDestination => 'Add destination';

  @override
  String get submittedForReview =>
      'Submitted — a worker or admin will review it soon.';

  @override
  String get destinationAdded => 'Destination added.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get destinationNameLabel => 'Name';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get pickLocationOnMap => 'Pick location on map';

  @override
  String locationSelected(String lat, String lng) {
    return 'Location: $lat, $lng';
  }

  @override
  String get addPhoto => 'Add a photo';

  @override
  String get changePhoto => 'Change photo';

  @override
  String get pickLocationFirst => 'Pick a location on the map first.';

  @override
  String get addPhotoFirst => 'Add a photo first.';

  @override
  String get submitForReview => 'Submit for review';

  @override
  String get displayName => 'Display name';

  @override
  String get roleFieldLabel => 'Role';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutConfirmTitle => 'Sign out?';

  @override
  String get signOutConfirmBody =>
      'You\'ll need to sign in again to use the app.';

  @override
  String get cancel => 'Cancel';

  @override
  String get editName => 'Edit name';

  @override
  String get save => 'Save';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'French';
}
