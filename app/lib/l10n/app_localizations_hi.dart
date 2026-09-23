// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'Suvi Share';

  @override
  String get tagline => 'कमरे के पार भेजें, इंटरनेट के पार नहीं।';

  @override
  String get navNearby => 'आस-पास';

  @override
  String get navTransfers => 'ट्रांसफ़र';

  @override
  String get navSettings => 'सेटिंग्स';

  @override
  String get onboardingWelcomeTitle =>
      'अपने Wi-Fi पर फ़ाइलें शेयर करें।\nन क्लाउड, न अकाउंट।';

  @override
  String get onboardingWelcomeBody =>
      'Suvi Share आपकी फ़ोटो, वीडियो, डॉक्यूमेंट और टेक्स्ट को आपके लोकल नेटवर्क पर एक डिवाइस से दूसरे तक पहुँचाता है। कुछ भी आपके घर से बाहर नहीं जाता।';

  @override
  String get onboardingGetStarted => 'शुरू करें';

  @override
  String get onboardingNameTitle => 'आपके डिवाइस का नाम';

  @override
  String get onboardingNameBody => 'दूसरे डिवाइस आपको इसी नाम से देखेंगे।';

  @override
  String get onboardingNameHint => 'डिवाइस का नाम';

  @override
  String get onboardingShuffle => 'नया नाम';

  @override
  String get onboardingReceiveTitle => 'फ़ाइलें कैसे मिलें?';

  @override
  String get onboardingReceiveBody =>
      'आप इसे कभी भी सेटिंग्स में बदल सकते हैं।';

  @override
  String get receiveModeAsk => 'हर बार मुझसे पूछो';

  @override
  String get receiveModeAskDesc =>
      'कौन क्या भेज रहा है दिखेगा, फिर आप स्वीकार या अस्वीकार करें।';

  @override
  String get receiveModeTrusted => 'भरोसेमंद डिवाइस से अपने-आप सेव';

  @override
  String get receiveModeTrustedDesc =>
      'जिन्हें आपने भरोसेमंद बनाया है वे बिना पूछे भेज सकते हैं। बाकी पूछेंगे।';

  @override
  String get receiveModePin => 'PIN ज़रूरी';

  @override
  String get receiveModePinDesc => 'भेजने वाले को पहले आपका PIN डालना होगा।';

  @override
  String get onboardingFinish => 'शेयर करना शुरू करें';

  @override
  String get next => 'आगे';

  @override
  String get back => 'पीछे';

  @override
  String get skip => 'छोड़ें';

  @override
  String youAre(String alias) {
    return 'आप हैं $alias';
  }

  @override
  String visibleOn(String ip) {
    return 'आपके नेटवर्क पर दिख रहे हैं · $ip';
  }

  @override
  String get notConnected => 'Wi-Fi से कनेक्ट नहीं';

  @override
  String get receiveOn => 'रिसीव चालू';

  @override
  String get receiveOff => 'रिसीव बंद';

  @override
  String get lookingForDevices => 'नेटवर्क पर डिवाइस खोज रहे हैं…';

  @override
  String get nearbyDevices => 'आस-पास के डिवाइस';

  @override
  String get favorites => 'पसंदीदा';

  @override
  String get recentlySeen => 'हाल में देखे';

  @override
  String get noDevicesTitle => 'अभी कोई डिवाइस नहीं';

  @override
  String get noDevicesBody =>
      'दूसरे डिवाइस पर Suvi Share खोलें। दोनों एक ही Wi-Fi पर होने चाहिए।';

  @override
  String get tipSameWifi => 'एक ही Wi-Fi?';

  @override
  String get tipFirewall => 'फ़ायरवॉल अनुमति?';

  @override
  String get tipOpenApp => 'दूसरे डिवाइस पर Suvi खोलें';

  @override
  String get enterAddress => 'पता डालें';

  @override
  String get scanNetwork => 'नेटवर्क स्कैन करें';

  @override
  String scanning(int done, int total) {
    return '$total में से $done स्कैन…';
  }

  @override
  String get showMyQr => 'मेरा QR दिखाएँ';

  @override
  String get refresh => 'रिफ़्रेश';

  @override
  String get send => 'भेजें';

  @override
  String sendTo(String alias) {
    return '$alias को भेजें';
  }

  @override
  String get trusted => 'भरोसेमंद';

  @override
  String get unverified => 'असत्यापित';

  @override
  String get blocked => 'ब्लॉक';

  @override
  String get favorite => 'पसंदीदा';

  @override
  String get unfavorite => 'पसंदीदा हटाएँ';

  @override
  String get trustDevice => 'इस डिवाइस पर भरोसा करें';

  @override
  String get untrustDevice => 'भरोसा हटाएँ';

  @override
  String get blockDevice => 'ब्लॉक करें';

  @override
  String get unblockDevice => 'अनब्लॉक करें';

  @override
  String get deviceDetails => 'विवरण';

  @override
  String get pickFiles => 'फ़ाइलें';

  @override
  String get pickMedia => 'फ़ोटो और वीडियो';

  @override
  String get pickFolder => 'फ़ोल्डर';

  @override
  String get pickText => 'टेक्स्ट';

  @override
  String get pickClipboard => 'क्लिपबोर्ड';

  @override
  String get whatToSend => 'क्या भेजना है?';

  @override
  String get browseByCategory => 'कैटेगरी से चुनें';

  @override
  String get moreWaysToShare => 'शेयर करने के दूसरे तरीके';

  @override
  String get continueToDevice => 'रिसीव करने वाला डिवाइस चुनें';

  @override
  String get filePickerFailed => 'फ़ाइल पिकर नहीं खुल सका। फिर कोशिश करें।';

  @override
  String get categoryGeneral => 'सभी फ़ाइलें';

  @override
  String get categoryGeneralDesc => 'किसी भी तरह की फ़ाइल';

  @override
  String get categoryDocuments => 'डॉक्यूमेंट';

  @override
  String get categoryDocumentsDesc => 'PDF, Office और टेक्स्ट';

  @override
  String get categoryImages => 'फ़ोटो';

  @override
  String get categoryImagesDesc => 'इमेज और स्क्रीनशॉट';

  @override
  String get categoryVideos => 'वीडियो';

  @override
  String get categoryVideosDesc => 'मूवी और क्लिप';

  @override
  String get categoryMusic => 'म्यूज़िक';

  @override
  String get categoryMusicDesc => 'ऑडियो और रिकॉर्डिंग';

  @override
  String get categoryCompressed => 'कम्प्रेस्ड';

  @override
  String get categoryCompressedDesc => 'ZIP, RAR, 7Z और अन्य';

  @override
  String get categoryOther => 'अन्य फ़ाइलें';

  @override
  String get categoryOtherDesc => 'ऐप, डेटा और पैकेज';

  @override
  String get chooseDevice => 'डिवाइस चुनें';

  @override
  String itemsSelected(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count आइटम',
      one: '1 आइटम',
    );
    return '$_temp0 · $size';
  }

  @override
  String get addMore => 'और जोड़ें';

  @override
  String get clearSelection => 'हटाएँ';

  @override
  String get textToSend => 'भेजने के लिए टेक्स्ट';

  @override
  String get typeSomething => 'कुछ लिखें या पेस्ट करें…';

  @override
  String waitingForAccept(String alias) {
    return '$alias के स्वीकार करने का इंतज़ार…';
  }

  @override
  String sendingTo(String alias) {
    return '$alias को भेज रहे हैं';
  }

  @override
  String sentTo(String alias) {
    return '$alias को भेजा';
  }

  @override
  String declinedBy(String alias) {
    return '$alias ने मना किया';
  }

  @override
  String get transferFailed => 'ट्रांसफ़र विफल';

  @override
  String get transferCancelled => 'रद्द';

  @override
  String get sendMore => 'और भेजें';

  @override
  String get done => 'हो गया';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get retry => 'फिर कोशिश';

  @override
  String get close => 'बंद करें';

  @override
  String progressLine(String done, String total, String speed) {
    return '$total में से $done · $speed/s';
  }

  @override
  String incomingTitle(String alias) {
    return '$alias आपको भेजना चाहता है';
  }

  @override
  String incomingFiles(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count फ़ाइलें',
      one: '1 फ़ाइल',
    );
    return '$_temp0 · $size';
  }

  @override
  String get incomingText => 'एक संदेश';

  @override
  String savesTo(String path) {
    return 'सेव होगा: $path';
  }

  @override
  String get change => 'बदलें';

  @override
  String get accept => 'स्वीकार';

  @override
  String get decline => 'मना करें';

  @override
  String alwaysAcceptFrom(String alias) {
    return '$alias से हमेशा स्वीकार करें';
  }

  @override
  String receivingFrom(String alias) {
    return '$alias से आ रहा है';
  }

  @override
  String receivedFrom(String alias) {
    return '$alias से मिला';
  }

  @override
  String savedTo(String path) {
    return 'सेव हुआ: $path';
  }

  @override
  String get open => 'खोलें';

  @override
  String get showInFolder => 'फ़ोल्डर में दिखाएँ';

  @override
  String get copy => 'कॉपी';

  @override
  String get copied => 'क्लिपबोर्ड पर कॉपी हुआ';

  @override
  String moreFiles(int count) {
    return '+$count और';
  }

  @override
  String get active => 'चालू';

  @override
  String get history => 'इतिहास';

  @override
  String get noTransfersYet => 'अभी कोई ट्रांसफ़र नहीं';

  @override
  String get noTransfersBody => 'आपकी भेजी और मिली फ़ाइलें यहाँ दिखेंगी।';

  @override
  String get clearHistory => 'इतिहास साफ़ करें';

  @override
  String get today => 'आज';

  @override
  String get yesterday => 'कल';

  @override
  String get sent => 'भेजा';

  @override
  String get received => 'मिला';

  @override
  String get failed => 'विफल';

  @override
  String get cancelled => 'रद्द';

  @override
  String get declined => 'अस्वीकृत';

  @override
  String get settingsDevice => 'डिवाइस';

  @override
  String get settingsDeviceName => 'डिवाइस का नाम';

  @override
  String get settingsAvatarColor => 'अवतार रंग';

  @override
  String get settingsShowAddress => 'मेरा पता और QR';

  @override
  String get settingsReceiving => 'रिसीविंग';

  @override
  String get settingsReceiveMode => 'रिसीव मोड';

  @override
  String get settingsPin => 'PIN';

  @override
  String get settingsPinDesc => 'भेजने वाले को यह PIN डालना होगा';

  @override
  String get settingsQuickSave => 'Quick Save';

  @override
  String get settingsQuickSaveDesc =>
      'बिना पूछे सब स्वीकार — सिर्फ़ भरोसेमंद नेटवर्क पर';

  @override
  String get settingsSaveFolder => 'सेव फ़ोल्डर';

  @override
  String get settingsTrustedDevices => 'भरोसेमंद डिवाइस';

  @override
  String get settingsNoTrusted =>
      'अभी कोई भरोसेमंद डिवाइस नहीं। आस-पास स्क्रीन पर डिवाइस के मेन्यू से जोड़ें।';

  @override
  String get settingsNetwork => 'नेटवर्क';

  @override
  String get settingsPort => 'पोर्ट';

  @override
  String get settingsPortDesc =>
      'डिफ़ॉल्ट 53317। तभी बदलें जब कोई और ऐप इसे इस्तेमाल करे।';

  @override
  String get settingsEncryption => 'एन्क्रिप्शन';

  @override
  String settingsEncryptionDesc(String fp) {
    return 'TLS · फ़िंगरप्रिंट $fp';
  }

  @override
  String get settingsWebShare => 'वेब शेयर';

  @override
  String get settingsWebShareDesc =>
      'इस Wi-Fi के किसी भी ब्राउज़र से फ़ाइलें भेजें और पाएँ — ऐप की ज़रूरत नहीं';

  @override
  String get webShareOn => 'ब्राउज़र में यह पता खोलें';

  @override
  String get webShareOff => 'वेब शेयर बंद है';

  @override
  String get webShareHttpNote =>
      'साधारण HTTP पर चलता है क्योंकि ब्राउज़र सेल्फ़-साइन्ड सर्टिफ़िकेट नहीं मानते। साझा नेटवर्क पर PIN लगाएँ।';

  @override
  String get webShareNoWifi => 'पहले Wi-Fi से जुड़ें';

  @override
  String get shareViaLink => 'लिंक से शेयर करें';

  @override
  String get settingsAppearance => 'दिखावट';

  @override
  String get settingsTheme => 'थीम';

  @override
  String get themeSystem => 'सिस्टम';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeDark => 'डार्क';

  @override
  String get settingsDynamicColor => 'वॉलपेपर के रंग';

  @override
  String get settingsPaletteHint =>
      'पैलेट चुनने पर वॉलपेपर के रंग बंद हो जाते हैं';

  @override
  String get settingsColorPalette => 'कलर पैलेट';

  @override
  String get paletteSuvi => 'सुवी';

  @override
  String get paletteOcean => 'ओशन';

  @override
  String get paletteSunset => 'सनसेट';

  @override
  String get paletteForest => 'फॉरेस्ट';

  @override
  String get paletteLavender => 'लैवेंडर';

  @override
  String get paletteRose => 'रोज़';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsDesktop => 'डेस्कटॉप';

  @override
  String get settingsMinimizeToTray => 'बंद करने पर ट्रे में रखें';

  @override
  String get settingsMinimizeToTrayDesc =>
      'विंडो बंद होने पर भी रिसीव करते रहें';

  @override
  String get settingsUpdates => 'सॉफ़्टवेयर अपडेट';

  @override
  String get updateAutoCheck => 'अपने-आप जाँचें';

  @override
  String get updateAutoCheckDesc =>
      'हर 24 घंटे में अधिकतम एक बार GitHub Releases जाँचता है';

  @override
  String get updateChecking => 'अपडेट जाँचा जा रहा है…';

  @override
  String updateAvailable(String version) {
    return 'वर्ज़न $version उपलब्ध है';
  }

  @override
  String get updateUpToDate => 'आप सबसे नया वर्ज़न इस्तेमाल कर रहे हैं';

  @override
  String get updateNeverChecked => 'अभी जाँच नहीं हुई';

  @override
  String get updateCheckFailed => 'अपडेट जाँच नहीं सकी';

  @override
  String get updateCheckNow => 'अभी जाँचें';

  @override
  String get updateDownload => 'अपडेट डाउनलोड करें';

  @override
  String get updateOpenRelease => 'रिलीज़ देखें';

  @override
  String get updateOpenFailed => 'अपडेट लिंक नहीं खुल सका';

  @override
  String get updateInstallNote =>
      'इंस्टॉल करने से पहले आपका डिवाइस पुष्टि माँगेगा।';

  @override
  String get settingsAbout => 'जानकारी';

  @override
  String settingsVersion(String v) {
    return 'वर्ज़न $v';
  }

  @override
  String get settingsPrivacy =>
      'ट्रांसफ़र आपके नेटवर्क पर रहते हैं। अपडेट जाँच सिर्फ़ GitHub से जुड़ती है; कोई फ़ाइल या एनालिटिक्स नहीं भेजे जाते।';

  @override
  String get settingsRestartRequired => 'लागू करने के लिए रीस्टार्ट करें';

  @override
  String get save => 'सेव';

  @override
  String get qrTitle => 'मेरा पता';

  @override
  String get qrBody =>
      'सीधे जुड़ने के लिए दूसरे डिवाइस पर इसे स्कैन करें या टाइप करें।';

  @override
  String get addressHint => '192.168.1.20 या 192.168.1.20:53317';

  @override
  String get connect => 'जोड़ें';

  @override
  String get deviceNotReachable =>
      'इस पते तक नहीं पहुँच सके। क्या वहाँ Suvi Share खुला है?';

  @override
  String get errNoWifiTitle => 'आप Wi-Fi से कनेक्ट नहीं हैं';

  @override
  String get errNoWifiBody =>
      'Suvi Share आपके लोकल नेटवर्क पर काम करता है। Wi-Fi से जुड़ें या हॉटस्पॉट चालू करें।';

  @override
  String get errFirewallTitle => 'फ़ायरवॉल Suvi Share को रोक सकता है';

  @override
  String get errFirewallBody =>
      'प्राइवेट नेटवर्क पर Suvi Share को अनुमति दें ताकि दूसरे डिवाइस पहुँच सकें।';

  @override
  String errBusy(String alias) {
    return '$alias अभी दूसरा ट्रांसफ़र ले रहा है। थोड़ी देर में कोशिश करें।';
  }

  @override
  String get errPin => 'PIN ज़रूरी या गलत';

  @override
  String get clipboardEmpty => 'क्लिपबोर्ड खाली है';

  @override
  String get scanQr => 'QR स्कैन करें';

  @override
  String get scanQrHint => 'दूसरे डिवाइस पर दिख रहे QR पर कैमरा रखें';

  @override
  String connectedTo(String alias) {
    return '$alias से जुड़ गए';
  }

  @override
  String get developedBy => 'Developed by vikas0vks';

  @override
  String peerUnreachable(String alias) {
    return '$alias तक नहीं पहुँच सके। उस डिवाइस पर Suvi Share खोलें — सूची अपने-आप ताज़ा हो जाएगी।';
  }

  @override
  String get enterPin => 'PIN डालें';

  @override
  String get pinHint => '4–8 अंक';

  @override
  String get webShareSessionPin => 'सेशन PIN';

  @override
  String get identityVerificationFailed =>
      'डिवाइस की पहचान सत्यापित नहीं हुई। भरोसे की सेटिंग नहीं बदली गई।';

  @override
  String get openLocationFailed => 'इस डिवाइस पर यह फ़ोल्डर नहीं खुल सका।';

  @override
  String get fileTypeImage => 'फ़ोटो';

  @override
  String get fileTypeVideo => 'वीडियो';

  @override
  String get fileTypeAudio => 'ऑडियो';

  @override
  String get fileTypeDocument => 'डॉक्यूमेंट';

  @override
  String get fileTypeApp => 'ऐप';

  @override
  String get fileTypeOther => 'फ़ाइल';
}
