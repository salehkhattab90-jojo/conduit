/// A structured preview embed produced by the OWUI middleware for generated
/// documents: `{type: 'preview', url, name, content_type}`. The `url` points
/// at a rendered preview FILE (typically application/pdf); the real
/// downloadable file travels as a sibling `files` entry on the SAME
/// function_call_output item. Distinct from legacy embeds, which are raw
/// self-contained HTML strings.
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

List<dynamic>? sanitizeEmbedsForWebUi(List<Map<String, dynamic>>? embeds) {
  if (embeds == null || embeds.isEmpty) {
    return null;
  }

  // Legacy embeds are flattened to their HTML source string (what the web UI
  // stores). Structured preview embeds MUST keep their object shape — saving
  // them as bare strings would corrupt the server-side contract the web
  // client's preview card depends on.
  final normalized = <dynamic>[];
  for (final embed in embeds) {
    if (isPreviewEmbed(embed)) {
      normalized.add(<String, dynamic>{
        'type': 'preview',
        'url': embed['url'].toString(),
        if (embed['name'] != null) 'name': embed['name'].toString(),
        if (embed['content_type'] != null)
          'content_type': embed['content_type'].toString(),
      });
      continue;
    }
    final source = extractEmbedSource(embed);
    if (source != null && source.isNotEmpty) {
      normalized.add(source);
    }
  }

  return normalized.isEmpty ? null : normalized;
}
