// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Suvi Share';

  @override
  String get tagline => 'Share across the room, not across the internet.';

  @override
  String get navNearby => 'Nearby';

  @override
  String get navTransfers => 'Transfers';

  @override
  String get navSettings => 'Settings';

  @override
  String get onboardingWelcomeTitle =>
      'Share files on your Wi-Fi.\nNo cloud, no account.';

  @override
  String get onboardingWelcomeBody =>
      'Suvi Share moves photos, videos, documents and text between your devices over your local network. Nothing ever leaves your home.';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingNameTitle => 'Your device name';

  @override
  String get onboardingNameBody => 'This is how other devices will see you.';

  @override
  String get onboardingNameHint => 'Device name';

  @override
  String get onboardingShuffle => 'Shuffle name';

  @override
  String get onboardingReceiveTitle => 'How should receiving work?';

  @override
  String get onboardingReceiveBody =>
      'You can change this anytime in Settings.';

  @override
  String get receiveModeAsk => 'Ask me every time';

  @override
  String get receiveModeAskDesc =>
      'You\'ll see who\'s sending and what, then accept or decline.';

  @override
  String get receiveModeTrusted => 'Auto-save from trusted devices';

  @override
  String get receiveModeTrustedDesc =>
      'Devices you\'ve marked as trusted send without asking. Others still ask.';

  @override
  String get receiveModePin => 'Require a PIN';

  @override
  String get receiveModePinDesc =>
      'Senders must enter your PIN before anything arrives.';

  @override
  String get onboardingFinish => 'Start sharing';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get skip => 'Skip';

  @override
  String youAre(String alias) {
    return 'You are $alias';
  }

  @override
  String visibleOn(String ip) {
    return 'Visible on your network · $ip';
  }

  @override
  String get notConnected => 'Not connected to Wi-Fi';

  @override
  String get receiveOn => 'Receiving';

  @override
  String get receiveOff => 'Receiving off';

  @override
  String get lookingForDevices => 'Looking for devices on your network…';

  @override
  String get nearbyDevices => 'Nearby devices';

  @override
  String get favorites => 'Favorites';

  @override
  String get recentlySeen => 'Recently seen';

  @override
  String get noDevicesTitle => 'No devices yet';

  @override
  String get noDevicesBody =>
      'Open Suvi Share on the other device. Both must be on the same Wi-Fi.';

  @override
  String get tipSameWifi => 'Same Wi-Fi?';

  @override
  String get tipFirewall => 'Firewall allowed?';

  @override
  String get tipOpenApp => 'Open Suvi on the other device';

  @override
  String get enterAddress => 'Enter address';

  @override
  String get scanNetwork => 'Scan network';

  @override
  String scanning(int done, int total) {
    return 'Scanning $done of $total…';
  }

  @override
  String get showMyQr => 'Show my QR';

  @override
  String get refresh => 'Refresh';

  @override
  String get send => 'Send';

  @override
  String sendTo(String alias) {
    return 'Send to $alias';
  }

  @override
  String get trusted => 'Trusted';

  @override
  String get unverified => 'Unverified';

  @override
  String get blocked => 'Blocked';

  @override
  String get favorite => 'Favorite';

  @override
  String get unfavorite => 'Remove favorite';

  @override
  String get trustDevice => 'Trust this device';

  @override
  String get untrustDevice => 'Remove trust';

  @override
  String get blockDevice => 'Block';

  @override
  String get unblockDevice => 'Unblock';

  @override
  String get deviceDetails => 'Details';

  @override
  String get pickFiles => 'Files';

  @override
  String get pickMedia => 'Photos & videos';

  @override
  String get pickFolder => 'Folder';

  @override
  String get pickText => 'Text';

  @override
  String get pickClipboard => 'Clipboard';

  @override
  String get whatToSend => 'What do you want to send?';

  @override
  String get browseByCategory => 'Browse by category';

  @override
  String get moreWaysToShare => 'More ways to share';

  @override
  String get continueToDevice => 'Choose receiving device';

  @override
  String get filePickerFailed =>
      'Couldn\'t open the file picker. Please try again.';

  @override
  String get categoryGeneral => 'General';

  @override
  String get categoryGeneralDesc => 'Any file type';

  @override
  String get categoryDocuments => 'Documents';

  @override
  String get categoryDocumentsDesc => 'PDF, Office & text';

  @override
  String get categoryImages => 'Photos';

  @override
  String get categoryImagesDesc => 'Images & screenshots';

  @override
  String get categoryVideos => 'Videos';

  @override
  String get categoryVideosDesc => 'Movies & clips';

  @override
  String get categoryMusic => 'Music';

  @override
  String get categoryMusicDesc => 'Audio & recordings';

  @override
  String get categoryCompressed => 'Compressed';

  @override
  String get categoryCompressedDesc => 'ZIP, RAR, 7Z & more';

  @override
  String get categoryOther => 'Other files';

  @override
  String get categoryOtherDesc => 'Apps, data & packages';

  @override
  String get chooseDevice => 'Choose a device';

  @override
  String itemsSelected(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0 · $size';
  }

  @override
  String get addMore => 'Add more';

  @override
  String get clearSelection => 'Clear';

  @override
  String get textToSend => 'Text to send';

  @override
  String get typeSomething => 'Type or paste something…';

  @override
  String waitingForAccept(String alias) {
    return 'Waiting for $alias to accept…';
  }

  @override
  String sendingTo(String alias) {
    return 'Sending to $alias';
  }

  @override
  String sentTo(String alias) {
    return 'Sent to $alias';
  }

  @override
  String declinedBy(String alias) {
    return '$alias declined';
  }

  @override
  String get transferFailed => 'Transfer failed';

  @override
  String get transferCancelled => 'Cancelled';

  @override
  String get sendMore => 'Send more';

  @override
  String get done => 'Done';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';

  @override
  String progressLine(String done, String total, String speed) {
    return '$done of $total · $speed/s';
  }

  @override
  String incomingTitle(String alias) {
    return '$alias wants to send you';
  }

  @override
  String incomingFiles(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0 · $size';
  }

  @override
  String get incomingText => 'A message';

  @override
  String savesTo(String path) {
    return 'Saves to $path';
  }

  @override
  String get change => 'Change';

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String alwaysAcceptFrom(String alias) {
    return 'Always accept from $alias';
  }

  @override
  String receivingFrom(String alias) {
    return 'Receiving from $alias';
  }

  @override
  String receivedFrom(String alias) {
    return 'Received from $alias';
  }

  @override
  String savedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get open => 'Open';

  @override
  String get showInFolder => 'Show in folder';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied to clipboard';

  @override
  String moreFiles(int count) {
    return '+$count more';
  }

  @override
  String get active => 'Active';

  @override
  String get history => 'History';

  @override
  String get noTransfersYet => 'No transfers yet';

  @override
  String get noTransfersBody => 'Files you send and receive will show up here.';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get sent => 'Sent';

  @override
  String get received => 'Received';

  @override
  String get failed => 'Failed';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get declined => 'Declined';

  @override
  String get settingsDevice => 'Device';

  @override
  String get settingsDeviceName => 'Device name';

  @override
  String get settingsAvatarColor => 'Avatar color';

  @override
  String get settingsShowAddress => 'Show my address & QR';

  @override
  String get settingsReceiving => 'Receiving';

  @override
  String get settingsReceiveMode => 'Receive mode';

  @override
  String get settingsPin => 'PIN';

  @override
  String get settingsPinDesc => 'Senders must enter this PIN';

  @override
  String get settingsQuickSave => 'Quick Save';

  @override
  String get settingsQuickSaveDesc =>
      'Accept everything without asking — use only on networks you trust';

  @override
  String get settingsSaveFolder => 'Save folder';

  @override
  String get settingsTrustedDevices => 'Trusted devices';

  @override
  String get settingsNoTrusted =>
      'No trusted devices yet. Trust a device from its menu on the Nearby screen.';

  @override
  String get settingsNetwork => 'Network';

  @override
  String get settingsPort => 'Port';

  @override
  String get settingsPortDesc =>
      'Default 53317. Change only if another app uses it.';

  @override
  String get settingsEncryption => 'Encryption';

  @override
  String settingsEncryptionDesc(String fp) {
    return 'TLS · Fingerprint $fp';
  }

  @override
  String get settingsWebShare => 'Web share';

  @override
  String get settingsWebShareDesc =>
      'Let any browser on this Wi-Fi send and receive files — no app needed';

  @override
  String get webShareOn => 'Open this address in a browser';

  @override
  String get webShareOff => 'Web share is off';

  @override
  String get webShareHttpNote =>
      'Served over plain HTTP because browsers reject self-signed certificates. Use a PIN on shared networks.';

  @override
  String get webShareNoWifi => 'Connect to Wi-Fi first';

  @override
  String get shareViaLink => 'Share via link';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsDynamicColor => 'Use wallpaper colors';

  @override
  String get settingsPaletteHint =>
      'Choosing a palette turns wallpaper colors off';

  @override
  String get settingsColorPalette => 'Color palette';

  @override
  String get paletteSuvi => 'Suvi';

  @override
  String get paletteOcean => 'Ocean';

  @override
  String get paletteSunset => 'Sunset';

  @override
  String get paletteForest => 'Forest';

  @override
  String get paletteLavender => 'Lavender';

  @override
  String get paletteRose => 'Rose';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsDesktop => 'Desktop';

  @override
  String get settingsMinimizeToTray => 'Close to tray';

  @override
  String get settingsMinimizeToTrayDesc =>
      'Keep receiving when the window is closed';

  @override
  String get settingsUpdates => 'Software updates';

  @override
  String get updateAutoCheck => 'Check automatically';

  @override
  String get updateAutoCheckDesc =>
      'Checks GitHub Releases at most once every 24 hours';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String updateAvailable(String version) {
    return 'Version $version is available';
  }

  @override
  String get updateUpToDate => 'You\'re using the latest version';

  @override
  String get updateNeverChecked => 'Not checked yet';

  @override
  String get updateCheckFailed => 'Couldn\'t check for updates';

  @override
  String get updateCheckNow => 'Check now';

  @override
  String get updateDownload => 'Download update';

  @override
  String get updateOpenRelease => 'View release';

  @override
  String get updateOpenFailed => 'Couldn\'t open the update link';

  @override
  String get updateInstallNote =>
      'Your device will ask for confirmation before installing.';

  @override
  String get settingsAbout => 'About';

  @override
  String settingsVersion(String v) {
    return 'Version $v';
  }

  @override
  String get settingsPrivacy =>
      'Transfers stay on your network. Update checks contact GitHub only; no files or analytics are sent.';

  @override
  String get settingsRestartRequired => 'Restart required to apply';

  @override
  String get save => 'Save';

  @override
  String get qrTitle => 'My address';

  @override
  String get qrBody =>
      'Scan or type this on another device to connect directly.';

  @override
  String get addressHint => '192.168.1.20 or 192.168.1.20:53317';

  @override
  String get connect => 'Connect';

  @override
  String get deviceNotReachable =>
      'Couldn\'t reach that address. Is Suvi Share open there?';

  @override
  String get errNoWifiTitle => 'You\'re not connected to Wi-Fi';

  @override
  String get errNoWifiBody =>
      'Suvi Share works over your local network. Connect to Wi-Fi or turn on a hotspot.';

  @override
  String get errFirewallTitle => 'A firewall may be blocking Suvi Share';

  @override
  String get errFirewallBody =>
      'Allow Suvi Share on private networks so other devices can reach it.';

  @override
  String errBusy(String alias) {
    return '$alias is receiving another transfer. Try again in a moment.';
  }

  @override
  String get errPin => 'PIN required or incorrect';

  @override
  String get clipboardEmpty => 'Clipboard is empty';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get scanQrHint => 'Point at the QR shown on the other device';

  @override
  String connectedTo(String alias) {
    return 'Connected to $alias';
  }

  @override
  String get developedBy => 'Developed by vikas0vks';

  @override
  String peerUnreachable(String alias) {
    return 'Couldn\'t reach $alias. Open Suvi Share on that device — the list will refresh.';
  }

  @override
  String get enterPin => 'Enter PIN';

  @override
  String get pinHint => '4–8 digits';

  @override
  String get webShareSessionPin => 'Session PIN';

  @override
  String get identityVerificationFailed =>
      'Device identity could not be verified. Trust was not changed.';

  @override
  String get openLocationFailed => 'Couldn\'t open this folder on this device.';

  @override
  String get fileTypeImage => 'Image';

  @override
  String get fileTypeVideo => 'Video';

  @override
  String get fileTypeAudio => 'Audio';

  @override
  String get fileTypeDocument => 'Document';

  @override
  String get fileTypeApp => 'App';

  @override
  String get fileTypeOther => 'File';
}
