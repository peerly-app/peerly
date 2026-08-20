import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';

const _nativeNames = {
  'en': 'English',
  'fr': 'Français',
  'es': 'Español',
  'de': 'Deutsch',
  'it': 'Italiano',
  'pt': 'Português',
};

String languageDisplayName(Locale locale) =>
    _nativeNames[locale.languageCode] ?? locale.languageCode;

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeService = context.watch<LocaleService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsLanguage, style: AppTypography.screenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final locale in supportedLocales) ...[
                  InkWell(
                    onTap: () => localeService.setLocale(locale),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              languageDisplayName(locale),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 15,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          if (locale.languageCode ==
                              localeService.locale.languageCode)
                            const Icon(
                              Icons.check,
                              size: 18,
                              color: AppColors.accent,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (locale != supportedLocales.last)
                    const Divider(
                      color: AppColors.borderSubtle,
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
