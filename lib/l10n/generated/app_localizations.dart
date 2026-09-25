import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fa.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_ps.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_ur.dart';
import 'app_localizations_uz.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fa'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('ps'),
    Locale('pt'),
    Locale('ru'),
    Locale('tr'),
    Locale('ur'),
    Locale('uz'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'ZEV'**
  String get appName;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get lastName;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phone;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get error;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @courses.
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get courses;

  /// No description provided for @myCourses.
  ///
  /// In en, this message translates to:
  /// **'My Courses'**
  String get myCourses;

  /// No description provided for @allCourses.
  ///
  /// In en, this message translates to:
  /// **'All Courses'**
  String get allCourses;

  /// No description provided for @scholarships.
  ///
  /// In en, this message translates to:
  /// **'Scholarships'**
  String get scholarships;

  /// No description provided for @announcements.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get announcements;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @biometricLogin.
  ///
  /// In en, this message translates to:
  /// **'Biometric Login'**
  String get biometricLogin;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support & Help'**
  String get support;

  /// No description provided for @aiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistant;

  /// No description provided for @reels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get reels;

  /// No description provided for @stories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get stories;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// No description provided for @transactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get transactions;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @instructor.
  ///
  /// In en, this message translates to:
  /// **'Instructor'**
  String get instructor;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @free.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get free;

  /// No description provided for @enrollNow.
  ///
  /// In en, this message translates to:
  /// **'Enroll Now'**
  String get enrollNow;

  /// No description provided for @lessons.
  ///
  /// In en, this message translates to:
  /// **'Lessons'**
  String get lessons;

  /// No description provided for @quizzes.
  ///
  /// In en, this message translates to:
  /// **'Quizzes'**
  String get quizzes;

  /// No description provided for @certificates.
  ///
  /// In en, this message translates to:
  /// **'Certificates'**
  String get certificates;

  /// No description provided for @assignments.
  ///
  /// In en, this message translates to:
  /// **'Assignments'**
  String get assignments;

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @directMessages.
  ///
  /// In en, this message translates to:
  /// **'Direct Messages'**
  String get directMessages;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @soon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get soon;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @wishlist.
  ///
  /// In en, this message translates to:
  /// **'Wishlist'**
  String get wishlist;

  /// No description provided for @liveCampus.
  ///
  /// In en, this message translates to:
  /// **'Live Campus'**
  String get liveCampus;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get live;

  /// No description provided for @examsQuizzes.
  ///
  /// In en, this message translates to:
  /// **'Exams & Quizzes'**
  String get examsQuizzes;

  /// No description provided for @paymentsInvoices.
  ///
  /// In en, this message translates to:
  /// **'Payments & Invoices'**
  String get paymentsInvoices;

  /// No description provided for @tradingJournal.
  ///
  /// In en, this message translates to:
  /// **'Trading Journal'**
  String get tradingJournal;

  /// No description provided for @createPost.
  ///
  /// In en, this message translates to:
  /// **'Create Post'**
  String get createPost;

  /// No description provided for @socialFeed.
  ///
  /// In en, this message translates to:
  /// **'Social Feed'**
  String get socialFeed;

  /// No description provided for @feed.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get feed;

  /// No description provided for @walletReferral.
  ///
  /// In en, this message translates to:
  /// **'Wallet & Referral'**
  String get walletReferral;

  /// No description provided for @friendsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Friends & Network'**
  String get friendsNetwork;

  /// No description provided for @friends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friends;

  /// No description provided for @achievements.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievements;

  /// No description provided for @safiAiAssistant.
  ///
  /// In en, this message translates to:
  /// **'ZEV AI Assistant'**
  String get safiAiAssistant;

  /// No description provided for @helpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get helpCenter;

  /// No description provided for @supportTickets.
  ///
  /// In en, this message translates to:
  /// **'Support Tickets'**
  String get supportTickets;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// No description provided for @appSettings.
  ///
  /// In en, this message translates to:
  /// **'App Settings'**
  String get appSettings;

  /// No description provided for @studentPortalMenu.
  ///
  /// In en, this message translates to:
  /// **'STUDENT PORTAL MENU'**
  String get studentPortalMenu;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'LOG OUT'**
  String get logOut;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'MENU'**
  String get menu;

  /// No description provided for @loadingDashboard.
  ///
  /// In en, this message translates to:
  /// **'LOADING DASHBOARD...'**
  String get loadingDashboard;

  /// No description provided for @academyStudent.
  ///
  /// In en, this message translates to:
  /// **'ZEV MEMBER'**
  String get academyStudent;

  /// No description provided for @walletBalance.
  ///
  /// In en, this message translates to:
  /// **'Wallet Balance'**
  String get walletBalance;

  /// No description provided for @dailyStreak.
  ///
  /// In en, this message translates to:
  /// **'DAILY STREAK'**
  String get dailyStreak;

  /// No description provided for @longestStreak.
  ///
  /// In en, this message translates to:
  /// **'LONGEST STREAK'**
  String get longestStreak;

  /// No description provided for @daysCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Days'**
  String daysCount(String count);

  /// No description provided for @enrolled.
  ///
  /// In en, this message translates to:
  /// **'Enrolled'**
  String get enrolled;

  /// No description provided for @score.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get score;

  /// No description provided for @certs.
  ///
  /// In en, this message translates to:
  /// **'Certs'**
  String get certs;

  /// No description provided for @continueLearning.
  ///
  /// In en, this message translates to:
  /// **'Continue Learning'**
  String get continueLearning;

  /// No description provided for @upcomingClasses.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Live Classes'**
  String get upcomingClasses;

  /// No description provided for @noClassesToday.
  ///
  /// In en, this message translates to:
  /// **'No live classes scheduled for today'**
  String get noClassesToday;

  /// No description provided for @exploreAll.
  ///
  /// In en, this message translates to:
  /// **'Explore All'**
  String get exploreAll;

  /// No description provided for @myEnrolled.
  ///
  /// In en, this message translates to:
  /// **'My Enrolled'**
  String get myEnrolled;

  /// No description provided for @searchCourses.
  ///
  /// In en, this message translates to:
  /// **'Search by course title, instructor...'**
  String get searchCourses;

  /// No description provided for @allCategories.
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get allCategories;

  /// No description provided for @filterByCategory.
  ///
  /// In en, this message translates to:
  /// **'Filter by Category'**
  String get filterByCategory;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @exploreAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Explore as Guest'**
  String get exploreAsGuest;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Log In'**
  String get alreadyHaveAccount;

  /// No description provided for @dontHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'\'t have an account? Sign Up'**
  String get dontHaveAccount;

  /// No description provided for @stepIntoDigitalCampus.
  ///
  /// In en, this message translates to:
  /// **'Step into your digital campus.'**
  String get stepIntoDigitalCampus;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'EMAIL ADDRESS'**
  String get emailAddress;

  /// No description provided for @enterYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get enterYourEmail;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @enterStrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter a strong password...'**
  String get enterStrongPassword;

  /// No description provided for @forgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot?'**
  String get forgot;

  /// No description provided for @rememberMe.
  ///
  /// In en, this message translates to:
  /// **'Remember me'**
  String get rememberMe;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'SIGN IN'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'SIGN UP'**
  String get signUp;

  /// No description provided for @newHere.
  ///
  /// In en, this message translates to:
  /// **'New here?'**
  String get newHere;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @loginToAccount.
  ///
  /// In en, this message translates to:
  /// **'Login to Account 🚀'**
  String get loginToAccount;

  /// No description provided for @createNewAccount.
  ///
  /// In en, this message translates to:
  /// **'Create New Account'**
  String get createNewAccount;

  /// No description provided for @skipToFeed.
  ///
  /// In en, this message translates to:
  /// **'Skip to Feed'**
  String get skipToFeed;

  /// No description provided for @readyToBegin.
  ///
  /// In en, this message translates to:
  /// **'Ready to Begin?'**
  String get readyToBegin;

  /// No description provided for @readyToBeginDesc.
  ///
  /// In en, this message translates to:
  /// **'Log in to your account or create a new one to access elite training and live campus tools.'**
  String get readyToBeginDesc;

  /// No description provided for @continueText.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueText;

  /// No description provided for @exploreFeedAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Explore Feed & Reels as Guest 🌟'**
  String get exploreFeedAsGuest;

  /// No description provided for @personalDetails.
  ///
  /// In en, this message translates to:
  /// **'Personal Details'**
  String get personalDetails;

  /// No description provided for @contactAndCountry.
  ///
  /// In en, this message translates to:
  /// **'Contact & Country'**
  String get contactAndCountry;

  /// No description provided for @accountSecurity.
  ///
  /// In en, this message translates to:
  /// **'Account Security'**
  String get accountSecurity;

  /// No description provided for @learningGoals.
  ///
  /// In en, this message translates to:
  /// **'Learning Goals'**
  String get learningGoals;

  /// No description provided for @fatherName.
  ///
  /// In en, this message translates to:
  /// **'Fathers Name'**
  String get fatherName;

  /// No description provided for @dateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth'**
  String get dateOfBirth;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// No description provided for @bio.
  ///
  /// In en, this message translates to:
  /// **'Bio / Summary'**
  String get bio;

  /// No description provided for @referralCode.
  ///
  /// In en, this message translates to:
  /// **'Referral Code (Optional)'**
  String get referralCode;

  /// No description provided for @profilePhotoRequired.
  ///
  /// In en, this message translates to:
  /// **'Profile photo is required.'**
  String get profilePhotoRequired;

  /// No description provided for @fillPersonalDetails.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all personal details.'**
  String get fillPersonalDetails;

  /// No description provided for @countryPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Country and phone number are required.'**
  String get countryPhoneRequired;

  /// No description provided for @verifyEmailBeforeLogin.
  ///
  /// In en, this message translates to:
  /// **'Please verify your email address before signing in.'**
  String get verifyEmailBeforeLogin;

  /// No description provided for @networkConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Network connection failed. Please check your internet connection.'**
  String get networkConnectionFailed;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters.'**
  String get passwordMinLength;

  /// No description provided for @passwordChangedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully! 🔒'**
  String get passwordChangedSuccess;

  /// No description provided for @updatePassword.
  ///
  /// In en, this message translates to:
  /// **'UPDATE PASSWORD 🔒'**
  String get updatePassword;

  /// No description provided for @appLockAndPrivacy.
  ///
  /// In en, this message translates to:
  /// **'App Lock & Privacy'**
  String get appLockAndPrivacy;

  /// No description provided for @biometricAuth.
  ///
  /// In en, this message translates to:
  /// **'Biometric Authentication'**
  String get biometricAuth;

  /// No description provided for @biometricAuthDesc.
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint or face recognition to unlock.'**
  String get biometricAuthDesc;

  /// No description provided for @biometricLoginEnabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric login enabled! 🔓'**
  String get biometricLoginEnabled;

  /// No description provided for @biometricsNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Biometrics not supported on this device.'**
  String get biometricsNotSupported;

  /// No description provided for @pinLock.
  ///
  /// In en, this message translates to:
  /// **'4-Digit PIN Lock'**
  String get pinLock;

  /// No description provided for @pinLockDesc.
  ///
  /// In en, this message translates to:
  /// **'Set a secret security PIN for fast access.'**
  String get pinLockDesc;

  /// No description provided for @setSecretPin.
  ///
  /// In en, this message translates to:
  /// **'Set 4-Digit PIN'**
  String get setSecretPin;

  /// No description provided for @savePin.
  ///
  /// In en, this message translates to:
  /// **'Save PIN'**
  String get savePin;

  /// No description provided for @pinSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'PIN code successfully saved! 🔑'**
  String get pinSavedSuccess;

  /// No description provided for @pinMustBe4Digits.
  ///
  /// In en, this message translates to:
  /// **'PIN must be 4 digits.'**
  String get pinMustBe4Digits;

  /// No description provided for @preferencesAndLanguage.
  ///
  /// In en, this message translates to:
  /// **'Preferences & Language'**
  String get preferencesAndLanguage;

  /// No description provided for @pushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get pushNotifications;

  /// No description provided for @pushNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Receive course updates, alerts and messages.'**
  String get pushNotificationsDesc;

  /// No description provided for @liveCampusSession.
  ///
  /// In en, this message translates to:
  /// **'LIVE CAMPUS SESSION'**
  String get liveCampusSession;

  /// No description provided for @joinLiveMeetingRoom.
  ///
  /// In en, this message translates to:
  /// **'Join Live Meeting Room 🚀'**
  String get joinLiveMeetingRoom;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join 🚀'**
  String get join;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'IN PROGRESS'**
  String get inProgress;

  /// No description provided for @noCoursesEnrolledYet.
  ///
  /// In en, this message translates to:
  /// **'You havent enrolled in any courses yet.'**
  String get noCoursesEnrolledYet;

  /// No description provided for @activeLiveCampusClasses.
  ///
  /// In en, this message translates to:
  /// **'Active Live Campus Classes'**
  String get activeLiveCampusClasses;

  /// No description provided for @noActiveClasses.
  ///
  /// In en, this message translates to:
  /// **'No active class groups found.'**
  String get noActiveClasses;

  /// No description provided for @academyLearningHub.
  ///
  /// In en, this message translates to:
  /// **'ZEV Hub'**
  String get academyLearningHub;

  /// No description provided for @academyHubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Explore masterclasses, view your enrollments & upgrade skills.'**
  String get academyHubSubtitle;

  /// No description provided for @noCoursesFound.
  ///
  /// In en, this message translates to:
  /// **'No courses found matching your query.'**
  String get noCoursesFound;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @notices.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get notices;

  /// No description provided for @myProgress.
  ///
  /// In en, this message translates to:
  /// **'My Progress'**
  String get myProgress;

  /// No description provided for @completedCourses.
  ///
  /// In en, this message translates to:
  /// **'Completed Courses'**
  String get completedCourses;

  /// No description provided for @totalLessons.
  ///
  /// In en, this message translates to:
  /// **'Total Lessons'**
  String get totalLessons;

  /// No description provided for @downloadCertificate.
  ///
  /// In en, this message translates to:
  /// **'Download Certificate'**
  String get downloadCertificate;

  /// No description provided for @shareCertificate.
  ///
  /// In en, this message translates to:
  /// **'Share Certificate'**
  String get shareCertificate;

  /// No description provided for @walletDeposit.
  ///
  /// In en, this message translates to:
  /// **'Deposit Funds'**
  String get walletDeposit;

  /// No description provided for @walletWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw Funds'**
  String get walletWithdraw;

  /// No description provided for @inviteFriends.
  ///
  /// In en, this message translates to:
  /// **'Invite Friends'**
  String get inviteFriends;

  /// No description provided for @copyReferral.
  ///
  /// In en, this message translates to:
  /// **'Copy Referral Link'**
  String get copyReferral;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard!'**
  String get copiedToClipboard;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @welcomeOnboarding1Title.
  ///
  /// In en, this message translates to:
  /// **'Welcome to ZEV'**
  String get welcomeOnboarding1Title;

  /// No description provided for @welcomeOnboarding1Desc.
  ///
  /// In en, this message translates to:
  /// **'Your premier gateway to mastering financial markets, software engineering, and modern digital business.'**
  String get welcomeOnboarding1Desc;

  /// No description provided for @welcomeOnboarding2Title.
  ///
  /// In en, this message translates to:
  /// **'Social Feed & Discussions'**
  String get welcomeOnboarding2Title;

  /// No description provided for @welcomeOnboarding2Desc.
  ///
  /// In en, this message translates to:
  /// **'Explore real-time trade analyses, coding tutorials, market insights, and student discussions directly from the community.'**
  String get welcomeOnboarding2Desc;

  /// No description provided for @welcomeOnboarding3Title.
  ///
  /// In en, this message translates to:
  /// **'Educational Video Reels'**
  String get welcomeOnboarding3Title;

  /// No description provided for @welcomeOnboarding3Desc.
  ///
  /// In en, this message translates to:
  /// **'Watch bite-sized educational video reels, trading setups, programming tips, and market recaps with vertical swipe.'**
  String get welcomeOnboarding3Desc;

  /// No description provided for @welcomeOnboarding4Title.
  ///
  /// In en, this message translates to:
  /// **'Direct Messaging & Community Hub'**
  String get welcomeOnboarding4Title;

  /// No description provided for @welcomeOnboarding4Desc.
  ///
  /// In en, this message translates to:
  /// **'Connect with classmates, share direct media messages, collaborate with mentors, and stay updated with live alerts.'**
  String get welcomeOnboarding4Desc;

  /// No description provided for @welcomeOnboarding5Title.
  ///
  /// In en, this message translates to:
  /// **'Live Campus & Interactive Hubs'**
  String get welcomeOnboarding5Title;

  /// No description provided for @welcomeOnboarding5Desc.
  ///
  /// In en, this message translates to:
  /// **'Attend corporate Microsoft Teams lectures, sync with secure Signal operations, and check in to daily classes.'**
  String get welcomeOnboarding5Desc;

  /// No description provided for @welcomeOnboarding6Title.
  ///
  /// In en, this message translates to:
  /// **'Professional Trading Journal'**
  String get welcomeOnboarding6Title;

  /// No description provided for @welcomeOnboarding6Desc.
  ///
  /// In en, this message translates to:
  /// **'Log your forex and crypto executions, manage risk, track R/R multiples, and build your edge like a pro.'**
  String get welcomeOnboarding6Desc;

  /// No description provided for @welcomeOnboarding7Title.
  ///
  /// In en, this message translates to:
  /// **'Examination Center & Quizzes'**
  String get welcomeOnboarding7Title;

  /// No description provided for @welcomeOnboarding7Desc.
  ///
  /// In en, this message translates to:
  /// **'Test your knowledge through descriptive academic exams, complete homework, and track your official grades.'**
  String get welcomeOnboarding7Desc;

  /// No description provided for @welcomeOnboarding8Title.
  ///
  /// In en, this message translates to:
  /// **'Earn & Grow Together'**
  String get welcomeOnboarding8Title;

  /// No description provided for @welcomeOnboarding8Desc.
  ///
  /// In en, this message translates to:
  /// **'Invite friends using your unique referral code, earn instant cash bonuses, and unlock verified blockchain credentials.'**
  String get welcomeOnboarding8Desc;

  /// No description provided for @loadingExams.
  ///
  /// In en, this message translates to:
  /// **'Loading Exams...'**
  String get loadingExams;

  /// No description provided for @examinationCenter.
  ///
  /// In en, this message translates to:
  /// **'Examination Center'**
  String get examinationCenter;

  /// No description provided for @examinationCenterDesc.
  ///
  /// In en, this message translates to:
  /// **'Take your academic exams and track official grades.'**
  String get examinationCenterDesc;

  /// No description provided for @totalExams.
  ///
  /// In en, this message translates to:
  /// **'Total Exams'**
  String get totalExams;

  /// No description provided for @passed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get passed;

  /// No description provided for @toDo.
  ///
  /// In en, this message translates to:
  /// **'To Do'**
  String get toDo;

  /// No description provided for @attempted.
  ///
  /// In en, this message translates to:
  /// **'Attempted'**
  String get attempted;

  /// No description provided for @passMark.
  ///
  /// In en, this message translates to:
  /// **'Pass Mark'**
  String get passMark;

  /// No description provided for @startExam.
  ///
  /// In en, this message translates to:
  /// **'Start Exam'**
  String get startExam;

  /// No description provided for @statusPassed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get statusPassed;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Chance (Failed)'**
  String get statusFailed;

  /// No description provided for @awaitingGrading.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Grading'**
  String get awaitingGrading;

  /// No description provided for @noExamsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No exams available right now.'**
  String get noExamsAvailable;

  /// No description provided for @assignmentsAttendance.
  ///
  /// In en, this message translates to:
  /// **'Assignments & Attendance'**
  String get assignmentsAttendance;

  /// No description provided for @assignmentsDesc.
  ///
  /// In en, this message translates to:
  /// **'Sign today\'\'s attendance, submit homework, and track academic progress.'**
  String get assignmentsDesc;

  /// No description provided for @todaysCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Today\'\'s Check-in'**
  String get todaysCheckIn;

  /// No description provided for @signed.
  ///
  /// In en, this message translates to:
  /// **'Signed'**
  String get signed;

  /// No description provided for @signNow.
  ///
  /// In en, this message translates to:
  /// **'Sign Now'**
  String get signNow;

  /// No description provided for @signing.
  ///
  /// In en, this message translates to:
  /// **'Signing...'**
  String get signing;

  /// No description provided for @teamsRoom.
  ///
  /// In en, this message translates to:
  /// **'Teams Room'**
  String get teamsRoom;

  /// No description provided for @signalGroup.
  ///
  /// In en, this message translates to:
  /// **'Signal Group'**
  String get signalGroup;

  /// No description provided for @classAssignments.
  ///
  /// In en, this message translates to:
  /// **'Class Assignments'**
  String get classAssignments;

  /// No description provided for @submitAssignment.
  ///
  /// In en, this message translates to:
  /// **'Submit Assignment'**
  String get submitAssignment;

  /// No description provided for @uploadSolution.
  ///
  /// In en, this message translates to:
  /// **'Upload Solution'**
  String get uploadSolution;

  /// No description provided for @downloadAttachment.
  ///
  /// In en, this message translates to:
  /// **'Download Attachment'**
  String get downloadAttachment;

  /// No description provided for @noAssignmentsFound.
  ///
  /// In en, this message translates to:
  /// **'No assignments found.'**
  String get noAssignmentsFound;

  /// No description provided for @due.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get due;

  /// No description provided for @submitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get submitted;

  /// No description provided for @graded.
  ///
  /// In en, this message translates to:
  /// **'Graded'**
  String get graded;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @globalScholarships.
  ///
  /// In en, this message translates to:
  /// **'Global Scholarships'**
  String get globalScholarships;

  /// No description provided for @globalScholarshipsDesc.
  ///
  /// In en, this message translates to:
  /// **'Explore verified academic grants & international opportunities.'**
  String get globalScholarshipsDesc;

  /// No description provided for @availableOpportunities.
  ///
  /// In en, this message translates to:
  /// **'Available Opportunities'**
  String get availableOpportunities;

  /// No description provided for @scholarshipOverview.
  ///
  /// In en, this message translates to:
  /// **'Scholarship Overview'**
  String get scholarshipOverview;

  /// No description provided for @noScholarshipsFound.
  ///
  /// In en, this message translates to:
  /// **'No scholarships found for this region.'**
  String get noScholarshipsFound;

  /// No description provided for @applyNow.
  ///
  /// In en, this message translates to:
  /// **'Apply Now'**
  String get applyNow;

  /// No description provided for @deadline.
  ///
  /// In en, this message translates to:
  /// **'Deadline'**
  String get deadline;

  /// No description provided for @eligibilityCriteria.
  ///
  /// In en, this message translates to:
  /// **'Eligibility Criteria'**
  String get eligibilityCriteria;

  /// No description provided for @requiredDocuments.
  ///
  /// In en, this message translates to:
  /// **'Required Documents'**
  String get requiredDocuments;

  /// No description provided for @myAchievements.
  ///
  /// In en, this message translates to:
  /// **'My Achievements'**
  String get myAchievements;

  /// No description provided for @myAchievementsDesc.
  ///
  /// In en, this message translates to:
  /// **'A structured record of your academic milestones.'**
  String get myAchievementsDesc;

  /// No description provided for @officialCertificates.
  ///
  /// In en, this message translates to:
  /// **'Official Certificates'**
  String get officialCertificates;

  /// No description provided for @badgesAndHonors.
  ///
  /// In en, this message translates to:
  /// **'Badges & Honors'**
  String get badgesAndHonors;

  /// No description provided for @verifiedCredential.
  ///
  /// In en, this message translates to:
  /// **'Verified Credential'**
  String get verifiedCredential;

  /// No description provided for @issued.
  ///
  /// In en, this message translates to:
  /// **'Issued'**
  String get issued;

  /// No description provided for @viewPdf.
  ///
  /// In en, this message translates to:
  /// **'View PDF'**
  String get viewPdf;

  /// No description provided for @noCertificatesYet.
  ///
  /// In en, this message translates to:
  /// **'No certificates yet.'**
  String get noCertificatesYet;

  /// No description provided for @noBadgesYet.
  ///
  /// In en, this message translates to:
  /// **'No badges yet.'**
  String get noBadgesYet;

  /// No description provided for @points.
  ///
  /// In en, this message translates to:
  /// **'Pts'**
  String get points;

  /// No description provided for @helpCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & Support Center'**
  String get helpCenterTitle;

  /// No description provided for @helpCenterDesc.
  ///
  /// In en, this message translates to:
  /// **'Submit support tickets, read FAQs, and reach our dedicated team.'**
  String get helpCenterDesc;

  /// No description provided for @submitTicket.
  ///
  /// In en, this message translates to:
  /// **'Submit Ticket'**
  String get submitTicket;

  /// No description provided for @submittingTicket.
  ///
  /// In en, this message translates to:
  /// **'Submitting Ticket...'**
  String get submittingTicket;

  /// No description provided for @ticketSubject.
  ///
  /// In en, this message translates to:
  /// **'Ticket Subject'**
  String get ticketSubject;

  /// No description provided for @ticketMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get ticketMessage;

  /// No description provided for @ticketDepartment.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get ticketDepartment;

  /// No description provided for @ticketSuccess.
  ///
  /// In en, this message translates to:
  /// **'Support ticket submitted successfully!'**
  String get ticketSuccess;

  /// No description provided for @faqTitle.
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get faqTitle;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get contactSupport;

  /// No description provided for @howCanWeHelp.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get howCanWeHelp;

  /// No description provided for @howCanWeHelpDesc.
  ///
  /// In en, this message translates to:
  /// **'Submit a ticket, explore FAQs, or reach out to us directly.'**
  String get howCanWeHelpDesc;

  /// No description provided for @submitSupportTicket.
  ///
  /// In en, this message translates to:
  /// **'Submit a Support Ticket'**
  String get submitSupportTicket;

  /// No description provided for @fillSubjectAndMessage.
  ///
  /// In en, this message translates to:
  /// **'Please fill in both subject and message fields.'**
  String get fillSubjectAndMessage;

  /// No description provided for @subjectHint.
  ///
  /// In en, this message translates to:
  /// **'Subject / Issue summary...'**
  String get subjectHint;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Describe your problem or request in detail...'**
  String get messageHint;

  /// No description provided for @generalSupport.
  ///
  /// In en, this message translates to:
  /// **'General Support'**
  String get generalSupport;

  /// No description provided for @technicalIssue.
  ///
  /// In en, this message translates to:
  /// **'Technical Issue'**
  String get technicalIssue;

  /// No description provided for @billingAndPayments.
  ///
  /// In en, this message translates to:
  /// **'Billing & Payments'**
  String get billingAndPayments;

  /// No description provided for @courseContent.
  ///
  /// In en, this message translates to:
  /// **'Course Content'**
  String get courseContent;

  /// No description provided for @directCommunications.
  ///
  /// In en, this message translates to:
  /// **'Direct Communications'**
  String get directCommunications;

  /// No description provided for @officialEmail.
  ///
  /// In en, this message translates to:
  /// **'Official Email'**
  String get officialEmail;

  /// No description provided for @academyHotline.
  ///
  /// In en, this message translates to:
  /// **'ZEV Support'**
  String get academyHotline;

  /// No description provided for @officialChannelsAndSocials.
  ///
  /// In en, this message translates to:
  /// **'Official Channels & Socials'**
  String get officialChannelsAndSocials;

  /// No description provided for @whatsappCommunity.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp Community Channel'**
  String get whatsappCommunity;

  /// No description provided for @whatsappCommunityDesc.
  ///
  /// In en, this message translates to:
  /// **'Join our official broadcast channel for instant updates'**
  String get whatsappCommunityDesc;

  /// No description provided for @faq1Q.
  ///
  /// In en, this message translates to:
  /// **'How do I join live classes?'**
  String get faq1Q;

  /// No description provided for @faq1A.
  ///
  /// In en, this message translates to:
  /// **'You can join live sessions directly from the \'\'Live Campus\'\' section using the meeting room link provided for your batch. Ensure you have Zoom/Meet installed.'**
  String get faq1A;

  /// No description provided for @faq2Q.
  ///
  /// In en, this message translates to:
  /// **'How are certificates issued?'**
  String get faq2Q;

  /// No description provided for @faq2A.
  ///
  /// In en, this message translates to:
  /// **'Once you successfully pass your final exams and complete the course requirements, your official verified certificate will automatically appear in the \'\'Certificates\'\' section as a downloadable PDF.'**
  String get faq2A;

  /// No description provided for @faq3Q.
  ///
  /// In en, this message translates to:
  /// **'Can I apply for international scholarships?'**
  String get faq3Q;

  /// No description provided for @faq3A.
  ///
  /// In en, this message translates to:
  /// **'Absolutely! Explore our \'\'Scholarships\'\' portal to discover fully funded global grants, eligibility criteria, and direct application links curated by ZEV.'**
  String get faq3A;

  /// No description provided for @paymentsAndInvoices.
  ///
  /// In en, this message translates to:
  /// **'Payments & Invoices'**
  String get paymentsAndInvoices;

  /// No description provided for @paymentsAndInvoicesDesc.
  ///
  /// In en, this message translates to:
  /// **'Track transaction history, receipts, and apply discount coupons.'**
  String get paymentsAndInvoicesDesc;

  /// No description provided for @discountAndScholarships.
  ///
  /// In en, this message translates to:
  /// **'Discount & Scholarships'**
  String get discountAndScholarships;

  /// No description provided for @enterCouponCode.
  ///
  /// In en, this message translates to:
  /// **'Enter coupon code...'**
  String get enterCouponCode;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @couponSuccess.
  ///
  /// In en, this message translates to:
  /// **'Coupon applied successfully! Discount unlocked. 🎉'**
  String get couponSuccess;

  /// No description provided for @couponInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid or expired coupon code. ❌'**
  String get couponInvalid;

  /// No description provided for @transactionHistory.
  ///
  /// In en, this message translates to:
  /// **'Transaction History'**
  String get transactionHistory;

  /// No description provided for @transactionDetails.
  ///
  /// In en, this message translates to:
  /// **'Transaction Details'**
  String get transactionDetails;

  /// No description provided for @transactionId.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID'**
  String get transactionId;

  /// No description provided for @gateway.
  ///
  /// In en, this message translates to:
  /// **'Gateway'**
  String get gateway;

  /// No description provided for @reference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get reference;

  /// No description provided for @dateTime.
  ///
  /// In en, this message translates to:
  /// **'Date & Time'**
  String get dateTime;

  /// No description provided for @noTransactionsYet.
  ///
  /// In en, this message translates to:
  /// **'No payment history found.'**
  String get noTransactionsYet;

  /// No description provided for @safiCommunity.
  ///
  /// In en, this message translates to:
  /// **'ZEV Community'**
  String get safiCommunity;

  /// No description provided for @safiCommunityDesc.
  ///
  /// In en, this message translates to:
  /// **'Experience real-time connection. Access your official classroom operations on Signal.'**
  String get safiCommunityDesc;

  /// No description provided for @searchActiveChannels.
  ///
  /// In en, this message translates to:
  /// **'Search active channels...'**
  String get searchActiveChannels;

  /// No description provided for @faculty.
  ///
  /// In en, this message translates to:
  /// **'Faculty'**
  String get faculty;

  /// No description provided for @enterSignalGroup.
  ///
  /// In en, this message translates to:
  /// **'Enter protected Signal group channel...'**
  String get enterSignalGroup;

  /// No description provided for @signalSyncPending.
  ///
  /// In en, this message translates to:
  /// **'Signal Workspace Sync Pending'**
  String get signalSyncPending;

  /// No description provided for @noEnrolledChannels.
  ///
  /// In en, this message translates to:
  /// **'No Enrolled Channels'**
  String get noEnrolledChannels;

  /// No description provided for @joinCurriculumToUnlock.
  ///
  /// In en, this message translates to:
  /// **'Join an active course curriculum to unlock your priority workspace.'**
  String get joinCurriculumToUnlock;

  /// No description provided for @loadingCommunity.
  ///
  /// In en, this message translates to:
  /// **'LOADING COMMUNITY...'**
  String get loadingCommunity;

  /// No description provided for @downloadFile.
  ///
  /// In en, this message translates to:
  /// **'Download File'**
  String get downloadFile;

  /// No description provided for @downloadFileToDevice.
  ///
  /// In en, this message translates to:
  /// **'Download File to Device 📥'**
  String get downloadFileToDevice;

  /// No description provided for @downloadSuccess.
  ///
  /// In en, this message translates to:
  /// **'File downloaded successfully to Downloads folder! 📁'**
  String get downloadSuccess;

  /// No description provided for @downloadingFile.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOADING FILE...'**
  String get downloadingFile;

  /// No description provided for @loadingPdfViewer.
  ///
  /// In en, this message translates to:
  /// **'Loading PDF Viewer...'**
  String get loadingPdfViewer;

  /// No description provided for @couldNotLoadPdf.
  ///
  /// In en, this message translates to:
  /// **'Could not load PDF document.'**
  String get couldNotLoadPdf;

  /// No description provided for @noDocumentAttached.
  ///
  /// In en, this message translates to:
  /// **'No document attached.'**
  String get noDocumentAttached;

  /// No description provided for @leadInstructor.
  ///
  /// In en, this message translates to:
  /// **'Lead Instructor'**
  String get leadInstructor;

  /// No description provided for @includesCertificate.
  ///
  /// In en, this message translates to:
  /// **'Includes Certificate'**
  String get includesCertificate;

  /// No description provided for @noCertificate.
  ///
  /// In en, this message translates to:
  /// **'No Certificate'**
  String get noCertificate;

  /// No description provided for @freeSession.
  ///
  /// In en, this message translates to:
  /// **'FREE SESSION'**
  String get freeSession;

  /// No description provided for @freeTrialBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'7-Day Free Trial Available! 🎁'**
  String get freeTrialBannerTitle;

  /// No description provided for @freeTrialBannerDesc.
  ///
  /// In en, this message translates to:
  /// **'7-day free trial reservation active. Access automatically locks after one week.'**
  String get freeTrialBannerDesc;

  /// No description provided for @classHubAndDetails.
  ///
  /// In en, this message translates to:
  /// **'Class Hub & Details'**
  String get classHubAndDetails;

  /// No description provided for @enrolledAndActive.
  ///
  /// In en, this message translates to:
  /// **'ENROLLED & ACTIVE ✓'**
  String get enrolledAndActive;

  /// No description provided for @paymentPending.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT PENDING'**
  String get paymentPending;

  /// No description provided for @registerForCourse.
  ///
  /// In en, this message translates to:
  /// **'Register for Course'**
  String get registerForCourse;

  /// No description provided for @alreadyEnrolled.
  ///
  /// In en, this message translates to:
  /// **'Already Enrolled'**
  String get alreadyEnrolled;

  /// No description provided for @courseSyllabus.
  ///
  /// In en, this message translates to:
  /// **'Course Syllabus'**
  String get courseSyllabus;

  /// No description provided for @selectClassBatch.
  ///
  /// In en, this message translates to:
  /// **'Select Class Batch'**
  String get selectClassBatch;

  /// No description provided for @scheduleInfo.
  ///
  /// In en, this message translates to:
  /// **'Schedule Info'**
  String get scheduleInfo;

  /// No description provided for @classDaysTime.
  ///
  /// In en, this message translates to:
  /// **'Class Days & Time'**
  String get classDaysTime;

  /// No description provided for @joinMeeting.
  ///
  /// In en, this message translates to:
  /// **'Join Meeting Room'**
  String get joinMeeting;

  /// No description provided for @joinSignalGroup.
  ///
  /// In en, this message translates to:
  /// **'Join Signal Group'**
  String get joinSignalGroup;

  /// No description provided for @examPaper.
  ///
  /// In en, this message translates to:
  /// **'Exam Paper'**
  String get examPaper;

  /// No description provided for @answered.
  ///
  /// In en, this message translates to:
  /// **'Answered'**
  String get answered;

  /// No description provided for @autoSavedSmartExam.
  ///
  /// In en, this message translates to:
  /// **'Auto Saved • Smart Exam'**
  String get autoSavedSmartExam;

  /// No description provided for @descriptiveQuestion.
  ///
  /// In en, this message translates to:
  /// **'Descriptive'**
  String get descriptiveQuestion;

  /// No description provided for @multipleChoiceQuestion.
  ///
  /// In en, this message translates to:
  /// **'Multiple Choice'**
  String get multipleChoiceQuestion;

  /// No description provided for @writeDescriptiveAnswer.
  ///
  /// In en, this message translates to:
  /// **'Write your descriptive answer here...'**
  String get writeDescriptiveAnswer;

  /// No description provided for @submitExam.
  ///
  /// In en, this message translates to:
  /// **'Submit Exam'**
  String get submitExam;

  /// No description provided for @confirmSubmitExam.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to submit your exam answers?'**
  String get confirmSubmitExam;

  /// No description provided for @examSubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Exam submitted successfully! Results will be reviewed by faculty.'**
  String get examSubmittedSuccess;

  /// No description provided for @timeRemaining.
  ///
  /// In en, this message translates to:
  /// **'Time Remaining'**
  String get timeRemaining;

  /// No description provided for @liveSupport.
  ///
  /// In en, this message translates to:
  /// **'Live Support'**
  String get liveSupport;

  /// No description provided for @createTicket.
  ///
  /// In en, this message translates to:
  /// **'Create Ticket'**
  String get createTicket;

  /// No description provided for @activeTickets.
  ///
  /// In en, this message translates to:
  /// **'Active Tickets'**
  String get activeTickets;

  /// No description provided for @pendingTickets.
  ///
  /// In en, this message translates to:
  /// **'Pending Tickets'**
  String get pendingTickets;

  /// No description provided for @closedTickets.
  ///
  /// In en, this message translates to:
  /// **'Closed Tickets'**
  String get closedTickets;

  /// No description provided for @noTicketsFound.
  ///
  /// In en, this message translates to:
  /// **'No support tickets found.'**
  String get noTicketsFound;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @weeks.
  ///
  /// In en, this message translates to:
  /// **'Weeks'**
  String get weeks;

  /// No description provided for @aboutCourse.
  ///
  /// In en, this message translates to:
  /// **'About Masterclass'**
  String get aboutCourse;

  /// No description provided for @meetInstructors.
  ///
  /// In en, this message translates to:
  /// **'Meet Your Instructors'**
  String get meetInstructors;

  /// No description provided for @reserveSeatAndClass.
  ///
  /// In en, this message translates to:
  /// **'Reserve Your Seat & Class'**
  String get reserveSeatAndClass;

  /// No description provided for @closeRegistrationForm.
  ///
  /// In en, this message translates to:
  /// **'Close Registration Form'**
  String get closeRegistrationForm;

  /// No description provided for @secureRegistrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Secure Registration & Schedule'**
  String get secureRegistrationTitle;

  /// No description provided for @secureRegistrationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fill out your details to finalize enrollment and class timing.'**
  String get secureRegistrationSubtitle;

  /// No description provided for @fullNameField.
  ///
  /// In en, this message translates to:
  /// **'FULL NAME *'**
  String get fullNameField;

  /// No description provided for @fatherNameField.
  ///
  /// In en, this message translates to:
  /// **'FATHER\'\'S NAME *'**
  String get fatherNameField;

  /// No description provided for @emailAddressField.
  ///
  /// In en, this message translates to:
  /// **'EMAIL ADDRESS *'**
  String get emailAddressField;

  /// No description provided for @whatsappNumberField.
  ///
  /// In en, this message translates to:
  /// **'WHATSAPP NUMBER *'**
  String get whatsappNumberField;

  /// No description provided for @preferredInstructor.
  ///
  /// In en, this message translates to:
  /// **'PREFERRED INSTRUCTOR *'**
  String get preferredInstructor;

  /// No description provided for @selectClassSchedule.
  ///
  /// In en, this message translates to:
  /// **'SELECT CLASS & SCHEDULE *'**
  String get selectClassSchedule;

  /// No description provided for @noActiveSchedule.
  ///
  /// In en, this message translates to:
  /// **'No active class schedule listed. Please register and support will contact you to set up a new cohort.'**
  String get noActiveSchedule;

  /// No description provided for @additionalNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'ADDITIONAL NOTES (OPTIONAL)'**
  String get additionalNotesOptional;

  /// No description provided for @finalizeRegistration.
  ///
  /// In en, this message translates to:
  /// **'Finalize Registration'**
  String get finalizeRegistration;

  /// No description provided for @registrationSuccess.
  ///
  /// In en, this message translates to:
  /// **'Registration & Seat Reservation Successful! 🎉'**
  String get registrationSuccess;

  /// No description provided for @fillRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all required fields.'**
  String get fillRequiredFields;

  /// No description provided for @authRequired.
  ///
  /// In en, this message translates to:
  /// **'Authentication required. Please login first.'**
  String get authRequired;

  /// No description provided for @enrollmentError.
  ///
  /// In en, this message translates to:
  /// **'You are already enrolled or an error occurred.'**
  String get enrollmentError;

  /// No description provided for @courseLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Course master link copied to clipboard! 🔗'**
  String get courseLinkCopied;

  /// No description provided for @courseNotFound.
  ///
  /// In en, this message translates to:
  /// **'Course not found.'**
  String get courseNotFound;

  /// No description provided for @loadingCourseDetails.
  ///
  /// In en, this message translates to:
  /// **'LOADING COURSE DETAILS...'**
  String get loadingCourseDetails;

  /// No description provided for @classSpecifications.
  ///
  /// In en, this message translates to:
  /// **'Class Specifications'**
  String get classSpecifications;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @classTime.
  ///
  /// In en, this message translates to:
  /// **'Class Time'**
  String get classTime;

  /// No description provided for @classDays.
  ///
  /// In en, this message translates to:
  /// **'Class Days'**
  String get classDays;

  /// No description provided for @accessChannels.
  ///
  /// In en, this message translates to:
  /// **'Access Channels'**
  String get accessChannels;

  /// No description provided for @joinTeamsLectureRoom.
  ///
  /// In en, this message translates to:
  /// **'Join Teams Lecture Room'**
  String get joinTeamsLectureRoom;

  /// No description provided for @joinTeamsLectureRoomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect instantly to live corporate session'**
  String get joinTeamsLectureRoomSubtitle;

  /// No description provided for @openSignalEncryptedGroup.
  ///
  /// In en, this message translates to:
  /// **'Open Signal Encrypted Group'**
  String get openSignalEncryptedGroup;

  /// No description provided for @signalEncryptedGroupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Secure messaging & operational updates'**
  String get signalEncryptedGroupSubtitle;

  /// No description provided for @classLockedTuitionPending.
  ///
  /// In en, this message translates to:
  /// **'Class rooms and links are locked until tuition payment is verified by the administration.'**
  String get classLockedTuitionPending;

  /// No description provided for @preparingExamPaper.
  ///
  /// In en, this message translates to:
  /// **'PREPARING EXAM PAPER...'**
  String get preparingExamPaper;

  /// No description provided for @paperSubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Paper Submitted Successfully!'**
  String get paperSubmittedSuccess;

  /// No description provided for @paperSubmittedDesc.
  ///
  /// In en, this message translates to:
  /// **'Your answers have been saved. Your instructor will grade your exam soon.'**
  String get paperSubmittedDesc;

  /// No description provided for @returnToExamCenter.
  ///
  /// In en, this message translates to:
  /// **'Return to Exam Center'**
  String get returnToExamCenter;

  /// No description provided for @unansweredQuestions.
  ///
  /// In en, this message translates to:
  /// **'Unanswered Questions'**
  String get unansweredQuestions;

  /// No description provided for @unansweredWarning.
  ///
  /// In en, this message translates to:
  /// **'You have skipped questions! Are you sure you want to submit?'**
  String get unansweredWarning;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @pts.
  ///
  /// In en, this message translates to:
  /// **'Pts'**
  String get pts;

  /// No description provided for @submitExamPaper.
  ///
  /// In en, this message translates to:
  /// **'SUBMIT EXAM PAPER 🚀'**
  String get submitExamPaper;

  /// No description provided for @recentConversations.
  ///
  /// In en, this message translates to:
  /// **'Recent Conversations'**
  String get recentConversations;

  /// No description provided for @noConversationsYet.
  ///
  /// In en, this message translates to:
  /// **'No Conversations Yet'**
  String get noConversationsYet;

  /// No description provided for @startLiveChatHint.
  ///
  /// In en, this message translates to:
  /// **'Click the banner above to start a live chat.'**
  String get startLiveChatHint;

  /// No description provided for @liveSupportAgent.
  ///
  /// In en, this message translates to:
  /// **'Live Support Agent'**
  String get liveSupportAgent;

  /// No description provided for @aiAndHumanOnline.
  ///
  /// In en, this message translates to:
  /// **'AI & Human Agents are online'**
  String get aiAndHumanOnline;

  /// No description provided for @startConversation.
  ///
  /// In en, this message translates to:
  /// **'Start conversation 💬'**
  String get startConversation;

  /// No description provided for @inConversation.
  ///
  /// In en, this message translates to:
  /// **'In Conversation'**
  String get inConversation;

  /// No description provided for @femaleVoice.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get femaleVoice;

  /// No description provided for @maleVoice.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get maleVoice;

  /// No description provided for @femalePartner.
  ///
  /// In en, this message translates to:
  /// **'Female Companion'**
  String get femalePartner;

  /// No description provided for @malePartner.
  ///
  /// In en, this message translates to:
  /// **'Male Companion'**
  String get malePartner;

  /// No description provided for @selectVoiceCharacter.
  ///
  /// In en, this message translates to:
  /// **'Select Voice Companion'**
  String get selectVoiceCharacter;

  /// No description provided for @selectVoiceCharacterDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose a female or male persona with unique vocal tone'**
  String get selectVoiceCharacterDesc;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @accessRestricted.
  ///
  /// In en, this message translates to:
  /// **'Access Restricted'**
  String get accessRestricted;

  /// No description provided for @journalRestrictedDesc.
  ///
  /// In en, this message translates to:
  /// **'The Professional Trading Journal is an exclusive tool reserved strictly for students enrolled in the Financial Markets & Forex Trading masterclass.'**
  String get journalRestrictedDesc;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'NEW CHAT'**
  String get newChat;

  /// No description provided for @waitingForAdmin.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Admin'**
  String get waitingForAdmin;

  /// No description provided for @aiSupportActive.
  ///
  /// In en, this message translates to:
  /// **'AI Support Active'**
  String get aiSupportActive;

  /// No description provided for @ticketClosed.
  ///
  /// In en, this message translates to:
  /// **'Ticket Closed'**
  String get ticketClosed;

  /// No description provided for @messageAdmin.
  ///
  /// In en, this message translates to:
  /// **'Message Admin...'**
  String get messageAdmin;

  /// No description provided for @askSafiAi.
  ///
  /// In en, this message translates to:
  /// **'Ask ZEV AI...'**
  String get askSafiAi;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get uploading;

  /// No description provided for @aiTyping.
  ///
  /// In en, this message translates to:
  /// **'ZEV AI is typing...'**
  String get aiTyping;

  /// No description provided for @documentAttached.
  ///
  /// In en, this message translates to:
  /// **'Document Attached'**
  String get documentAttached;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'SEND RESET LINK'**
  String get sendResetLink;

  /// No description provided for @checkYourInbox.
  ///
  /// In en, this message translates to:
  /// **'Check Your Inbox'**
  String get checkYourInbox;

  /// No description provided for @checkSpamFolder.
  ///
  /// In en, this message translates to:
  /// **'Please also check your Spam or Junk folder.'**
  String get checkSpamFolder;

  /// No description provided for @securityVerification.
  ///
  /// In en, this message translates to:
  /// **'Security Verification'**
  String get securityVerification;

  /// No description provided for @enter4DigitPin.
  ///
  /// In en, this message translates to:
  /// **'Enter your 4-digit PIN to continue'**
  String get enter4DigitPin;

  /// No description provided for @incorrectPin.
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN Code ❌'**
  String get incorrectPin;

  /// No description provided for @nextStep.
  ///
  /// In en, this message translates to:
  /// **'NEXT STEP'**
  String get nextStep;

  /// No description provided for @completeRegistration.
  ///
  /// In en, this message translates to:
  /// **'COMPLETE 🚀'**
  String get completeRegistration;

  /// No description provided for @verifyYourIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify Your Identity'**
  String get verifyYourIdentity;

  /// No description provided for @verificationLinkSent.
  ///
  /// In en, this message translates to:
  /// **'We\'\'ve sent a secure verification link to your email address:'**
  String get verificationLinkSent;

  /// No description provided for @proceedToLogin.
  ///
  /// In en, this message translates to:
  /// **'PROCEED TO LOGIN'**
  String get proceedToLogin;

  /// No description provided for @clickLinkInEmail.
  ///
  /// In en, this message translates to:
  /// **'Please open your email and click on the verification button.'**
  String get clickLinkInEmail;

  /// No description provided for @friendRequirementNotice.
  ///
  /// In en, this message translates to:
  /// **'You must first become friends with this user to send them direct messages.'**
  String get friendRequirementNotice;

  /// No description provided for @sendFriendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send Friend Request'**
  String get sendFriendRequest;

  /// No description provided for @friendRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent successfully! 🤝'**
  String get friendRequestSent;

  /// No description provided for @friendRequestError.
  ///
  /// In en, this message translates to:
  /// **'Friend request already sent or an error occurred.'**
  String get friendRequestError;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @replyingTo.
  ///
  /// In en, this message translates to:
  /// **'Replying to'**
  String get replyingTo;

  /// No description provided for @yourself.
  ///
  /// In en, this message translates to:
  /// **'yourself'**
  String get yourself;

  /// No description provided for @onlineNow.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
  String get onlineNow;

  /// No description provided for @educationalReel.
  ///
  /// In en, this message translates to:
  /// **'Reels 🎬'**
  String get educationalReel;

  /// No description provided for @checkOutReel.
  ///
  /// In en, this message translates to:
  /// **'Check out this reel! 🌟'**
  String get checkOutReel;

  /// No description provided for @watchReel.
  ///
  /// In en, this message translates to:
  /// **'Watch Reel 🎥'**
  String get watchReel;

  /// No description provided for @sponsored.
  ///
  /// In en, this message translates to:
  /// **'Sponsored'**
  String get sponsored;

  /// No description provided for @learnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn More'**
  String get learnMore;

  /// No description provided for @installNow.
  ///
  /// In en, this message translates to:
  /// **'Install Now'**
  String get installNow;

  /// No description provided for @swipeUpForNextReel.
  ///
  /// In en, this message translates to:
  /// **'Swipe up for next Reel'**
  String get swipeUpForNextReel;

  /// No description provided for @activityAndNotifications.
  ///
  /// In en, this message translates to:
  /// **'Activity & Notifications'**
  String get activityAndNotifications;

  /// No description provided for @allActivities.
  ///
  /// In en, this message translates to:
  /// **'All 🔥'**
  String get allActivities;

  /// No description provided for @likesAndComments.
  ///
  /// In en, this message translates to:
  /// **'Likes & Comments ❤️'**
  String get likesAndComments;

  /// No description provided for @friendRequests.
  ///
  /// In en, this message translates to:
  /// **'Friend Requests 👥'**
  String get friendRequests;

  /// No description provided for @noActivitiesYet.
  ///
  /// In en, this message translates to:
  /// **'No activities yet'**
  String get noActivitiesYet;

  /// No description provided for @activitiesEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'New likes, comments, and friend requests will appear here.'**
  String get activitiesEmptyDesc;

  /// No description provided for @postNotFound.
  ///
  /// In en, this message translates to:
  /// **'Post not found'**
  String get postNotFound;

  /// No description provided for @postedOnFeed.
  ///
  /// In en, this message translates to:
  /// **'Posted on Feed'**
  String get postedOnFeed;

  /// No description provided for @commentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Comments 💬'**
  String get commentsTitle;

  /// No description provided for @noCommentsYet.
  ///
  /// In en, this message translates to:
  /// **'No comments yet. Write one below!'**
  String get noCommentsYet;

  /// No description provided for @addComment.
  ///
  /// In en, this message translates to:
  /// **'Add a comment...'**
  String get addComment;

  /// No description provided for @studentNetwork.
  ///
  /// In en, this message translates to:
  /// **'Student Network'**
  String get studentNetwork;

  /// No description provided for @studentNetworkDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect, collaborate, and grow your professional network.'**
  String get studentNetworkDesc;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// No description provided for @searchByNameOrEmail.
  ///
  /// In en, this message translates to:
  /// **'Search by name or email...'**
  String get searchByNameOrEmail;

  /// No description provided for @removeFriend.
  ///
  /// In en, this message translates to:
  /// **'Remove Friend'**
  String get removeFriend;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @noStudentsFound.
  ///
  /// In en, this message translates to:
  /// **'No students found here.'**
  String get noStudentsFound;

  /// No description provided for @story24hNotice.
  ///
  /// In en, this message translates to:
  /// **'Your story will automatically disappear after 24 hours.'**
  String get story24hNotice;

  /// No description provided for @storyPublishedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your 24-hour story has been published successfully! 🎉'**
  String get storyPublishedSuccess;

  /// No description provided for @publishReel.
  ///
  /// In en, this message translates to:
  /// **'Publish Reel'**
  String get publishReel;

  /// No description provided for @reelPublishedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Reel published successfully! 🎉'**
  String get reelPublishedSuccess;

  /// No description provided for @postPublishedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Post published successfully! 🎉'**
  String get postPublishedSuccess;

  /// No description provided for @chooseMediaFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Select media from gallery 📸'**
  String get chooseMediaFromGallery;

  /// No description provided for @mediaUploaded.
  ///
  /// In en, this message translates to:
  /// **'Media uploaded! ✅'**
  String get mediaUploaded;

  /// No description provided for @reelTitle.
  ///
  /// In en, this message translates to:
  /// **'Reel Title'**
  String get reelTitle;

  /// No description provided for @publish.
  ///
  /// In en, this message translates to:
  /// **'PUBLISH'**
  String get publish;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (Optional)'**
  String get descriptionOptional;

  /// No description provided for @selectVideo.
  ///
  /// In en, this message translates to:
  /// **'Tap to select a Reel video 📹'**
  String get selectVideo;

  /// No description provided for @videoReadyToPublish.
  ///
  /// In en, this message translates to:
  /// **'Video ready to publish! 🎬'**
  String get videoReadyToPublish;

  /// No description provided for @chatInputHint.
  ///
  /// In en, this message translates to:
  /// **'Write a message...'**
  String get chatInputHint;

  /// No description provided for @certificateCode.
  ///
  /// In en, this message translates to:
  /// **'Certificate Code'**
  String get certificateCode;

  /// No description provided for @issueDate.
  ///
  /// In en, this message translates to:
  /// **'Issue Date'**
  String get issueDate;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetails;

  /// No description provided for @teacherPortal.
  ///
  /// In en, this message translates to:
  /// **'Teacher Portal'**
  String get teacherPortal;

  /// No description provided for @teacherOverview.
  ///
  /// In en, this message translates to:
  /// **'Teacher Overview'**
  String get teacherOverview;

  /// No description provided for @myStudents.
  ///
  /// In en, this message translates to:
  /// **'My Students'**
  String get myStudents;

  /// No description provided for @allStudents.
  ///
  /// In en, this message translates to:
  /// **'All Students'**
  String get allStudents;

  /// No description provided for @curriculum.
  ///
  /// In en, this message translates to:
  /// **'Curriculum'**
  String get curriculum;

  /// No description provided for @createCourse.
  ///
  /// In en, this message translates to:
  /// **'Create Course'**
  String get createCourse;

  /// No description provided for @editCourse.
  ///
  /// In en, this message translates to:
  /// **'Edit Course'**
  String get editCourse;

  /// No description provided for @courseDetails.
  ///
  /// In en, this message translates to:
  /// **'Course Details'**
  String get courseDetails;

  /// No description provided for @createClass.
  ///
  /// In en, this message translates to:
  /// **'Create Class'**
  String get createClass;

  /// No description provided for @editClass.
  ///
  /// In en, this message translates to:
  /// **'Edit Class'**
  String get editClass;

  /// No description provided for @classDetails.
  ///
  /// In en, this message translates to:
  /// **'Class Details'**
  String get classDetails;

  /// No description provided for @createAssignment.
  ///
  /// In en, this message translates to:
  /// **'Create Assignment'**
  String get createAssignment;

  /// No description provided for @editAssignment.
  ///
  /// In en, this message translates to:
  /// **'Edit Assignment'**
  String get editAssignment;

  /// No description provided for @assignmentDetails.
  ///
  /// In en, this message translates to:
  /// **'Assignment Details'**
  String get assignmentDetails;

  /// No description provided for @submissions.
  ///
  /// In en, this message translates to:
  /// **'Submissions'**
  String get submissions;

  /// No description provided for @gradeSubmission.
  ///
  /// In en, this message translates to:
  /// **'Grade Submission'**
  String get gradeSubmission;

  /// No description provided for @createQuiz.
  ///
  /// In en, this message translates to:
  /// **'Create Quiz'**
  String get createQuiz;

  /// No description provided for @editQuiz.
  ///
  /// In en, this message translates to:
  /// **'Edit Quiz'**
  String get editQuiz;

  /// No description provided for @quizQuestions.
  ///
  /// In en, this message translates to:
  /// **'Quiz Questions'**
  String get quizQuestions;

  /// No description provided for @quizResults.
  ///
  /// In en, this message translates to:
  /// **'Quiz Results'**
  String get quizResults;

  /// No description provided for @addStudent.
  ///
  /// In en, this message translates to:
  /// **'Add Student'**
  String get addStudent;

  /// No description provided for @removeStudent.
  ///
  /// In en, this message translates to:
  /// **'Remove Student'**
  String get removeStudent;

  /// No description provided for @teacherReports.
  ///
  /// In en, this message translates to:
  /// **'Teacher Reports'**
  String get teacherReports;

  /// No description provided for @adminPortal.
  ///
  /// In en, this message translates to:
  /// **'Admin Portal'**
  String get adminPortal;

  /// No description provided for @adminDashboard.
  ///
  /// In en, this message translates to:
  /// **'Admin Dashboard'**
  String get adminDashboard;

  /// No description provided for @manageStudents.
  ///
  /// In en, this message translates to:
  /// **'Manage Students'**
  String get manageStudents;

  /// No description provided for @manageTeachers.
  ///
  /// In en, this message translates to:
  /// **'Manage Teachers'**
  String get manageTeachers;

  /// No description provided for @manageCourses.
  ///
  /// In en, this message translates to:
  /// **'Manage Courses'**
  String get manageCourses;

  /// No description provided for @manageClasses.
  ///
  /// In en, this message translates to:
  /// **'Manage Classes'**
  String get manageClasses;

  /// No description provided for @finance.
  ///
  /// In en, this message translates to:
  /// **'Finance & Invoices'**
  String get finance;

  /// No description provided for @honorsAwards.
  ///
  /// In en, this message translates to:
  /// **'Honors & Awards'**
  String get honorsAwards;

  /// No description provided for @supportRequests.
  ///
  /// In en, this message translates to:
  /// **'Support Requests'**
  String get supportRequests;

  /// No description provided for @liveStudio.
  ///
  /// In en, this message translates to:
  /// **'Live Studio'**
  String get liveStudio;

  /// No description provided for @revenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get revenue;

  /// No description provided for @totalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total Revenue'**
  String get totalRevenue;

  /// No description provided for @totalStudents.
  ///
  /// In en, this message translates to:
  /// **'Total Students'**
  String get totalStudents;

  /// No description provided for @totalTeachers.
  ///
  /// In en, this message translates to:
  /// **'Total Teachers'**
  String get totalTeachers;

  /// No description provided for @totalCourses.
  ///
  /// In en, this message translates to:
  /// **'Total Courses'**
  String get totalCourses;

  /// No description provided for @totalClasses.
  ///
  /// In en, this message translates to:
  /// **'Total Classes'**
  String get totalClasses;

  /// No description provided for @pendingApprovals.
  ///
  /// In en, this message translates to:
  /// **'Pending Approvals'**
  String get pendingApprovals;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @action.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get action;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @grade.
  ///
  /// In en, this message translates to:
  /// **'Grade'**
  String get grade;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get dueDate;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @capacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get capacity;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start Date'**
  String get startDate;

  /// No description provided for @endDate.
  ///
  /// In en, this message translates to:
  /// **'End Date'**
  String get endDate;

  /// No description provided for @startTime.
  ///
  /// In en, this message translates to:
  /// **'Start Time'**
  String get startTime;

  /// No description provided for @endTime.
  ///
  /// In en, this message translates to:
  /// **'End Time'**
  String get endTime;

  /// No description provided for @meetingLink.
  ///
  /// In en, this message translates to:
  /// **'Meeting Link'**
  String get meetingLink;

  /// No description provided for @joinClass.
  ///
  /// In en, this message translates to:
  /// **'Join Class'**
  String get joinClass;

  /// No description provided for @startClass.
  ///
  /// In en, this message translates to:
  /// **'Start Class'**
  String get startClass;

  /// No description provided for @endClass.
  ///
  /// In en, this message translates to:
  /// **'End Class'**
  String get endClass;

  /// No description provided for @noDataFound.
  ///
  /// In en, this message translates to:
  /// **'No data found'**
  String get noDataFound;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this?'**
  String get confirmDelete;

  /// No description provided for @confirmAction.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get confirmAction;

  /// No description provided for @itemCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Created successfully'**
  String get itemCreatedSuccessfully;

  /// No description provided for @itemUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Updated successfully'**
  String get itemUpdatedSuccessfully;

  /// No description provided for @itemDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Deleted successfully'**
  String get itemDeletedSuccessfully;

  /// No description provided for @teacherNotice.
  ///
  /// In en, this message translates to:
  /// **'Teacher Notice'**
  String get teacherNotice;

  /// No description provided for @adminNotice.
  ///
  /// In en, this message translates to:
  /// **'Admin Notice'**
  String get adminNotice;

  /// No description provided for @sendAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Send Announcement'**
  String get sendAnnouncement;

  /// No description provided for @announcementTitle.
  ///
  /// In en, this message translates to:
  /// **'Announcement Title'**
  String get announcementTitle;

  /// No description provided for @announcementBody.
  ///
  /// In en, this message translates to:
  /// **'Announcement Body'**
  String get announcementBody;

  /// No description provided for @targetAudience.
  ///
  /// In en, this message translates to:
  /// **'Target Audience'**
  String get targetAudience;

  /// No description provided for @allUsers.
  ///
  /// In en, this message translates to:
  /// **'All Users'**
  String get allUsers;

  /// No description provided for @onlyStudents.
  ///
  /// In en, this message translates to:
  /// **'Only Students'**
  String get onlyStudents;

  /// No description provided for @onlyTeachers.
  ///
  /// In en, this message translates to:
  /// **'Only Teachers'**
  String get onlyTeachers;

  /// No description provided for @supportChatWithAdmin.
  ///
  /// In en, this message translates to:
  /// **'Support Chat with Admin'**
  String get supportChatWithAdmin;

  /// No description provided for @ticketStatus.
  ///
  /// In en, this message translates to:
  /// **'Ticket Status'**
  String get ticketStatus;

  /// No description provided for @openTickets.
  ///
  /// In en, this message translates to:
  /// **'Open Tickets'**
  String get openTickets;

  /// No description provided for @closeTicket.
  ///
  /// In en, this message translates to:
  /// **'Close Ticket'**
  String get closeTicket;

  /// No description provided for @sendReply.
  ///
  /// In en, this message translates to:
  /// **'Send Reply'**
  String get sendReply;

  /// No description provided for @awardTitle.
  ///
  /// In en, this message translates to:
  /// **'Award Title'**
  String get awardTitle;

  /// No description provided for @giveAward.
  ///
  /// In en, this message translates to:
  /// **'Grant Award'**
  String get giveAward;

  /// No description provided for @awardedTo.
  ///
  /// In en, this message translates to:
  /// **'Awarded To'**
  String get awardedTo;

  /// No description provided for @studentName.
  ///
  /// In en, this message translates to:
  /// **'Student Name'**
  String get studentName;

  /// No description provided for @teacherName.
  ///
  /// In en, this message translates to:
  /// **'Teacher Name'**
  String get teacherName;

  /// No description provided for @courseName.
  ///
  /// In en, this message translates to:
  /// **'Course Name'**
  String get courseName;

  /// No description provided for @className.
  ///
  /// In en, this message translates to:
  /// **'Class Name'**
  String get className;

  /// No description provided for @addStudentToClass.
  ///
  /// In en, this message translates to:
  /// **'Add Student to Class'**
  String get addStudentToClass;

  /// No description provided for @facultyAndNetwork.
  ///
  /// In en, this message translates to:
  /// **'Faculty & Network'**
  String get facultyAndNetwork;

  /// No description provided for @educationalReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get educationalReels;

  /// No description provided for @honors.
  ///
  /// In en, this message translates to:
  /// **'Honors'**
  String get honors;

  /// No description provided for @academyFeed.
  ///
  /// In en, this message translates to:
  /// **'ZEV Feed'**
  String get academyFeed;

  /// No description provided for @facultyNetwork.
  ///
  /// In en, this message translates to:
  /// **'Faculty & Network'**
  String get facultyNetwork;

  /// No description provided for @supportChat.
  ///
  /// In en, this message translates to:
  /// **'Support Chat'**
  String get supportChat;

  /// No description provided for @instructorProfile.
  ///
  /// In en, this message translates to:
  /// **'Instructor Profile'**
  String get instructorProfile;

  /// No description provided for @adminProfile.
  ///
  /// In en, this message translates to:
  /// **'Admin Profile'**
  String get adminProfile;

  /// No description provided for @totalVolume.
  ///
  /// In en, this message translates to:
  /// **'Total Volume'**
  String get totalVolume;

  /// No description provided for @published.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get published;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @courseTitle.
  ///
  /// In en, this message translates to:
  /// **'Course Title'**
  String get courseTitle;

  /// No description provided for @courseDescription.
  ///
  /// In en, this message translates to:
  /// **'Course Description'**
  String get courseDescription;

  /// No description provided for @primaryInstructor.
  ///
  /// In en, this message translates to:
  /// **'Primary Instructor'**
  String get primaryInstructor;

  /// No description provided for @coInstructor.
  ///
  /// In en, this message translates to:
  /// **'Co-Instructor'**
  String get coInstructor;

  /// No description provided for @selectCoInstructor.
  ///
  /// In en, this message translates to:
  /// **'Select Co-Instructor'**
  String get selectCoInstructor;

  /// No description provided for @runCourseSolo.
  ///
  /// In en, this message translates to:
  /// **'Run course solo'**
  String get runCourseSolo;

  /// No description provided for @courseThumbnail.
  ///
  /// In en, this message translates to:
  /// **'Course Thumbnail'**
  String get courseThumbnail;

  /// No description provided for @publishCourse.
  ///
  /// In en, this message translates to:
  /// **'Publish Course'**
  String get publishCourse;

  /// No description provided for @makeVisibleToStudents.
  ///
  /// In en, this message translates to:
  /// **'Make visible to ZEV community'**
  String get makeVisibleToStudents;

  /// No description provided for @creatingCourse.
  ///
  /// In en, this message translates to:
  /// **'Compiling Course...'**
  String get creatingCourse;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @addLesson.
  ///
  /// In en, this message translates to:
  /// **'Add Lesson'**
  String get addLesson;

  /// No description provided for @lessonTitle.
  ///
  /// In en, this message translates to:
  /// **'Lesson Title'**
  String get lessonTitle;

  /// No description provided for @lessonDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get lessonDuration;

  /// No description provided for @videoUrl.
  ///
  /// In en, this message translates to:
  /// **'Video URL'**
  String get videoUrl;

  /// No description provided for @liveClasses.
  ///
  /// In en, this message translates to:
  /// **'Live Classes'**
  String get liveClasses;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @totalEarnings.
  ///
  /// In en, this message translates to:
  /// **'Total Earnings'**
  String get totalEarnings;

  /// No description provided for @activeStudents.
  ///
  /// In en, this message translates to:
  /// **'Active Students'**
  String get activeStudents;

  /// No description provided for @activeCourses.
  ///
  /// In en, this message translates to:
  /// **'Active Courses'**
  String get activeCourses;

  /// No description provided for @activeClasses.
  ///
  /// In en, this message translates to:
  /// **'Active Classes'**
  String get activeClasses;

  /// No description provided for @question.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get question;

  /// No description provided for @progress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progress;

  /// No description provided for @payout.
  ///
  /// In en, this message translates to:
  /// **'Payout'**
  String get payout;

  /// No description provided for @analytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analytics;

  /// No description provided for @classes.
  ///
  /// In en, this message translates to:
  /// **'Classes'**
  String get classes;

  /// No description provided for @students.
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get students;

  /// No description provided for @questionBank.
  ///
  /// In en, this message translates to:
  /// **'Question Bank'**
  String get questionBank;

  /// No description provided for @addNewQuestion.
  ///
  /// In en, this message translates to:
  /// **'Add New Question'**
  String get addNewQuestion;

  /// No description provided for @multipleChoice.
  ///
  /// In en, this message translates to:
  /// **'Multiple Choice (4 Options)'**
  String get multipleChoice;

  /// No description provided for @descriptive.
  ///
  /// In en, this message translates to:
  /// **'Descriptive (Written)'**
  String get descriptive;

  /// No description provided for @enterQuestionText.
  ///
  /// In en, this message translates to:
  /// **'Enter question text...'**
  String get enterQuestionText;

  /// No description provided for @optionA.
  ///
  /// In en, this message translates to:
  /// **'Option A'**
  String get optionA;

  /// No description provided for @optionB.
  ///
  /// In en, this message translates to:
  /// **'Option B'**
  String get optionB;

  /// No description provided for @optionC.
  ///
  /// In en, this message translates to:
  /// **'Option C'**
  String get optionC;

  /// No description provided for @optionD.
  ///
  /// In en, this message translates to:
  /// **'Option D'**
  String get optionD;

  /// No description provided for @correctOption.
  ///
  /// In en, this message translates to:
  /// **'Correct Option'**
  String get correctOption;

  /// No description provided for @saveQuestion.
  ///
  /// In en, this message translates to:
  /// **'Save Question'**
  String get saveQuestion;

  /// No description provided for @currentInventory.
  ///
  /// In en, this message translates to:
  /// **'Current Inventory'**
  String get currentInventory;

  /// No description provided for @noQuestionsAdded.
  ///
  /// In en, this message translates to:
  /// **'No questions added yet.'**
  String get noQuestionsAdded;

  /// No description provided for @totalQuestions.
  ///
  /// In en, this message translates to:
  /// **'Total Questions'**
  String get totalQuestions;

  /// No description provided for @totalPoints.
  ///
  /// In en, this message translates to:
  /// **'Total Points'**
  String get totalPoints;

  /// No description provided for @studentSubmissions.
  ///
  /// In en, this message translates to:
  /// **'Student Submissions'**
  String get studentSubmissions;

  /// No description provided for @pendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending Review'**
  String get pendingReview;

  /// No description provided for @evaluate.
  ///
  /// In en, this message translates to:
  /// **'Evaluate'**
  String get evaluate;

  /// No description provided for @submitGrade.
  ///
  /// In en, this message translates to:
  /// **'Submit Grade'**
  String get submitGrade;

  /// No description provided for @studentAnswer.
  ///
  /// In en, this message translates to:
  /// **'Student Answer'**
  String get studentAnswer;

  /// No description provided for @teacherEvaluation.
  ///
  /// In en, this message translates to:
  /// **'Teacher Evaluation'**
  String get teacherEvaluation;

  /// No description provided for @autoGraded.
  ///
  /// In en, this message translates to:
  /// **'Auto Graded (MCQ)'**
  String get autoGraded;

  /// No description provided for @noSubmissionsFound.
  ///
  /// In en, this message translates to:
  /// **'No submissions found.'**
  String get noSubmissionsFound;

  /// No description provided for @gradesSubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Grades and feedback submitted successfully!'**
  String get gradesSubmittedSuccess;

  /// No description provided for @tradeDate.
  ///
  /// In en, this message translates to:
  /// **'Trade Date'**
  String get tradeDate;

  /// No description provided for @symbol.
  ///
  /// In en, this message translates to:
  /// **'Symbol'**
  String get symbol;

  /// No description provided for @positionType.
  ///
  /// In en, this message translates to:
  /// **'Position Type'**
  String get positionType;

  /// No description provided for @entryPrice.
  ///
  /// In en, this message translates to:
  /// **'Entry Price'**
  String get entryPrice;

  /// No description provided for @exitPrice.
  ///
  /// In en, this message translates to:
  /// **'Exit Price'**
  String get exitPrice;

  /// No description provided for @stopLoss.
  ///
  /// In en, this message translates to:
  /// **'Stop Loss'**
  String get stopLoss;

  /// No description provided for @takeProfit.
  ///
  /// In en, this message translates to:
  /// **'Take Profit'**
  String get takeProfit;

  /// No description provided for @lotSize.
  ///
  /// In en, this message translates to:
  /// **'Lot Size'**
  String get lotSize;

  /// No description provided for @profitLoss.
  ///
  /// In en, this message translates to:
  /// **'Profit / Loss'**
  String get profitLoss;

  /// No description provided for @riskReward.
  ///
  /// In en, this message translates to:
  /// **'Risk / Reward'**
  String get riskReward;

  /// No description provided for @strategy.
  ///
  /// In en, this message translates to:
  /// **'Strategy'**
  String get strategy;

  /// No description provided for @emotions.
  ///
  /// In en, this message translates to:
  /// **'Emotions'**
  String get emotions;

  /// No description provided for @chartImage.
  ///
  /// In en, this message translates to:
  /// **'Chart Image'**
  String get chartImage;

  /// No description provided for @teacherScore.
  ///
  /// In en, this message translates to:
  /// **'Teacher Score'**
  String get teacherScore;

  /// No description provided for @teacherFeedback.
  ///
  /// In en, this message translates to:
  /// **'Teacher Feedback'**
  String get teacherFeedback;

  /// No description provided for @gradeTrade.
  ///
  /// In en, this message translates to:
  /// **'Grade Trade'**
  String get gradeTrade;

  /// No description provided for @forexAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'Forex Course Access Required'**
  String get forexAccessRequired;

  /// No description provided for @noTradesFound.
  ///
  /// In en, this message translates to:
  /// **'No journal entries found.'**
  String get noTradesFound;

  /// No description provided for @grantAward.
  ///
  /// In en, this message translates to:
  /// **'Grant Award'**
  String get grantAward;

  /// No description provided for @awardGrantedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Award granted successfully!'**
  String get awardGrantedSuccess;

  /// No description provided for @selectStudent.
  ///
  /// In en, this message translates to:
  /// **'Select Student'**
  String get selectStudent;

  /// No description provided for @selectAward.
  ///
  /// In en, this message translates to:
  /// **'Select Award'**
  String get selectAward;

  /// No description provided for @pointsRequired.
  ///
  /// In en, this message translates to:
  /// **'Points Required'**
  String get pointsRequired;

  /// No description provided for @certificateDetails.
  ///
  /// In en, this message translates to:
  /// **'Certificate Details'**
  String get certificateDetails;

  /// No description provided for @verifyCertificate.
  ///
  /// In en, this message translates to:
  /// **'Verify Certificate'**
  String get verifyCertificate;

  /// No description provided for @certificateIssued.
  ///
  /// In en, this message translates to:
  /// **'Certificate Issued'**
  String get certificateIssued;

  /// No description provided for @noCertificatesFound.
  ///
  /// In en, this message translates to:
  /// **'No certificates found.'**
  String get noCertificatesFound;

  /// No description provided for @aboutUs.
  ///
  /// In en, this message translates to:
  /// **'About Us'**
  String get aboutUs;

  /// No description provided for @faq.
  ///
  /// In en, this message translates to:
  /// **'FAQ'**
  String get faq;

  /// No description provided for @personalInfo.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get personalInfo;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully!'**
  String get profileUpdated;

  /// No description provided for @systemStats.
  ///
  /// In en, this message translates to:
  /// **'System Statistics'**
  String get systemStats;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// No description provided for @addNewCourse.
  ///
  /// In en, this message translates to:
  /// **'Add New Course'**
  String get addNewCourse;

  /// No description provided for @addNewClass.
  ///
  /// In en, this message translates to:
  /// **'Add New Class'**
  String get addNewClass;

  /// No description provided for @addNewStudent.
  ///
  /// In en, this message translates to:
  /// **'Add New Student'**
  String get addNewStudent;

  /// No description provided for @addNewTeacher.
  ///
  /// In en, this message translates to:
  /// **'Add New Teacher'**
  String get addNewTeacher;

  /// No description provided for @coursePricing.
  ///
  /// In en, this message translates to:
  /// **'Course Pricing'**
  String get coursePricing;

  /// No description provided for @freeCourse.
  ///
  /// In en, this message translates to:
  /// **'Free Course'**
  String get freeCourse;

  /// No description provided for @paidCourse.
  ///
  /// In en, this message translates to:
  /// **'Paid Course'**
  String get paidCourse;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @assignTeacher.
  ///
  /// In en, this message translates to:
  /// **'Assign Teacher'**
  String get assignTeacher;

  /// No description provided for @selectClass.
  ///
  /// In en, this message translates to:
  /// **'Select Class'**
  String get selectClass;

  /// No description provided for @totalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get totalAmount;

  /// No description provided for @paymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Payment Status'**
  String get paymentStatus;

  /// No description provided for @paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// No description provided for @unpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get unpaid;

  /// No description provided for @invoiceId.
  ///
  /// In en, this message translates to:
  /// **'Invoice ID'**
  String get invoiceId;

  /// No description provided for @tickets.
  ///
  /// In en, this message translates to:
  /// **'Support Tickets'**
  String get tickets;

  /// No description provided for @ticketPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get ticketPriority;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @typeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type your message...'**
  String get typeMessage;

  /// No description provided for @option.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get option;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @aboutFacultyHelp.
  ///
  /// In en, this message translates to:
  /// **'About & Faculty Help'**
  String get aboutFacultyHelp;

  /// No description provided for @aboutFacultyHelpDesc.
  ///
  /// In en, this message translates to:
  /// **'ZEV instructor portal, guidelines, and official channels.'**
  String get aboutFacultyHelpDesc;

  /// No description provided for @aboutSafiAcademy.
  ///
  /// In en, this message translates to:
  /// **'About ZEV'**
  String get aboutSafiAcademy;

  /// No description provided for @teacherAboutWelcomeText.
  ///
  /// In en, this message translates to:
  /// **'Welcome to the ZEV Instructor Portal. As part of our elite faculty, your dedication shapes the future of global education, technical training, and professional trading expertise.\n\nUse this portal to manage your courses, grade student assignments, review assessments, and interact with students. For direct administration or technical assistance, you can reach out via our official communication channels below.'**
  String get teacherAboutWelcomeText;

  /// No description provided for @facultyEmail.
  ///
  /// In en, this message translates to:
  /// **'Faculty Email'**
  String get facultyEmail;

  /// No description provided for @managePreferencesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your app preferences, security, and credentials.'**
  String get managePreferencesSubtitle;

  /// No description provided for @enterNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter a strong password (min 6 chars)...'**
  String get enterNewPassword;

  /// No description provided for @errorChangingPassword.
  ///
  /// In en, this message translates to:
  /// **'Error changing password'**
  String get errorChangingPassword;

  /// No description provided for @faceOrTouchId.
  ///
  /// In en, this message translates to:
  /// **'Face ID or Touch ID'**
  String get faceOrTouchId;

  /// No description provided for @appPinLock.
  ///
  /// In en, this message translates to:
  /// **'App PIN Lock'**
  String get appPinLock;

  /// No description provided for @setAppPinLock.
  ///
  /// In en, this message translates to:
  /// **'Set App PIN Lock'**
  String get setAppPinLock;

  /// No description provided for @appPreferences.
  ///
  /// In en, this message translates to:
  /// **'App Preferences'**
  String get appPreferences;

  /// No description provided for @secureSignOut.
  ///
  /// In en, this message translates to:
  /// **'SECURE SIGN OUT'**
  String get secureSignOut;

  /// No description provided for @instructorProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your faculty identity, credentials, and professional bio.'**
  String get instructorProfileSubtitle;

  /// No description provided for @personalProfessionalIdentity.
  ///
  /// In en, this message translates to:
  /// **'Personal & Professional Identity'**
  String get personalProfessionalIdentity;

  /// No description provided for @avatarUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Profile picture updated successfully! ✅'**
  String get avatarUpdatedSuccess;

  /// No description provided for @avatarUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload avatar.'**
  String get avatarUploadFailed;

  /// No description provided for @instructorProfileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Instructor profile updated successfully! ✅'**
  String get instructorProfileUpdated;

  /// No description provided for @databaseSaveError.
  ///
  /// In en, this message translates to:
  /// **'Database error. Failed to save profile.'**
  String get databaseSaveError;

  /// No description provided for @countryRegion.
  ///
  /// In en, this message translates to:
  /// **'Country / Region'**
  String get countryRegion;

  /// No description provided for @professionalBio.
  ///
  /// In en, this message translates to:
  /// **'Professional Bio / Headline'**
  String get professionalBio;

  /// No description provided for @savingChanges.
  ///
  /// In en, this message translates to:
  /// **'SAVING CHANGES...'**
  String get savingChanges;

  /// No description provided for @saveProfileDetails.
  ///
  /// In en, this message translates to:
  /// **'SAVE PROFILE DETAILS 🚀'**
  String get saveProfileDetails;

  /// No description provided for @notProvided.
  ///
  /// In en, this message translates to:
  /// **'Not provided'**
  String get notProvided;

  /// No description provided for @taskDetailsAndAlert.
  ///
  /// In en, this message translates to:
  /// **'Task Details & Alert'**
  String get taskDetailsAndAlert;

  /// No description provided for @deleteTask.
  ///
  /// In en, this message translates to:
  /// **'Delete Task'**
  String get deleteTask;

  /// No description provided for @deleteTaskConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this task?'**
  String get deleteTaskConfirm;

  /// No description provided for @taskDeleted.
  ///
  /// In en, this message translates to:
  /// **'Task deleted.'**
  String get taskDeleted;

  /// No description provided for @taskOverdueAlert.
  ///
  /// In en, this message translates to:
  /// **'ALERT: This task is approaching its deadline or is overdue!'**
  String get taskOverdueAlert;

  /// No description provided for @taskInformation.
  ///
  /// In en, this message translates to:
  /// **'Task Information'**
  String get taskInformation;

  /// No description provided for @dueDateAndTime.
  ///
  /// In en, this message translates to:
  /// **'Due Date & Time'**
  String get dueDateAndTime;

  /// No description provided for @noDueDateSet.
  ///
  /// In en, this message translates to:
  /// **'No due date set (Click to set)'**
  String get noDueDateSet;

  /// No description provided for @markAsCompleted.
  ///
  /// In en, this message translates to:
  /// **'Mark as Completed'**
  String get markAsCompleted;

  /// No description provided for @createdAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Created At'**
  String get createdAtLabel;

  /// No description provided for @updateTaskBtn.
  ///
  /// In en, this message translates to:
  /// **'UPDATE TASK 💾'**
  String get updateTaskBtn;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @allFieldsRequired.
  ///
  /// In en, this message translates to:
  /// **'Please fill all required fields.'**
  String get allFieldsRequired;

  /// No description provided for @savedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully! ✅'**
  String get savedSuccessfully;

  /// No description provided for @failedToSave.
  ///
  /// In en, this message translates to:
  /// **'Failed to save.'**
  String get failedToSave;

  /// No description provided for @adminCommandCenter.
  ///
  /// In en, this message translates to:
  /// **'COMMAND CENTER'**
  String get adminCommandCenter;

  /// No description provided for @selectManagementModule.
  ///
  /// In en, this message translates to:
  /// **'Select a management module'**
  String get selectManagementModule;

  /// No description provided for @module.
  ///
  /// In en, this message translates to:
  /// **'Module'**
  String get module;

  /// No description provided for @administrator.
  ///
  /// In en, this message translates to:
  /// **'ADMINISTRATOR'**
  String get administrator;

  /// No description provided for @signOutSession.
  ///
  /// In en, this message translates to:
  /// **'SIGN OUT SESSION'**
  String get signOutSession;

  /// No description provided for @adminInitializing.
  ///
  /// In en, this message translates to:
  /// **'INITIALIZING COMMAND CENTER...'**
  String get adminInitializing;

  /// No description provided for @createNewContent.
  ///
  /// In en, this message translates to:
  /// **'Create New Content 🚀'**
  String get createNewContent;

  /// No description provided for @uploadEducationalReel.
  ///
  /// In en, this message translates to:
  /// **'Upload Reel 🎬'**
  String get uploadEducationalReel;

  /// No description provided for @shareReelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share short reels videos with peers'**
  String get shareReelSubtitle;

  /// No description provided for @createFeedPost.
  ///
  /// In en, this message translates to:
  /// **'Create Feed Post 📝'**
  String get createFeedPost;

  /// No description provided for @sharePostSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share text, questions, or images on ZEV feed'**
  String get sharePostSubtitle;

  /// No description provided for @systemCommandCenter.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM COMMAND CENTER'**
  String get systemCommandCenter;

  /// No description provided for @adminDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live performance overview and global ZEV platform control.'**
  String get adminDashboardSubtitle;

  /// No description provided for @totalFaculty.
  ///
  /// In en, this message translates to:
  /// **'Total Faculty'**
  String get totalFaculty;

  /// No description provided for @systemMetrics.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM METRICS'**
  String get systemMetrics;

  /// No description provided for @grossRevenue.
  ///
  /// In en, this message translates to:
  /// **'Gross Revenue'**
  String get grossRevenue;

  /// No description provided for @pendingPayouts.
  ///
  /// In en, this message translates to:
  /// **'Pending Payouts'**
  String get pendingPayouts;

  /// No description provided for @recentTransactions.
  ///
  /// In en, this message translates to:
  /// **'RECENT TRANSACTIONS'**
  String get recentTransactions;

  /// No description provided for @noRecentTransactions.
  ///
  /// In en, this message translates to:
  /// **'No recent financial activity recorded.'**
  String get noRecentTransactions;

  /// No description provided for @studentRegistry.
  ///
  /// In en, this message translates to:
  /// **'STUDENT REGISTRY'**
  String get studentRegistry;

  /// No description provided for @manageStudentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor academic performance, points, wallet balances & role promotions.'**
  String get manageStudentsSubtitle;

  /// No description provided for @totalFunds.
  ///
  /// In en, this message translates to:
  /// **'Total Funds'**
  String get totalFunds;

  /// No description provided for @manageProfile.
  ///
  /// In en, this message translates to:
  /// **'Manage Profile'**
  String get manageProfile;

  /// No description provided for @studentProfileNotFound.
  ///
  /// In en, this message translates to:
  /// **'Student Profile Not Found'**
  String get studentProfileNotFound;

  /// No description provided for @backToStudents.
  ///
  /// In en, this message translates to:
  /// **'Back to Students'**
  String get backToStudents;

  /// No description provided for @personalDetailsLocked.
  ///
  /// In en, this message translates to:
  /// **'PERSONAL DETAILS (LOCKED)'**
  String get personalDetailsLocked;

  /// No description provided for @adminControls.
  ///
  /// In en, this message translates to:
  /// **'ADMIN CONTROLS & DATABASE SYNC'**
  String get adminControls;

  /// No description provided for @academicScore.
  ///
  /// In en, this message translates to:
  /// **'ACADEMIC SCORE (PTS)'**
  String get academicScore;

  /// No description provided for @systemRolePromotion.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM ROLE & PROMOTION'**
  String get systemRolePromotion;

  /// No description provided for @roleStudent.
  ///
  /// In en, this message translates to:
  /// **'Student (Normal Access)'**
  String get roleStudent;

  /// No description provided for @roleTeacher.
  ///
  /// In en, this message translates to:
  /// **'Instructor / Mentor'**
  String get roleTeacher;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator (Full Access)'**
  String get roleAdmin;

  /// No description provided for @syncChangesToDatabase.
  ///
  /// In en, this message translates to:
  /// **'SYNC CHANGES TO DATABASE 🚀'**
  String get syncChangesToDatabase;

  /// No description provided for @adminSyncSuccess.
  ///
  /// In en, this message translates to:
  /// **'Admin changes successfully synchronized with database! ✅'**
  String get adminSyncSuccess;

  /// No description provided for @failedToUpdateDatabase.
  ///
  /// In en, this message translates to:
  /// **'Failed to update database'**
  String get failedToUpdateDatabase;

  /// No description provided for @facultyRegistry.
  ///
  /// In en, this message translates to:
  /// **'FACULTY REGISTRY'**
  String get facultyRegistry;

  /// No description provided for @manageFaculty.
  ///
  /// In en, this message translates to:
  /// **'Manage Faculty'**
  String get manageFaculty;

  /// No description provided for @manageFacultySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor instructor performance, assigned classes & credentials.'**
  String get manageFacultySubtitle;

  /// No description provided for @searchInstructors.
  ///
  /// In en, this message translates to:
  /// **'Search instructors...'**
  String get searchInstructors;

  /// No description provided for @noFacultyFound.
  ///
  /// In en, this message translates to:
  /// **'No faculty members found.'**
  String get noFacultyFound;

  /// No description provided for @teacherDetails.
  ///
  /// In en, this message translates to:
  /// **'Teacher Details'**
  String get teacherDetails;

  /// No description provided for @assignedClasses.
  ///
  /// In en, this message translates to:
  /// **'Assigned Classes'**
  String get assignedClasses;

  /// No description provided for @courseRepository.
  ///
  /// In en, this message translates to:
  /// **'COURSE REPOSITORY'**
  String get courseRepository;

  /// No description provided for @manageCoursesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create, modify, and publish masterclasses.'**
  String get manageCoursesSubtitle;

  /// No description provided for @academicClasses.
  ///
  /// In en, this message translates to:
  /// **'ACADEMIC CLASSES'**
  String get academicClasses;

  /// No description provided for @createNewClass.
  ///
  /// In en, this message translates to:
  /// **'Create New Class'**
  String get createNewClass;

  /// No description provided for @enrolledStudents.
  ///
  /// In en, this message translates to:
  /// **'Enrolled Students'**
  String get enrolledStudents;

  /// No description provided for @addStudents.
  ///
  /// In en, this message translates to:
  /// **'Add Students'**
  String get addStudents;

  /// No description provided for @treasuryFinance.
  ///
  /// In en, this message translates to:
  /// **'TREASURY & FINANCE'**
  String get treasuryFinance;

  /// No description provided for @financialOverview.
  ///
  /// In en, this message translates to:
  /// **'Financial Overview & Payouts'**
  String get financialOverview;

  /// No description provided for @approvePayout.
  ///
  /// In en, this message translates to:
  /// **'Approve Payout'**
  String get approvePayout;

  /// No description provided for @rejectPayout.
  ///
  /// In en, this message translates to:
  /// **'Reject Payout'**
  String get rejectPayout;

  /// No description provided for @honorsAndAwards.
  ///
  /// In en, this message translates to:
  /// **'Honors & Achievements'**
  String get honorsAndAwards;

  /// No description provided for @helpDeskTickets.
  ///
  /// In en, this message translates to:
  /// **'Help Desk Tickets'**
  String get helpDeskTickets;

  /// No description provided for @replyToTicket.
  ///
  /// In en, this message translates to:
  /// **'Reply to Ticket'**
  String get replyToTicket;

  /// No description provided for @systemSettings.
  ///
  /// In en, this message translates to:
  /// **'System Settings'**
  String get systemSettings;

  /// No description provided for @backToClassRoster.
  ///
  /// In en, this message translates to:
  /// **'Back to Class Roster'**
  String get backToClassRoster;

  /// No description provided for @enrollStudents.
  ///
  /// In en, this message translates to:
  /// **'Enroll Students'**
  String get enrollStudents;

  /// No description provided for @enrollStudentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select multiple students to enroll in this cohort.'**
  String get enrollStudentsSubtitle;

  /// No description provided for @confirmEnrollment.
  ///
  /// In en, this message translates to:
  /// **'Confirm Enrollment'**
  String get confirmEnrollment;

  /// No description provided for @paidAll.
  ///
  /// In en, this message translates to:
  /// **'Paid (All)'**
  String get paidAll;

  /// No description provided for @facultyManagement.
  ///
  /// In en, this message translates to:
  /// **'Faculty Management'**
  String get facultyManagement;

  /// No description provided for @facultyDirectory.
  ///
  /// In en, this message translates to:
  /// **'FACULTY DIRECTORY'**
  String get facultyDirectory;

  /// No description provided for @facultyManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review instructor profiles and active cohorts from profiles & teacher_info.'**
  String get facultyManagementSubtitle;

  /// No description provided for @activeCohorts.
  ///
  /// In en, this message translates to:
  /// **'Active Cohorts'**
  String get activeCohorts;

  /// No description provided for @searchInstructorsHint.
  ///
  /// In en, this message translates to:
  /// **'Search instructor by name or email...'**
  String get searchInstructorsHint;

  /// No description provided for @noInstructorsFound.
  ///
  /// In en, this message translates to:
  /// **'No instructors found.'**
  String get noInstructorsFound;

  /// No description provided for @noBiographyProvided.
  ///
  /// In en, this message translates to:
  /// **'No professional biography provided.'**
  String get noBiographyProvided;

  /// No description provided for @viewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get viewProfile;

  /// No description provided for @backToFaculty.
  ///
  /// In en, this message translates to:
  /// **'Back to Faculty'**
  String get backToFaculty;

  /// No description provided for @instructorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Instructor Not Found'**
  String get instructorNotFound;

  /// No description provided for @walletBalanceAndPayouts.
  ///
  /// In en, this message translates to:
  /// **'WALLET BALANCE & PAYOUTS'**
  String get walletBalanceAndPayouts;

  /// No description provided for @processPayout.
  ///
  /// In en, this message translates to:
  /// **'Process Payout'**
  String get processPayout;

  /// No description provided for @instructorProfileSyncSuccess.
  ///
  /// In en, this message translates to:
  /// **'Instructor profile & admin controls successfully synchronized! 🚀'**
  String get instructorProfileSyncSuccess;

  /// No description provided for @invalidPayoutAmount.
  ///
  /// In en, this message translates to:
  /// **'Invalid payout amount.'**
  String get invalidPayoutAmount;

  /// No description provided for @payoutSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payout successfully processed!'**
  String get payoutSuccess;

  /// No description provided for @failedToProcessPayout.
  ///
  /// In en, this message translates to:
  /// **'Failed to process payout'**
  String get failedToProcessPayout;

  /// No description provided for @specializedCourses.
  ///
  /// In en, this message translates to:
  /// **'SPECIALIZED COURSES'**
  String get specializedCourses;

  /// No description provided for @noSpecializedCourses.
  ///
  /// In en, this message translates to:
  /// **'No specialized courses linked.'**
  String get noSpecializedCourses;

  /// No description provided for @assignedCohorts.
  ///
  /// In en, this message translates to:
  /// **'ASSIGNED COHORTS'**
  String get assignedCohorts;

  /// No description provided for @noAssignedClasses.
  ///
  /// In en, this message translates to:
  /// **'No assigned classes.'**
  String get noAssignedClasses;

  /// No description provided for @confirmAndSettlePayout.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM & SETTLE PAYOUT 🚀'**
  String get confirmAndSettlePayout;

  /// No description provided for @payoutAmountUsd.
  ///
  /// In en, this message translates to:
  /// **'PAYOUT AMOUNT (USD)'**
  String get payoutAmountUsd;

  /// No description provided for @biographyTeacherInfo.
  ///
  /// In en, this message translates to:
  /// **'BIOGRAPHY (TEACHER INFO)'**
  String get biographyTeacherInfo;

  /// No description provided for @courseLibrary.
  ///
  /// In en, this message translates to:
  /// **'COURSE LIBRARY'**
  String get courseLibrary;

  /// No description provided for @searchCourseHint.
  ///
  /// In en, this message translates to:
  /// **'Search courses by title or description...'**
  String get searchCourseHint;

  /// No description provided for @coursePrice.
  ///
  /// In en, this message translates to:
  /// **'Course Price (\$)'**
  String get coursePrice;

  /// No description provided for @courseCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get courseCategory;

  /// No description provided for @courseLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get courseLevel;

  /// No description provided for @thumbnailUrl.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Image URL'**
  String get thumbnailUrl;

  /// No description provided for @saveCourseChanges.
  ///
  /// In en, this message translates to:
  /// **'SAVE COURSE CHANGES 🚀'**
  String get saveCourseChanges;

  /// No description provided for @createCourseAction.
  ///
  /// In en, this message translates to:
  /// **'CREATE MASTERCLASS 🚀'**
  String get createCourseAction;

  /// No description provided for @deleteCourse.
  ///
  /// In en, this message translates to:
  /// **'Delete Course'**
  String get deleteCourse;

  /// No description provided for @confirmDeleteCourse.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this course?'**
  String get confirmDeleteCourse;

  /// No description provided for @classesAndCohorts.
  ///
  /// In en, this message translates to:
  /// **'Classes & Cohorts'**
  String get classesAndCohorts;

  /// No description provided for @cohortDirectory.
  ///
  /// In en, this message translates to:
  /// **'COHORT DIRECTORY'**
  String get cohortDirectory;

  /// No description provided for @searchClassesHint.
  ///
  /// In en, this message translates to:
  /// **'Search classes by name or instructor...'**
  String get searchClassesHint;

  /// No description provided for @noClassesFound.
  ///
  /// In en, this message translates to:
  /// **'No classes found.'**
  String get noClassesFound;

  /// No description provided for @activeCohort.
  ///
  /// In en, this message translates to:
  /// **'Active Cohort'**
  String get activeCohort;

  /// No description provided for @inactiveCohort.
  ///
  /// In en, this message translates to:
  /// **'Archived / Inactive'**
  String get inactiveCohort;

  /// No description provided for @selectTeacher.
  ///
  /// In en, this message translates to:
  /// **'Select Instructor'**
  String get selectTeacher;

  /// No description provided for @selectCourse.
  ///
  /// In en, this message translates to:
  /// **'Select Course'**
  String get selectCourse;

  /// No description provided for @createClassAction.
  ///
  /// In en, this message translates to:
  /// **'CREATE NEW COHORT 🚀'**
  String get createClassAction;

  /// No description provided for @saveClassChanges.
  ///
  /// In en, this message translates to:
  /// **'SAVE CLASS CHANGES 🚀'**
  String get saveClassChanges;

  /// No description provided for @liveStreamingStudio.
  ///
  /// In en, this message translates to:
  /// **'LIVE STREAMING STUDIO'**
  String get liveStreamingStudio;

  /// No description provided for @broadcastRoomUrl.
  ///
  /// In en, this message translates to:
  /// **'Broadcast Room URL / Meeting Link'**
  String get broadcastRoomUrl;

  /// No description provided for @financialLedger.
  ///
  /// In en, this message translates to:
  /// **'FINANCIAL LEDGER'**
  String get financialLedger;

  /// No description provided for @allTransactions.
  ///
  /// In en, this message translates to:
  /// **'All Transactions'**
  String get allTransactions;

  /// No description provided for @deposits.
  ///
  /// In en, this message translates to:
  /// **'Deposits'**
  String get deposits;

  /// No description provided for @withdrawals.
  ///
  /// In en, this message translates to:
  /// **'Withdrawals'**
  String get withdrawals;

  /// No description provided for @awardsAndRecognition.
  ///
  /// In en, this message translates to:
  /// **'AWARDS & RECOGNITION'**
  String get awardsAndRecognition;

  /// No description provided for @announcementBroadcast.
  ///
  /// In en, this message translates to:
  /// **'ANNOUNCEMENT BROADCAST'**
  String get announcementBroadcast;

  /// No description provided for @publishAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'PUBLISH ANNOUNCEMENT 📢'**
  String get publishAnnouncement;

  /// No description provided for @supportHelpDesk.
  ///
  /// In en, this message translates to:
  /// **'SUPPORT HELP DESK'**
  String get supportHelpDesk;

  /// No description provided for @ticketStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get ticketStatusOpen;

  /// No description provided for @ticketStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Resolved / Closed'**
  String get ticketStatusClosed;

  /// No description provided for @liveSupportChat.
  ///
  /// In en, this message translates to:
  /// **'Live Support Chat'**
  String get liveSupportChat;

  /// No description provided for @adminSettings.
  ///
  /// In en, this message translates to:
  /// **'ADMIN SETTINGS'**
  String get adminSettings;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'SAVE SETTINGS 🚀'**
  String get saveSettings;

  /// No description provided for @systemConfiguration.
  ///
  /// In en, this message translates to:
  /// **'System Configuration'**
  String get systemConfiguration;

  /// No description provided for @loadingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Loading Directory...'**
  String get loadingDirectory;

  /// No description provided for @teacher.
  ///
  /// In en, this message translates to:
  /// **'Teacher'**
  String get teacher;

  /// No description provided for @course.
  ///
  /// In en, this message translates to:
  /// **'Course'**
  String get course;

  /// No description provided for @backToCourses.
  ///
  /// In en, this message translates to:
  /// **'Back to Courses'**
  String get backToCourses;

  /// No description provided for @noDescription.
  ///
  /// In en, this message translates to:
  /// **'No description provided.'**
  String get noDescription;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @backToCohorts.
  ///
  /// In en, this message translates to:
  /// **'Back to Cohorts'**
  String get backToCohorts;

  /// No description provided for @cohortManagement.
  ///
  /// In en, this message translates to:
  /// **'COHORT MANAGEMENT'**
  String get cohortManagement;

  /// No description provided for @createClassCohortSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Assign course, instructor, schedule and online links for students.'**
  String get createClassCohortSubtitle;

  /// No description provided for @classTimeSlot.
  ///
  /// In en, this message translates to:
  /// **'CLASS TIME SLOT'**
  String get classTimeSlot;

  /// No description provided for @classDaysHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Sat, Mon, Wed'**
  String get classDaysHint;

  /// No description provided for @classTimeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 18:00 - 20:00'**
  String get classTimeHint;

  /// No description provided for @scheduleNotes.
  ///
  /// In en, this message translates to:
  /// **'SCHEDULE INFO (NOTES)'**
  String get scheduleNotes;

  /// No description provided for @meetingLinkHint.
  ///
  /// In en, this message translates to:
  /// **'https://zoom.us/j/...'**
  String get meetingLinkHint;

  /// No description provided for @signalLinkHint.
  ///
  /// In en, this message translates to:
  /// **'https://t.me/+...'**
  String get signalLinkHint;

  /// No description provided for @activeLiveCohort.
  ///
  /// In en, this message translates to:
  /// **'Active (Live Cohort)'**
  String get activeLiveCohort;

  /// No description provided for @archivedCompleted.
  ///
  /// In en, this message translates to:
  /// **'Archived / Completed'**
  String get archivedCompleted;

  /// No description provided for @noLiveSessions.
  ///
  /// In en, this message translates to:
  /// **'No live sessions found.'**
  String get noLiveSessions;

  /// No description provided for @noLink.
  ///
  /// In en, this message translates to:
  /// **'No Link'**
  String get noLink;

  /// No description provided for @manageAction.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manageAction;

  /// No description provided for @manageClassModal.
  ///
  /// In en, this message translates to:
  /// **'Manage Class'**
  String get manageClassModal;

  /// No description provided for @saveAndUpdateAll.
  ///
  /// In en, this message translates to:
  /// **'SAVE & UPDATE ALL PROPERTIES 🚀'**
  String get saveAndUpdateAll;

  /// No description provided for @liveSessionsAndCohorts.
  ///
  /// In en, this message translates to:
  /// **'Live Sessions & Cohorts'**
  String get liveSessionsAndCohorts;

  /// No description provided for @liveSessionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor active rooms, schedules, and manage all class properties securely.'**
  String get liveSessionsSubtitle;

  /// No description provided for @searchCohortsHint.
  ///
  /// In en, this message translates to:
  /// **'Search cohorts...'**
  String get searchCohortsHint;

  /// No description provided for @establishingConnection.
  ///
  /// In en, this message translates to:
  /// **'ESTABLISHING LIVE CONNECTION...'**
  String get establishingConnection;

  /// No description provided for @auditingRecords.
  ///
  /// In en, this message translates to:
  /// **'AUDITING FINANCIAL RECORDS...'**
  String get auditingRecords;

  /// No description provided for @financialLedgerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Audit global platform revenue and manage faculty payouts securely.'**
  String get financialLedgerSubtitle;

  /// No description provided for @facultyLiability.
  ///
  /// In en, this message translates to:
  /// **'Faculty Liability'**
  String get facultyLiability;

  /// No description provided for @distributedPayouts.
  ///
  /// In en, this message translates to:
  /// **'Distributed Payouts'**
  String get distributedPayouts;

  /// No description provided for @netProfit.
  ///
  /// In en, this message translates to:
  /// **'Net Profit'**
  String get netProfit;

  /// No description provided for @facultyTab.
  ///
  /// In en, this message translates to:
  /// **'Faculty'**
  String get facultyTab;

  /// No description provided for @inflowsTab.
  ///
  /// In en, this message translates to:
  /// **'Inflows'**
  String get inflowsTab;

  /// No description provided for @outflowsTab.
  ///
  /// In en, this message translates to:
  /// **'Outflows'**
  String get outflowsTab;

  /// No description provided for @findInstructorHint.
  ///
  /// In en, this message translates to:
  /// **'Find instructor...'**
  String get findInstructorHint;

  /// No description provided for @payoutAmount.
  ///
  /// In en, this message translates to:
  /// **'Payout Amount (\$)'**
  String get payoutAmount;

  /// No description provided for @confirmPayout.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM PAYOUT 💸'**
  String get confirmPayout;

  /// No description provided for @studentPayments.
  ///
  /// In en, this message translates to:
  /// **'Student Inflows'**
  String get studentPayments;

  /// No description provided for @payoutRecords.
  ///
  /// In en, this message translates to:
  /// **'Payout Outflows'**
  String get payoutRecords;

  /// No description provided for @noTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions found.'**
  String get noTransactions;

  /// No description provided for @awardsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create, manage and distribute student achievement badges & rewards.'**
  String get awardsSubtitle;

  /// No description provided for @createAwardTitle.
  ///
  /// In en, this message translates to:
  /// **'Create New Award'**
  String get createAwardTitle;

  /// No description provided for @awardDescription.
  ///
  /// In en, this message translates to:
  /// **'Award Description'**
  String get awardDescription;

  /// No description provided for @awardIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon / Emoji'**
  String get awardIcon;

  /// No description provided for @publishAwardAction.
  ///
  /// In en, this message translates to:
  /// **'CREATE NEW AWARD 🏆'**
  String get publishAwardAction;

  /// No description provided for @availableAwards.
  ///
  /// In en, this message translates to:
  /// **'Available Badges & Awards'**
  String get availableAwards;

  /// No description provided for @noAwardsFound.
  ///
  /// In en, this message translates to:
  /// **'No awards or badges found.'**
  String get noAwardsFound;

  /// No description provided for @deleteAward.
  ///
  /// In en, this message translates to:
  /// **'Delete Award'**
  String get deleteAward;

  /// No description provided for @announcementsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Broadcast system-wide notices, updates, or maintenance alerts to all users.'**
  String get announcementsSubtitle;

  /// No description provided for @announcementContent.
  ///
  /// In en, this message translates to:
  /// **'Announcement Message / Content'**
  String get announcementContent;

  /// No description provided for @studentsOnly.
  ///
  /// In en, this message translates to:
  /// **'Students Only'**
  String get studentsOnly;

  /// No description provided for @teachersOnly.
  ///
  /// In en, this message translates to:
  /// **'Faculty Only'**
  String get teachersOnly;

  /// No description provided for @broadcastNow.
  ///
  /// In en, this message translates to:
  /// **'BROADCAST ANNOUNCEMENT 📢'**
  String get broadcastNow;

  /// No description provided for @recentAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'Broadcast History'**
  String get recentAnnouncements;

  /// No description provided for @noAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'No announcements broadcast yet.'**
  String get noAnnouncements;

  /// No description provided for @ticketsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage support desk inquiries, unresolved issues, and departmental tickets.'**
  String get ticketsSubtitle;

  /// No description provided for @searchTicketsHint.
  ///
  /// In en, this message translates to:
  /// **'Search by subject, student or department...'**
  String get searchTicketsHint;

  /// No description provided for @filterStatusAll.
  ///
  /// In en, this message translates to:
  /// **'All Tickets'**
  String get filterStatusAll;

  /// No description provided for @filterDepartment.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get filterDepartment;

  /// No description provided for @ticketDetails.
  ///
  /// In en, this message translates to:
  /// **'Ticket Details'**
  String get ticketDetails;

  /// No description provided for @typeYourReply.
  ///
  /// In en, this message translates to:
  /// **'Type your reply...'**
  String get typeYourReply;

  /// No description provided for @reopenTicket.
  ///
  /// In en, this message translates to:
  /// **'Reopen Ticket'**
  String get reopenTicket;

  /// No description provided for @liveSupportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Handle live student & faculty assistance in real time.'**
  String get liveSupportSubtitle;

  /// No description provided for @searchSupportHint.
  ///
  /// In en, this message translates to:
  /// **'Search support requests...'**
  String get searchSupportHint;

  /// No description provided for @openChat.
  ///
  /// In en, this message translates to:
  /// **'Open Chat'**
  String get openChat;

  /// No description provided for @noSupportRequests.
  ///
  /// In en, this message translates to:
  /// **'No support requests found.'**
  String get noSupportRequests;

  /// No description provided for @supportChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Support Chat'**
  String get supportChatTitle;

  /// No description provided for @markResolved.
  ///
  /// In en, this message translates to:
  /// **'Mark Resolved'**
  String get markResolved;

  /// No description provided for @adminSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your administrator profile, system preferences, and security settings.'**
  String get adminSettingsSubtitle;

  /// No description provided for @systemAdmin.
  ///
  /// In en, this message translates to:
  /// **'System Administrator'**
  String get systemAdmin;

  /// No description provided for @adminRole.
  ///
  /// In en, this message translates to:
  /// **'Administrative Role'**
  String get adminRole;

  /// No description provided for @logOutAccount.
  ///
  /// In en, this message translates to:
  /// **'Log Out Account'**
  String get logOutAccount;

  /// No description provided for @confirmLogout.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get confirmLogout;

  /// No description provided for @avatarUrl.
  ///
  /// In en, this message translates to:
  /// **'Avatar URL'**
  String get avatarUrl;

  /// No description provided for @superAdminRole.
  ///
  /// In en, this message translates to:
  /// **'Administrator (Super Admin)'**
  String get superAdminRole;

  /// No description provided for @teacherRole.
  ///
  /// In en, this message translates to:
  /// **'Instructor / Mentor (Teacher)'**
  String get teacherRole;

  /// No description provided for @studentRole.
  ///
  /// In en, this message translates to:
  /// **'Student (Normal)'**
  String get studentRole;

  /// No description provided for @teacherInfoAndCredentials.
  ///
  /// In en, this message translates to:
  /// **'TEACHER INFO & CREDENTIALS'**
  String get teacherInfoAndCredentials;

  /// No description provided for @facultyIdentityAndRole.
  ///
  /// In en, this message translates to:
  /// **'FACULTY IDENTITY & ROLE'**
  String get facultyIdentityAndRole;

  /// No description provided for @synchronizingEngine.
  ///
  /// In en, this message translates to:
  /// **'SYNCHRONIZING ENGINE...'**
  String get synchronizingEngine;

  /// No description provided for @settingsUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Settings & configurations synced successfully! 🚀'**
  String get settingsUpdatedSuccess;

  /// No description provided for @failedToUpdateSettings.
  ///
  /// In en, this message translates to:
  /// **'Failed to update configuration'**
  String get failedToUpdateSettings;

  /// No description provided for @noMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get noMessages;

  /// No description provided for @teachers.
  ///
  /// In en, this message translates to:
  /// **'Teachers'**
  String get teachers;

  /// No description provided for @activityLog.
  ///
  /// In en, this message translates to:
  /// **'Activity Log'**
  String get activityLog;

  /// No description provided for @loginActivity.
  ///
  /// In en, this message translates to:
  /// **'Login Activity'**
  String get loginActivity;

  /// No description provided for @activeSessions.
  ///
  /// In en, this message translates to:
  /// **'Active Sessions & Devices'**
  String get activeSessions;

  /// No description provided for @currentDevice.
  ///
  /// In en, this message translates to:
  /// **'Current Device (This Phone)'**
  String get currentDevice;

  /// No description provided for @pastSessions.
  ///
  /// In en, this message translates to:
  /// **'Past Logins'**
  String get pastSessions;

  /// No description provided for @noOtherActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'No other active sessions recorded.'**
  String get noOtherActiveSessions;

  /// No description provided for @activeNow.
  ///
  /// In en, this message translates to:
  /// **'Active Now'**
  String get activeNow;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanent Account Deletion Request'**
  String get deleteAccountSubtitle;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning: Deleting your account is permanent. All your purchased courses, certificates, wallet balance, quiz records, and learning progress will be permanently erased.'**
  String get deleteAccountWarning;

  /// No description provided for @deleteAccountReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Please explain why you want to delete your account (optional)'**
  String get deleteAccountReasonHint;

  /// No description provided for @deleteAccountConfirmCheck.
  ///
  /// In en, this message translates to:
  /// **'I understand that this action is irreversible and all my data will be deleted.'**
  String get deleteAccountConfirmCheck;

  /// No description provided for @requestAccountDeletion.
  ///
  /// In en, this message translates to:
  /// **'Submit Deletion Request'**
  String get requestAccountDeletion;

  /// No description provided for @accountDeletionSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Your deletion request has been submitted. Our admin team will verify and remove your account within 24-48 hours.'**
  String get accountDeletionSubmitted;

  /// No description provided for @deleteAccountWebPolicy.
  ///
  /// In en, this message translates to:
  /// **'Official Web Deletion Policy'**
  String get deleteAccountWebPolicy;

  /// No description provided for @shop.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get shop;

  /// No description provided for @shopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Verified Reseller Products & Educational Gear'**
  String get shopSubtitle;

  /// No description provided for @resellerProducts.
  ///
  /// In en, this message translates to:
  /// **'Reseller Products'**
  String get resellerProducts;

  /// No description provided for @inStock.
  ///
  /// In en, this message translates to:
  /// **'In Stock'**
  String get inStock;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get outOfStock;

  /// No description provided for @buyNow.
  ///
  /// In en, this message translates to:
  /// **'Buy Now'**
  String get buyNow;

  /// No description provided for @productDetails.
  ///
  /// In en, this message translates to:
  /// **'Product Details'**
  String get productDetails;

  /// No description provided for @priceUsd.
  ///
  /// In en, this message translates to:
  /// **'Price (USD)'**
  String get priceUsd;

  /// No description provided for @localEquivalent.
  ///
  /// In en, this message translates to:
  /// **'Estimated Local Value'**
  String get localEquivalent;

  /// No description provided for @paymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Payment Methods'**
  String get paymentMethods;

  /// No description provided for @hesabPay.
  ///
  /// In en, this message translates to:
  /// **'HesabPay'**
  String get hesabPay;

  /// No description provided for @atomaPay.
  ///
  /// In en, this message translates to:
  /// **'Atoma Pay'**
  String get atomaPay;

  /// No description provided for @hesabPayNumber.
  ///
  /// In en, this message translates to:
  /// **'+93796040415'**
  String get hesabPayNumber;

  /// No description provided for @atomaPayNumber.
  ///
  /// In en, this message translates to:
  /// **'+93773449567'**
  String get atomaPayNumber;

  /// No description provided for @copyNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy Account Number'**
  String get copyNumber;

  /// No description provided for @buyerFullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get buyerFullName;

  /// No description provided for @buyerContact.
  ///
  /// In en, this message translates to:
  /// **'Phone / Telegram / WhatsApp'**
  String get buyerContact;

  /// No description provided for @completeOrder.
  ///
  /// In en, this message translates to:
  /// **'Complete Purchase & Finish'**
  String get completeOrder;

  /// No description provided for @orderProcessing.
  ///
  /// In en, this message translates to:
  /// **'Submitting Order...'**
  String get orderProcessing;

  /// No description provided for @orderSubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Order placed successfully! Notification sent to Telegram.'**
  String get orderSubmittedSuccess;

  /// No description provided for @selectAppColor.
  ///
  /// In en, this message translates to:
  /// **'Select App Color'**
  String get selectAppColor;

  /// No description provided for @selectAppColorDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose your luxury theme palette'**
  String get selectAppColorDesc;

  /// No description provided for @themeImperialRoseGold.
  ///
  /// In en, this message translates to:
  /// **'Imperial Rose Gold & Champagne'**
  String get themeImperialRoseGold;

  /// No description provided for @themeRoyalEmerald.
  ///
  /// In en, this message translates to:
  /// **'Royal Emerald & 24K Gold'**
  String get themeRoyalEmerald;

  /// No description provided for @themeMidnightSapphire.
  ///
  /// In en, this message translates to:
  /// **'Midnight Sapphire & Platinum'**
  String get themeMidnightSapphire;

  /// No description provided for @themeObsidianVelvet.
  ///
  /// In en, this message translates to:
  /// **'Obsidian Velvet & Rich Ruby'**
  String get themeObsidianVelvet;

  /// No description provided for @themeAmethystGlow.
  ///
  /// In en, this message translates to:
  /// **'Amethyst Glow & Diamond'**
  String get themeAmethystGlow;

  /// No description provided for @syncResellerProducts.
  ///
  /// In en, this message translates to:
  /// **'Sync Reseller Products'**
  String get syncResellerProducts;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get syncNow;

  /// No description provided for @syncStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync Status'**
  String get syncStatus;

  /// No description provided for @syncHistory.
  ///
  /// In en, this message translates to:
  /// **'Sync History'**
  String get syncHistory;

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last Synced'**
  String get lastSynced;

  /// No description provided for @itemsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Items Updated'**
  String get itemsUpdated;

  /// No description provided for @resellerSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Product Synchronization (Edge Function)'**
  String get resellerSyncTitle;

  /// No description provided for @totalProducts.
  ///
  /// In en, this message translates to:
  /// **'Total Products'**
  String get totalProducts;

  /// No description provided for @activeInStore.
  ///
  /// In en, this message translates to:
  /// **'Active in Store'**
  String get activeInStore;

  /// No description provided for @syncWithEdgeFunction.
  ///
  /// In en, this message translates to:
  /// **'Sync with Supabase Edge Function'**
  String get syncWithEdgeFunction;

  /// No description provided for @syncDescription.
  ///
  /// In en, this message translates to:
  /// **'Execute Edge Function to update prices and stock'**
  String get syncDescription;

  /// No description provided for @edgeFunctionNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Supabase Edge Function Name'**
  String get edgeFunctionNameLabel;

  /// No description provided for @lastSyncTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Last Sync'**
  String get lastSyncTimeLabel;

  /// No description provided for @runSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Run Sync Now'**
  String get runSyncNow;

  /// No description provided for @syncingInProgress.
  ///
  /// In en, this message translates to:
  /// **'Syncing with server...'**
  String get syncingInProgress;

  /// No description provided for @syncLogsHistory.
  ///
  /// In en, this message translates to:
  /// **'Synchronization Logs History'**
  String get syncLogsHistory;

  /// No description provided for @logsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Logs'**
  String logsCount(Object count);

  /// No description provided for @noSyncLogsYet.
  ///
  /// In en, this message translates to:
  /// **'No sync logs recorded yet. Press the sync button.'**
  String get noSyncLogsYet;

  /// No description provided for @syncSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Product stock and status synchronized successfully!'**
  String get syncSuccessMessage;

  /// No description provided for @syncErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
  String get syncErrorMessage;

  /// No description provided for @syncStatusSuccess.
  ///
  /// In en, this message translates to:
  /// **'Successful'**
  String get syncStatusSuccess;

  /// No description provided for @syncStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get syncStatusFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'de',
    'en',
    'es',
    'fa',
    'fr',
    'hi',
    'id',
    'it',
    'ja',
    'ko',
    'nl',
    'ps',
    'pt',
    'ru',
    'tr',
    'ur',
    'uz',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fa':
      return AppLocalizationsFa();
    case 'fr':
      return AppLocalizationsFr();
    case 'hi':
      return AppLocalizationsHi();
    case 'id':
      return AppLocalizationsId();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'nl':
      return AppLocalizationsNl();
    case 'ps':
      return AppLocalizationsPs();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
    case 'ur':
      return AppLocalizationsUr();
    case 'uz':
      return AppLocalizationsUz();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
