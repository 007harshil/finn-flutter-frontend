import 'package:url_launcher/url_launcher.dart';

import '../../data/remote/api_config.dart';

/// Public pages and contacts the app links to (Google Play requires the
/// privacy policy to be reachable from inside the app).
abstract final class LegalLinks {
  static final privacyPolicy = Uri.parse('${ApiConfig.defaultApiUrl}/privacy');
  static final deleteAccount = Uri.parse('${ApiConfig.defaultApiUrl}/delete-account');
  static const supportEmail = 'finn.team007@gmail.com';
  static final support = Uri(scheme: 'mailto', path: supportEmail, query: 'subject=FiNN%20support');

  /// Opens [uri] outside the app. False when nothing could open it.
  static Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
