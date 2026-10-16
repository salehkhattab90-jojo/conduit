import 'dart:async';

import 'package:conduit_core/features/chat/utils/document_deliveries.dart';
import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/platform_page_route.dart';
import '../../../shared/utils/utf16_sanitizer.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/platform_ui/vocabulary.dart';
import 'document_preview_page.dart';

/// Identity colour of a delivered file's format, or null for a format with
/// no identity (shown in the neutral tone, still with its extension badge).
///
/// The list is open-ended on purpose: an unknown extension is never assumed
/// to be one of these.
Color? deliveryIdentityColor(String? extension) => switch (extension) {
  'doc' || 'docx' || 'odt' || 'rtf' => const Color(0xFF3B82F6),
  'xls' || 'xlsx' || 'csv' || 'tsv' || 'ods' => const Color(0xFF10B981),
  'ppt' || 'pptx' || 'odp' => const Color(0xFFF97316),
  'pdf' => const Color(0xFFEF4444),
  'html' || 'htm' || 'svg' => const Color(0xFF8B5CF6),
  'md' || 'markdown' || 'txt' => const Color(0xFF6B7280),
  _ => null,
};

/// One delivered file in a chat message: an identity tile with the file's
/// real extension, its name, a hint and a chevron.
class DeliveryCard extends StatelessWidget {
  const DeliveryCard({
    super.key,
    required this.title,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.extension,
  });

  final String title;
  final String hint;
  final IconData icon;
  final String? extension;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final extension = this.extension;
    final identity = deliveryIdentityColor(extension) ?? theme.textSecondary;
    final title = sanitizeUtf16(this.title);

    return Semantics(
      button: true,
      label: '$title, $hint',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: ConduitCard(
          isCompact: true,
          padding: const EdgeInsets.all(Spacing.md),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: identity.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                    ),
                    child: Icon(icon, size: 20, color: identity),
                  ),
                  if (extension != null)
                    Positioned(
                      bottom: -5,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.textPrimary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            extension.toUpperCase(),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 7,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: theme.cardBackground,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMediumStyle.copyWith(
                        color: theme.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Icon(Icons.chevron_right, size: 18, color: theme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cards of a message's generated documents, one per delivery.
class DocumentDeliveryCards extends StatelessWidget {
  const DocumentDeliveryCards({super.key, required this.deliveries});

  final List<DocumentDelivery> deliveries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < deliveries.length; index++) ...[
          if (index > 0) const SizedBox(height: Spacing.sm),
          _documentCard(context, l10n, deliveries[index]),
        ],
      ],
    );
  }

  Widget _documentCard(
    BuildContext context,
    AppLocalizations l10n,
    DocumentDelivery delivery,
  ) {
    final title =
        delivery.displayName ??
        (delivery.isArtifact ? l10n.artifact : l10n.document);
    return DeliveryCard(
      key: ValueKey('document-delivery-${delivery.key}'),
      title: title,
      hint: delivery.isArtifact ? l10n.artifactCardHint : l10n.documentCardHint,
      icon: delivery.isArtifact
          ? Icons.widgets_outlined
          : Icons.description_outlined,
      extension: delivery.extension,
      onTap: () => unawaited(
        Navigator.of(context, rootNavigator: true).push(
          buildPlatformPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) =>
                DocumentPreviewPage(delivery: delivery, title: title),
          ),
        ),
      ),
    );
  }
}
