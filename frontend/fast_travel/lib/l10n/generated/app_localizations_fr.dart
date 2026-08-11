// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get navDiscover => 'Découvrir';

  @override
  String get navFeed => 'Fil';

  @override
  String get navMyTrips => 'Mes voyages';

  @override
  String get navMap => 'Carte';

  @override
  String get navProfile => 'Profil';

  @override
  String get askAi => 'Demander à l\'IA';

  @override
  String get titleDiscover => 'Découvrir Yaoundé';

  @override
  String get titleFeed => 'Fil';

  @override
  String get titleMyTrips => 'Mes voyages';

  @override
  String get titleExploreMap => 'Explorer la carte';

  @override
  String get titleProfile => 'Profil';

  @override
  String get reviewDestinationsTooltip => 'Examiner les destinations';

  @override
  String get welcomeBack => 'Content de vous revoir';

  @override
  String get signInSubtitle =>
      'Connectez-vous pour continuer à planifier vos voyages au Cameroun.';

  @override
  String get emailLabel => 'E-mail';

  @override
  String get emailValidatorError => 'Saisissez un e-mail valide';

  @override
  String get passwordLabel => 'Mot de passe';

  @override
  String get passwordValidatorError => 'Au moins 6 caractères';

  @override
  String get couldNotReachServer =>
      'Impossible de joindre le serveur. Le backend est-il en cours d\'exécution ?';

  @override
  String get couldNotReachServerShort => 'Impossible de joindre le serveur.';

  @override
  String get googleSignInFailed =>
      'Échec de la connexion avec Google. Veuillez réessayer.';

  @override
  String get signIn => 'Se connecter';

  @override
  String get or => 'ou';

  @override
  String get continueWithGoogle => 'Continuer avec Google';

  @override
  String get newHereCreateAccount => 'Nouveau ici ? Créer un compte';

  @override
  String get createYourAccount => 'Créez votre compte';

  @override
  String get registerSubtitle =>
      'Choisissez un rôle et explorez des projets de voyage à Yaoundé.';

  @override
  String get fullNameLabel => 'Nom complet';

  @override
  String get requiredField => 'Champ requis';

  @override
  String get roleLabel => 'Rôle';

  @override
  String get roleUser => 'Utilisateur';

  @override
  String get roleWorker => 'Agent';

  @override
  String get roleAdmin => 'Administrateur';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get alreadyHaveAccount => 'Vous avez déjà un compte ? Connectez-vous';

  @override
  String get verifyEmailTitle => 'Vérifiez votre e-mail';

  @override
  String verifyEmailSubtitle(String email) {
    return 'Nous avons envoyé un code à 6 chiffres à $email. Saisissez-le ci-dessous pour terminer la création de votre compte.';
  }

  @override
  String get verificationCodeLabel => 'Code de vérification';

  @override
  String get verifyButton => 'Vérifier';

  @override
  String get adminPendingTitle => 'Demande envoyée';

  @override
  String get adminPendingMessage =>
      'Votre demande de compte administrateur a été envoyée pour approbation. Vous recevrez un e-mail une fois qu\'elle aura été examinée.';

  @override
  String get backToSignIn => 'Retour à la connexion';

  @override
  String get searchHint =>
      'Rechercher des destinations, régions ou ambiances...';

  @override
  String get noResultsFound => 'Aucun résultat trouvé';

  @override
  String get noResultsMessage =>
      'Essayez une autre recherche ou effacez le filtre.';

  @override
  String get cantReachServer => 'Impossible de joindre le serveur';

  @override
  String get suggestDestination => 'Suggérer une destination';

  @override
  String get addDestination => 'Ajouter une destination';

  @override
  String get submittedForReview =>
      'Envoyé — un agent ou un administrateur l\'examinera bientôt.';

  @override
  String get destinationAdded => 'Destination ajoutée.';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get destinationNameLabel => 'Nom';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get pickLocationOnMap => 'Choisir l\'emplacement sur la carte';

  @override
  String locationSelected(String lat, String lng) {
    return 'Emplacement : $lat, $lng';
  }

  @override
  String get addPhoto => 'Ajouter une photo';

  @override
  String get changePhoto => 'Changer la photo';

  @override
  String get pickLocationFirst =>
      'Choisissez d\'abord un emplacement sur la carte.';

  @override
  String get addPhotoFirst => 'Ajoutez d\'abord une photo.';

  @override
  String get submitForReview => 'Envoyer pour examen';

  @override
  String get displayName => 'Nom affiché';

  @override
  String get roleFieldLabel => 'Rôle';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get signOutConfirmTitle => 'Se déconnecter ?';

  @override
  String get signOutConfirmBody =>
      'Vous devrez vous reconnecter pour utiliser l\'application.';

  @override
  String get cancel => 'Annuler';

  @override
  String get editName => 'Modifier le nom';

  @override
  String get save => 'Enregistrer';

  @override
  String get language => 'Langue';

  @override
  String get languageEnglish => 'Anglais';

  @override
  String get languageFrench => 'Français';
}
