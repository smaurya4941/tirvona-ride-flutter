import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config_provider.dart';
import '../../core/theme/app_colors.dart';

/// The public legal pages the API serves (also the URLs entered in the Play
/// Console). Opened in the phone's browser.
enum LegalPage { privacy, terms, deleteAccount }

extension LegalPageUrl on WidgetRef {
  Uri legalUri(LegalPage page) {
    final config = read(appConfigProvider);
    return Uri.parse(switch (page) {
      LegalPage.privacy => config.privacyPolicyUrl,
      LegalPage.terms => config.termsUrl,
      LegalPage.deleteAccount => config.deleteAccountUrl,
    });
  }
}

/// Opens [page]; says so when no browser can.
Future<void> openLegalPage(
  BuildContext context,
  WidgetRef ref,
  LegalPage page,
) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      ref.legalUri(page),
      mode: LaunchMode.externalApplication,
    );
  } on Object {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open the page. Try again.')),
    );
  }
}

/// "By continuing you agree to the Terms of use and Privacy policy."
class LegalConsentText extends ConsumerStatefulWidget {
  const LegalConsentText({super.key});

  @override
  ConsumerState<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends ConsumerState<LegalConsentText> {
  late final TapGestureRecognizer _terms;
  late final TapGestureRecognizer _privacy;

  @override
  void initState() {
    super.initState();
    _terms = TapGestureRecognizer()
      ..onTap = () => openLegalPage(context, ref, LegalPage.terms);
    _privacy = TapGestureRecognizer()
      ..onTap = () => openLegalPage(context, ref, LegalPage.privacy);
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant);
    final link = base?.copyWith(
      color: AppColors.bhagwaDark,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'By continuing you agree to the '),
          TextSpan(text: 'Terms of use', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
