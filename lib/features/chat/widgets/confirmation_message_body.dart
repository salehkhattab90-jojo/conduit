import 'package:flutter/widgets.dart';

/// Inert renderer for the text of a server `confirmation` prompt.
///
/// The text comes from a model or a tool (an email it is about to send, say),
/// so it is untrusted and never goes through the app's markdown pipeline,
/// which can load remote images and route diagrams or HTML through a web
/// view. Only two marks are honoured: `**bold**` spans and `>` blockquote
/// lines. Everything else, links and HTML included, is shown as literal text,
/// with no gesture recognisers, images or web views, so nothing in the body
/// can act or be tapped. A quoted line is drawn as a quote, so quoted content
/// cannot pass itself off as the prompt's own labels. Each line takes the
/// ambient text direction.
class ConfirmationMessageBody extends StatelessWidget {
  const ConfirmationMessageBody({
    super.key,
    required this.message,
    required this.style,
    required this.quoteColor,
    required this.quoteBorderColor,
  });

  final String message;

  /// Style of ordinary lines; bold spans add weight to it.
  final TextStyle style;

  /// Text colour of quoted lines.
  final Color quoteColor;

  /// Colour of the bar beside quoted lines.
  final Color quoteBorderColor;

  @override
  Widget build(BuildContext context) {
    final lines = message.replaceAll('\r\n', '\n').split('\n');
    final children = <Widget>[];
    for (final line in lines) {
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 6));
        continue;
      }
      final trimmedLeft = line.trimLeft();
      if (trimmedLeft == '>' || trimmedLeft.startsWith('> ')) {
        final quoted = trimmedLeft.replaceFirst(RegExp(r'^>\s?'), '');
        children.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsetsDirectional.only(start: 8),
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: quoteBorderColor, width: 2),
              ),
            ),
            child: Text.rich(
              _inlineSpans(quoted, style.copyWith(color: quoteColor)),
              textAlign: TextAlign.start,
            ),
          ),
        );
        continue;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text.rich(
            _inlineSpans(line, style),
            textAlign: TextAlign.start,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// `**bold**` spans over literal text. Pure [TextSpan]s with no recognisers,
/// so nothing in them is tappable. An unmatched `**` stays literal.
TextSpan _inlineSpans(String line, TextStyle base) {
  final parts = line.split('**');
  // An even number of parts means one `**` has no partner: keep the last
  // marker as text instead of bolding the rest of the line.
  final unmatched = parts.length.isEven;
  final spans = <TextSpan>[];
  for (var i = 0; i < parts.length; i++) {
    final isLastUnmatched = unmatched && i == parts.length - 1;
    final text = isLastUnmatched ? '**${parts[i]}' : parts[i];
    if (text.isEmpty) continue;
    final bold = i.isOdd && !isLastUnmatched;
    spans.add(
      TextSpan(
        text: text,
        style: bold ? base.copyWith(fontWeight: FontWeight.w600) : base,
      ),
    );
  }
  return TextSpan(style: base, children: spans);
}
