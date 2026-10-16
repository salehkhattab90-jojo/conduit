/// Whether [raw] is a structured preview embed:
/// `{type: 'preview', url, name, content_type}`.
///
/// A document tool can deliver a real file in `files[]` together with this
/// object, whose `url` points at a rendered preview of that file (usually a
/// PDF). It is distinct from the legacy embed shape, a self-contained HTML
/// string, and must never be rendered as one.
bool isPreviewEmbed(Object? raw) {
  if (raw is! Map) return false;
  if (raw['type']?.toString() != 'preview') return false;
  final url = raw['url']?.toString().trim();
  return url != null && url.isNotEmpty;
}

String? extractEmbedSource(Object? raw) {
  if (raw is String) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (raw is Map) {
    for (final key in const ['src', 'url', 'html', 'content']) {
      final value = raw[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
  }

  return null;
}

List<Map<String, dynamic>> normalizeEmbedList(dynamic raw) {
  if (raw is! List) {
    return const <Map<String, dynamic>>[];
  }

  final embeds = <Map<String, dynamic>>[];
  for (final entry in raw) {
    final source = extractEmbedSource(entry);
    if (source == null) {
      continue;
    }

    if (entry is Map) {
      final normalized = <String, dynamic>{};
      entry.forEach((key, value) {
        normalized[key.toString()] = value;
      });
      normalized['src'] = source;
      embeds.add(normalized);
      continue;
    }

    embeds.add({'src': source});
  }

  return embeds;
}

/// The embeds of a message in the shape Open WebUI stores them.
///
/// The shape of each entry is kept: a legacy embed goes back as its source
/// string, and a structured preview embed ([isPreviewEmbed]) stays an object
/// with its `type`, `url`, `name` and `content_type`. Flattening a preview
/// object to its URL, or writing a string embed back as a `{src: …}` map,
/// leaves a chat the web client can no longer render.
List<Object>? sanitizeEmbedsForWebUi(List<Map<String, dynamic>>? embeds) {
  if (embeds == null || embeds.isEmpty) {
    return null;
  }

  final sanitized = <Object>[];
  for (final embed in embeds) {
    if (isPreviewEmbed(embed)) {
      final name = embed['name'];
      final contentType = embed['content_type'];
      sanitized.add(<String, dynamic>{
        'type': 'preview',
        'url': embed['url'].toString().trim(),
        if (name != null) 'name': name.toString(),
        if (contentType != null) 'content_type': contentType.toString(),
      });
      continue;
    }
    final source = extractEmbedSource(embed);
    if (source != null && source.isNotEmpty) {
      sanitized.add(source);
    }
  }

  return sanitized.isEmpty ? null : sanitized;
}
