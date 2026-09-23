import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Suvi Share'**
  String get appName;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Share across the room, not across the internet.'**
  String get tagline;

  /// No description provided for @navNearby.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get navNearby;

  /// No description provided for @navTransfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get navTransfers;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Share files on your Wi-Fi.\nNo cloud, no account.'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Suvi Share moves photos, videos, documents and text between your devices over your local network. Nothing ever leaves your home.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Your device name'**
  String get onboardingNameTitle;

  /// No description provided for @onboardingNameBody.
  ///
  /// In en, this message translates to:
  /// **'This is how other devices will see you.'**
  String get onboardingNameBody;

  /// No description provided for @onboardingNameHint.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get onboardingNameHint;

  /// No description provided for @onboardingShuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle name'**
  String get onboardingShuffle;

  /// No description provided for @onboardingReceiveTitle.
  ///
  /// In en, this message translates to:
  /// **'How should receiving work?'**
  String get onboardingReceiveTitle;

  /// No description provided for @onboardingReceiveBody.
  ///
  /// In en, this message translates to:
  /// **'You can change this anytime in Settings.'**
  String get onboardingReceiveBody;

  /// No description provided for @receiveModeAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask me every time'**
  String get receiveModeAsk;

  /// No description provided for @receiveModeAskDesc.
  ///
  /// In en, this message translates to:
  /// **'You\'ll see who\'s sending and what, then accept or decline.'**
  String get receiveModeAskDesc;

  /// No description provided for @receiveModeTrusted.
  ///
  /// In en, this message translates to:
  /// **'Auto-save from trusted devices'**
  String get receiveModeTrusted;

  /// No description provided for @receiveModeTrustedDesc.
  ///
  /// In en, this message translates to:
  /// **'Devices you\'ve marked as trusted send without asking. Others still ask.'**
  String get receiveModeTrustedDesc;

  /// No description provided for @receiveModePin.
  ///
  /// In en, this message translates to:
  /// **'Require a PIN'**
  String get receiveModePin;

  /// No description provided for @receiveModePinDesc.
  ///
  /// In en, this message translates to:
  /// **'Senders must enter your PIN before anything arrives.'**
  String get receiveModePinDesc;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Start sharing'**
  String get onboardingFinish;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @youAre.
  ///
  /// In en, this message translates to:
  /// **'You are {alias}'**
  String youAre(String alias);

  /// No description provided for @visibleOn.
  ///
  /// In en, this message translates to:
  /// **'Visible on your network · {ip}'**
  String visibleOn(String ip);

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected to Wi-Fi'**
  String get notConnected;

  /// No description provided for @receiveOn.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get receiveOn;

  /// No description provided for @receiveOff.
  ///
  /// In en, this message translates to:
  /// **'Receiving off'**
  String get receiveOff;

  /// No description provided for @lookingForDevices.
  ///
  /// In en, this message translates to:
  /// **'Looking for devices on your network…'**
  String get lookingForDevices;

  /// No description provided for @nearbyDevices.
  ///
  /// In en, this message translates to:
  /// **'Nearby devices'**
  String get nearbyDevices;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @recentlySeen.
  ///
  /// In en, this message translates to:
  /// **'Recently seen'**
  String get recentlySeen;

  /// No description provided for @noDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'No devices yet'**
  String get noDevicesTitle;

  /// No description provided for @noDevicesBody.
  ///
  /// In en, this message translates to:
  /// **'Open Suvi Share on the other device. Both must be on the same Wi-Fi.'**
  String get noDevicesBody;

  /// No description provided for @tipSameWifi.
  ///
  /// In en, this message translates to:
  /// **'Same Wi-Fi?'**
  String get tipSameWifi;

  /// No description provided for @tipFirewall.
  ///
  /// In en, this message translates to:
  /// **'Firewall allowed?'**
  String get tipFirewall;

  /// No description provided for @tipOpenApp.
  ///
  /// In en, this message translates to:
  /// **'Open Suvi on the other device'**
  String get tipOpenApp;

  /// No description provided for @enterAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter address'**
  String get enterAddress;

  /// No description provided for @scanNetwork.
  ///
  /// In en, this message translates to:
  /// **'Scan network'**
  String get scanNetwork;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning {done} of {total}…'**
  String scanning(int done, int total);

  /// No description provided for @showMyQr.
  ///
  /// In en, this message translates to:
  /// **'Show my QR'**
  String get showMyQr;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sendTo.
  ///
  /// In en, this message translates to:
  /// **'Send to {alias}'**
  String sendTo(String alias);

  /// No description provided for @trusted.
  ///
  /// In en, this message translates to:
  /// **'Trusted'**
  String get trusted;

  /// No description provided for @unverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get unverified;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @unfavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove favorite'**
  String get unfavorite;

  /// No description provided for @trustDevice.
  ///
  /// In en, this message translates to:
  /// **'Trust this device'**
  String get trustDevice;

  /// No description provided for @untrustDevice.
  ///
  /// In en, this message translates to:
  /// **'Remove trust'**
  String get untrustDevice;

  /// No description provided for @blockDevice.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockDevice;

  /// No description provided for @unblockDevice.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblockDevice;

  /// No description provided for @deviceDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get deviceDetails;

  /// No description provided for @pickFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get pickFiles;

  /// No description provided for @pickMedia.
  ///
  /// In en, this message translates to:
  /// **'Photos & videos'**
  String get pickMedia;

  /// No description provided for @pickFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get pickFolder;

  /// No description provided for @pickText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get pickText;

  /// No description provided for @pickClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get pickClipboard;

  /// No description provided for @whatToSend.
  ///
  /// In en, this message translates to:
  /// **'What do you want to send?'**
  String get whatToSend;

  /// No description provided for @browseByCategory.
  ///
  /// In en, this message translates to:
  /// **'Browse by category'**
  String get browseByCategory;

  /// No description provided for @moreWaysToShare.
  ///
  /// In en, this message translates to:
  /// **'More ways to share'**
  String get moreWaysToShare;

  /// No description provided for @continueToDevice.
  ///
  /// In en, this message translates to:
  /// **'Choose receiving device'**
  String get continueToDevice;

  /// No description provided for @filePickerFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the file picker. Please try again.'**
  String get filePickerFailed;

  /// No description provided for @categoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get categoryGeneral;

  /// No description provided for @categoryGeneralDesc.
  ///
  /// In en, this message translates to:
  /// **'Any file type'**
  String get categoryGeneralDesc;

  /// No description provided for @categoryDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get categoryDocuments;

  /// No description provided for @categoryDocumentsDesc.
  ///
  /// In en, this message translates to:
  /// **'PDF, Office & text'**
  String get categoryDocumentsDesc;

  /// No description provided for @categoryImages.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get categoryImages;

  /// No description provided for @categoryImagesDesc.
  ///
  /// In en, this message translates to:
  /// **'Images & screenshots'**
  String get categoryImagesDesc;

  /// No description provided for @categoryVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get categoryVideos;

  /// No description provided for @categoryVideosDesc.
  ///
  /// In en, this message translates to:
  /// **'Movies & clips'**
  String get categoryVideosDesc;

  /// No description provided for @categoryMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get categoryMusic;

  /// No description provided for @categoryMusicDesc.
  ///
  /// In en, this message translates to:
  /// **'Audio & recordings'**
  String get categoryMusicDesc;

  /// No description provided for @categoryCompressed.
  ///
  /// In en, this message translates to:
  /// **'Compressed'**
  String get categoryCompressed;

  /// No description provided for @categoryCompressedDesc.
  ///
  /// In en, this message translates to:
  /// **'ZIP, RAR, 7Z & more'**
  String get categoryCompressedDesc;

  /// No description provided for @categoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other files'**
  String get categoryOther;

  /// No description provided for @categoryOtherDesc.
  ///
  /// In en, this message translates to:
  /// **'Apps, data & packages'**
  String get categoryOtherDesc;

  /// No description provided for @chooseDevice.
  ///
  /// In en, this message translates to:
  /// **'Choose a device'**
  String get chooseDevice;

  /// No description provided for @itemsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}} · {size}'**
  String itemsSelected(int count, String size);

  /// No description provided for @addMore.
  ///
  /// In en, this message translates to:
  /// **'Add more'**
  String get addMore;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearSelection;

  /// No description provided for @textToSend.
  ///
  /// In en, this message translates to:
  /// **'Text to send'**
  String get textToSend;

  /// No description provided for @typeSomething.
  ///
  /// In en, this message translates to:
  /// **'Type or paste something…'**
  String get typeSomething;

  /// No description provided for @waitingForAccept.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {alias} to accept…'**
  String waitingForAccept(String alias);

  /// No description provided for @sendingTo.
  ///
  /// In en, this message translates to:
  /// **'Sending to {alias}'**
  String sendingTo(String alias);

  /// No description provided for @sentTo.
  ///
  /// In en, this message translates to:
  /// **'Sent to {alias}'**
  String sentTo(String alias);

  /// No description provided for @declinedBy.
  ///
  /// In en, this message translates to:
  /// **'{alias} declined'**
  String declinedBy(String alias);

  /// No description provided for @transferFailed.
  ///
  /// In en, this message translates to:
  /// **'Transfer failed'**
  String get transferFailed;

  /// No description provided for @transferCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get transferCancelled;

  /// No description provided for @sendMore.
  ///
  /// In en, this message translates to:
  /// **'Send more'**
  String get sendMore;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @progressLine.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} · {speed}/s'**
  String progressLine(String done, String total, String speed);

  /// No description provided for @incomingTitle.
  ///
  /// In en, this message translates to:
  /// **'{alias} wants to send you'**
  String incomingTitle(String alias);

  /// No description provided for @incomingFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}} · {size}'**
  String incomingFiles(int count, String size);

  /// No description provided for @incomingText.
  ///
  /// In en, this message translates to:
  /// **'A message'**
  String get incomingText;

  /// No description provided for @savesTo.
  ///
  /// In en, this message translates to:
  /// **'Saves to {path}'**
  String savesTo(String path);

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @alwaysAcceptFrom.
  ///
  /// In en, this message translates to:
  /// **'Always accept from {alias}'**
  String alwaysAcceptFrom(String alias);

  /// No description provided for @receivingFrom.
  ///
  /// In en, this message translates to:
  /// **'Receiving from {alias}'**
  String receivingFrom(String alias);

  /// No description provided for @receivedFrom.
  ///
  /// In en, this message translates to:
  /// **'Received from {alias}'**
  String receivedFrom(String alias);

  /// No description provided for @savedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String savedTo(String path);

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @showInFolder.
  ///
  /// In en, this message translates to:
  /// **'Show in folder'**
  String get showInFolder;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @moreFiles.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String moreFiles(int count);

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @noTransfersYet.
  ///
  /// In en, this message translates to:
  /// **'No transfers yet'**
  String get noTransfersYet;

  /// No description provided for @noTransfersBody.
  ///
  /// In en, this message translates to:
  /// **'Files you send and receive will show up here.'**
  String get noTransfersBody;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @received.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get received;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @declined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get declined;

  /// No description provided for @settingsDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get settingsDevice;

  /// No description provided for @settingsDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get settingsDeviceName;

  /// No description provided for @settingsAvatarColor.
  ///
  /// In en, this message translates to:
  /// **'Avatar color'**
  String get settingsAvatarColor;

  /// No description provided for @settingsShowAddress.
  ///
  /// In en, this message translates to:
  /// **'Show my address & QR'**
  String get settingsShowAddress;

  /// No description provided for @settingsReceiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get settingsReceiving;

  /// No description provided for @settingsReceiveMode.
  ///
  /// In en, this message translates to:
  /// **'Receive mode'**
  String get settingsReceiveMode;

  /// No description provided for @settingsPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get settingsPin;

  /// No description provided for @settingsPinDesc.
  ///
  /// In en, this message translates to:
  /// **'Senders must enter this PIN'**
  String get settingsPinDesc;

  /// No description provided for @settingsQuickSave.
  ///
  /// In en, this message translates to:
  /// **'Quick Save'**
  String get settingsQuickSave;

  /// No description provided for @settingsQuickSaveDesc.
  ///
  /// In en, this message translates to:
  /// **'Accept everything without asking — use only on networks you trust'**
  String get settingsQuickSaveDesc;

  /// No description provided for @settingsSaveFolder.
  ///
  /// In en, this message translates to:
  /// **'Save folder'**
  String get settingsSaveFolder;

  /// No description provided for @settingsTrustedDevices.
  ///
  /// In en, this message translates to:
  /// **'Trusted devices'**
  String get settingsTrustedDevices;

  /// No description provided for @settingsNoTrusted.
  ///
  /// In en, this message translates to:
  /// **'No trusted devices yet. Trust a device from its menu on the Nearby screen.'**
  String get settingsNoTrusted;

  /// No description provided for @settingsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsNetwork;

  /// No description provided for @settingsPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get settingsPort;

  /// No description provided for @settingsPortDesc.
  ///
  /// In en, this message translates to:
  /// **'Default 53317. Change only if another app uses it.'**
  String get settingsPortDesc;

  /// No description provided for @settingsEncryption.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get settingsEncryption;

  /// No description provided for @settingsEncryptionDesc.
  ///
  /// In en, this message translates to:
  /// **'TLS · Fingerprint {fp}'**
  String settingsEncryptionDesc(String fp);

  /// No description provided for @settingsWebShare.
  ///
  /// In en, this message translates to:
  /// **'Web share'**
  String get settingsWebShare;

  /// No description provided for @settingsWebShareDesc.
  ///
  /// In en, this message translates to:
  /// **'Let any browser on this Wi-Fi send and receive files — no app needed'**
  String get settingsWebShareDesc;

  /// No description provided for @webShareOn.
  ///
  /// In en, this message translates to:
  /// **'Open this address in a browser'**
  String get webShareOn;

  /// No description provided for @webShareOff.
  ///
  /// In en, this message translates to:
  /// **'Web share is off'**
  String get webShareOff;

  /// No description provided for @webShareHttpNote.
  ///
  /// In en, this message translates to:
  /// **'Served over plain HTTP because browsers reject self-signed certificates. Use a PIN on shared networks.'**
  String get webShareHttpNote;

  /// No description provided for @webShareNoWifi.
  ///
  /// In en, this message translates to:
  /// **'Connect to Wi-Fi first'**
  String get webShareNoWifi;

  /// No description provided for @shareViaLink.
  ///
  /// In en, this message translates to:
  /// **'Share via link'**
  String get shareViaLink;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @settingsDynamicColor.
  ///
  /// In en, this message translates to:
  /// **'Use wallpaper colors'**
  String get settingsDynamicColor;

  /// No description provided for @settingsPaletteHint.
  ///
  /// In en, this message translates to:
  /// **'Choosing a palette turns wallpaper colors off'**
  String get settingsPaletteHint;

  /// No description provided for @settingsColorPalette.
  ///
  /// In en, this message translates to:
  /// **'Color palette'**
  String get settingsColorPalette;

  /// No description provided for @paletteSuvi.
  ///
  /// In en, this message translates to:
  /// **'Suvi'**
  String get paletteSuvi;

  /// No description provided for @paletteOcean.
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get paletteOcean;

  /// No description provided for @paletteSunset.
  ///
  /// In en, this message translates to:
  /// **'Sunset'**
  String get paletteSunset;

  /// No description provided for @paletteForest.
  ///
  /// In en, this message translates to:
  /// **'Forest'**
  String get paletteForest;

  /// No description provided for @paletteLavender.
  ///
  /// In en, this message translates to:
  /// **'Lavender'**
  String get paletteLavender;

  /// No description provided for @paletteRose.
  ///
  /// In en, this message translates to:
  /// **'Rose'**
  String get paletteRose;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsDesktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get settingsDesktop;

  /// No description provided for @settingsMinimizeToTray.
  ///
  /// In en, this message translates to:
  /// **'Close to tray'**
  String get settingsMinimizeToTray;

  /// No description provided for @settingsMinimizeToTrayDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep receiving when the window is closed'**
  String get settingsMinimizeToTrayDesc;

  /// No description provided for @settingsUpdates.
  ///
  /// In en, this message translates to:
  /// **'Software updates'**
  String get settingsUpdates;

  /// No description provided for @updateAutoCheck.
  ///
  /// In en, this message translates to:
  /// **'Check automatically'**
  String get updateAutoCheck;

  /// No description provided for @updateAutoCheckDesc.
  ///
  /// In en, this message translates to:
  /// **'Checks GitHub Releases at most once every 24 hours'**
  String get updateAutoCheckDesc;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updateChecking;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available'**
  String updateAvailable(String version);

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You\'re using the latest version'**
  String get updateUpToDate;

  /// No description provided for @updateNeverChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet'**
  String get updateNeverChecked;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for updates'**
  String get updateCheckFailed;

  /// No description provided for @updateCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get updateCheckNow;

  /// No description provided for @updateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download update'**
  String get updateDownload;

  /// No description provided for @updateOpenRelease.
  ///
  /// In en, this message translates to:
  /// **'View release'**
  String get updateOpenRelease;

  /// No description provided for @updateOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the update link'**
  String get updateOpenFailed;

  /// No description provided for @updateInstallNote.
  ///
  /// In en, this message translates to:
  /// **'Your device will ask for confirmation before installing.'**
  String get updateInstallNote;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {v}'**
  String settingsVersion(String v);

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Transfers stay on your network. Update checks contact GitHub only; no files or analytics are sent.'**
  String get settingsPrivacy;

  /// No description provided for @settingsRestartRequired.
  ///
  /// In en, this message translates to:
  /// **'Restart required to apply'**
  String get settingsRestartRequired;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @qrTitle.
  ///
  /// In en, this message translates to:
  /// **'My address'**
  String get qrTitle;

  /// No description provided for @qrBody.
  ///
  /// In en, this message translates to:
  /// **'Scan or type this on another device to connect directly.'**
  String get qrBody;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'192.168.1.20 or 192.168.1.20:53317'**
  String get addressHint;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @deviceNotReachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach that address. Is Suvi Share open there?'**
  String get deviceNotReachable;

  /// No description provided for @errNoWifiTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re not connected to Wi-Fi'**
  String get errNoWifiTitle;

  /// No description provided for @errNoWifiBody.
  ///
  /// In en, this message translates to:
  /// **'Suvi Share works over your local network. Connect to Wi-Fi or turn on a hotspot.'**
  String get errNoWifiBody;

  /// No description provided for @errFirewallTitle.
  ///
  /// In en, this message translates to:
  /// **'A firewall may be blocking Suvi Share'**
  String get errFirewallTitle;

  /// No description provided for @errFirewallBody.
  ///
  /// In en, this message translates to:
  /// **'Allow Suvi Share on private networks so other devices can reach it.'**
  String get errFirewallBody;

  /// No description provided for @errBusy.
  ///
  /// In en, this message translates to:
  /// **'{alias} is receiving another transfer. Try again in a moment.'**
  String errBusy(String alias);

  /// No description provided for @errPin.
  ///
  /// In en, this message translates to:
  /// **'PIN required or incorrect'**
  String get errPin;

  /// No description provided for @clipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get clipboardEmpty;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// No description provided for @scanQrHint.
  ///
  /// In en, this message translates to:
  /// **'Point at the QR shown on the other device'**
  String get scanQrHint;

  /// No description provided for @connectedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected to {alias}'**
  String connectedTo(String alias);

  /// No description provided for @developedBy.
  ///
  /// In en, this message translates to:
  /// **'Developed by vikas0vks'**
  String get developedBy;

  /// No description provided for @peerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach {alias}. Open Suvi Share on that device — the list will refresh.'**
  String peerUnreachable(String alias);

  /// No description provided for @enterPin.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get enterPin;

  /// No description provided for @pinHint.
  ///
  /// In en, this message translates to:
  /// **'4–8 digits'**
  String get pinHint;

  /// No description provided for @webShareSessionPin.
  ///
  /// In en, this message translates to:
  /// **'Session PIN'**
  String get webShareSessionPin;

  /// No description provided for @identityVerificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Device identity could not be verified. Trust was not changed.'**
  String get identityVerificationFailed;

  /// No description provided for @openLocationFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open this folder on this device.'**
  String get openLocationFailed;

  /// No description provided for @fileTypeImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get fileTypeImage;

  /// No description provided for @fileTypeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get fileTypeVideo;

  /// No description provided for @fileTypeAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get fileTypeAudio;

  /// No description provided for @fileTypeDocument.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get fileTypeDocument;

  /// No description provided for @fileTypeApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get fileTypeApp;

  /// No description provided for @fileTypeOther.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get fileTypeOther;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
