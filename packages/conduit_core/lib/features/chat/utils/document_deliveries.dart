import 'dart:convert';

import 'package:conduit_markdown/conduit_markdown.dart';

import 'file_utils.dart';

/// How a generated document reached the message.
enum DocumentDeliveryKind {
  /// A structured preview embed (`{type: 'preview', url, name,
  /// content_type}`): a rendered preview file, usually a PDF, beside the
  /// real file.
  preview,

  /// A legacy HTML string embed beside the real file.
  htmlPreview,

  /// An HTML string embed with no file: the HTML is the deliverable.
  artifact,
}

/// One generated document, shown as one card: its real file, its preview,
/// or both.
final class DocumentDelivery {
  const DocumentDelivery({
    required this.kind,
    this.fileName,
    this.fileUrl,
    this.fileId,
    this.previewUrl,
    this.previewName,
    this.previewContentType,
    this.previewHtml,
  });

  final DocumentDeliveryKind kind;

  /// Name of the real file, or of the artifact. Null when nothing names it.
  final String? fileName;

  /// The real file (`files[]` entry). Null for an artifact, and for a
  /// preview whose file did not arrive.
  final String? fileUrl;

  /// Open WebUI file id of the real file, for download.
  final String? fileId;

  /// [DocumentDeliveryKind.preview]: URL of the rendered preview file.
  final String? previewUrl;
  final String? previewName;
  final String? previewContentType;

  /// [DocumentDeliveryKind.htmlPreview] and [DocumentDeliveryKind.artifact]:
  /// the HTML to render.
  final String? previewHtml;

  bool get isArtifact => kind == DocumentDeliveryKind.artifact;

  /// The name to show: the file's, else the preview's without the `.pdf`
  /// the preview renderer appends (`Report.docx.pdf` is `Report.docx`).
  String? get displayName {
    if (fileName case final name?) return name;
    final preview = previewName;
    if (preview == null) return null;
    if (preview.toLowerCase().endsWith('.pdf')) {
      final original = preview.substring(0, preview.length - 4);
      if (documentExtension(original) != null) return original;
    }
    return preview;
  }

  /// Lower-case extension identifying the format (`docx`, `pdf`, …), or null.
  String? get extension {
    final fromName = documentExtension(displayName);
    if (fromName != null) return fromName;
    if (kind == DocumentDeliveryKind.artifact) {
      final html = previewHtml?.trimLeft().toLowerCase() ?? '';
      return html.startsWith('<svg') ? 'svg' : 'html';
    }
    return null;
  }

  /// Identity used to show a delivery once, however many places carry it.
  String get key {
    if (fileUrl case final url?) {
      return 'file:${openWebUiFileIdFromUrl(url) ?? url}';
    }
    if (previewUrl case final url?) {
      return 'preview:${openWebUiFileIdFromUrl(url) ?? url}';
    }
    return 'html:${previewHtml ?? ''}';
  }
}

/// A message's deliveries, and what is left to render the usual way.
final class DocumentDeliveries {
  const DocumentDeliveries({
    required this.deliveries,
    required this.files,
    required this.embeds,
  });

  /// One card each.
  final List<DocumentDelivery> deliveries;

  /// Files to show as attachments: the message's own files no card shows,
  /// then the non-image files of tool results no card shows.
  final List<Map<String, dynamic>> files;

  /// The message's own embeds no card shows. Never holds a preview object:
  /// those render only through a card.
  final List<Map<String, dynamic>> embeds;
}

final _openWebUiFilePattern = RegExp(
  r'/api/v1/files/([^/?#]+)(?:/content)?/?(?:[?#].*)?$',
);
final _bareFileIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');

/// The Open WebUI file id a file URL points at: `/api/v1/files/{id}`,
/// `…/{id}/content` (relative or absolute), or a bare id.
String? openWebUiFileIdFromUrl(String? url) {
  final trimmed = url?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final match = _openWebUiFilePattern.firstMatch(trimmed);
  if (match != null) return match.group(1);
  return _bareFileIdPattern.hasMatch(trimmed) ? trimmed : null;
}

/// Lower-case extension of [name], at most five characters, or null.
String? documentExtension(String? name) {
  if (name == null) return null;
  final trimmed = name.trim();
  final dot = trimmed.lastIndexOf('.');
  if (dot <= 0 || dot >= trimmed.length - 1) return null;
  final extension = trimmed.substring(dot + 1).toLowerCase();
  if (extension.contains('/') || extension.contains(' ')) return null;
  return extension.length > 5 ? extension.substring(0, 5) : extension;
}

/// Pairs a message's generated documents into one delivery per document.
///
/// Deliveries are looked for among the message's own [files] and [embeds],
/// and among those of each `function_call_output` item of [output] (where
/// native tool calls put them), each place on its own:
///
/// - each preview object, with its real file: the file the preview points
///   at (a PDF previews itself), else the file it is named after
///   (`Report.docx` → `Report.docx.pdf`), else the only file left; a
///   preview whose file did not arrive still gets its card;
/// - with no preview object, a single HTML string embed with the single
///   non-image file (a legacy preview), or with no file at all (an
///   artifact, named after the `path` its call was given).
///
/// The message's other files and embeds render as before, and a tool
/// result's non-image files that no card shows are listed with them.
DocumentDeliveries collectDocumentDeliveries({
  List<Map<String, dynamic>>? files,
  List<Map<String, dynamic>>? embeds,
  List<Map<String, dynamic>>? output,
}) {
  final messageFiles = files ?? const <Map<String, dynamic>>[];
  final messageEmbeds = embeds ?? const <Map<String, dynamic>>[];
  final outputItems = output ?? const <Map<String, dynamic>>[];

  final byKey = <String, DocumentDelivery>{};
  final toolFiles = <Map<String, dynamic>>[];

  final messageGroup = _pairGroup(
    messageFiles,
    messageEmbeds,
    artifactName: () => _showCallArtifactName(outputItems),
  );
  for (final delivery in messageGroup.deliveries) {
    byKey.putIfAbsent(delivery.key, () => delivery);
  }

  if (outputItems.isNotEmpty) {
    final callsById = <String, Map<String, dynamic>>{};
    for (final item in outputItems) {
      if (item['type'] != 'function_call') continue;
      final id = (item['call_id'] ?? item['id'])?.toString();
      if (id != null && id.isNotEmpty) callsById[id] = item;
    }
    for (final item in outputItems) {
      if (item['type'] != 'function_call_output') continue;
      final itemFiles = _maps(item['files']);
      final itemEmbeds = normalizeEmbedList(item['embeds']);
      if (itemFiles.isEmpty && itemEmbeds.isEmpty) continue;
      final call = callsById[item['call_id']?.toString() ?? ''];
      final group = _pairGroup(
        itemFiles,
        itemEmbeds,
        artifactName: () => _pathArgumentName(call),
      );
      for (final delivery in group.deliveries) {
        byKey.putIfAbsent(delivery.key, () => delivery);
      }
      toolFiles.addAll(group.unpairedFiles);
    }
  }

  final deliveries = List<DocumentDelivery>.unmodifiable(byKey.values);
  bool shownByCard(Map<String, dynamic> file) => deliveries.any(
    (delivery) => _sameFile(getFileUrl(file), delivery.fileUrl),
  );

  final remainingFiles = <Map<String, dynamic>>[
    for (final file in messageFiles)
      if (!shownByCard(file)) file,
  ];
  for (final file in toolFiles) {
    if (shownByCard(file) ||
        remainingFiles.any(
          (listed) => _sameFile(getFileUrl(listed), getFileUrl(file)),
        )) {
      continue;
    }
    remainingFiles.add(file);
  }

  final remainingEmbeds = <Map<String, dynamic>>[
    for (final embed in messageEmbeds)
      if (!isPreviewEmbed(embed) &&
          !deliveries.any(
            (delivery) =>
                delivery.previewHtml != null &&
                delivery.previewHtml == extractEmbedSource(embed),
          ))
        embed,
  ];

  return DocumentDeliveries(
    deliveries: deliveries,
    files: List<Map<String, dynamic>>.unmodifiable(remainingFiles),
    embeds: List<Map<String, dynamic>>.unmodifiable(remainingEmbeds),
  );
}

typedef _GroupPairing = ({
  List<DocumentDelivery> deliveries,
  List<Map<String, dynamic>> unpairedFiles,
});

_GroupPairing _pairGroup(
  List<Map<String, dynamic>> files,
  List<Map<String, dynamic>> embeds, {
  required String? Function() artifactName,
}) {
  final freeFiles = [
    for (final file in files)
      if (!isImageFile(file) && getFileUrl(file) != null) file,
  ];
  final previews = embeds.where(isPreviewEmbed).toList();

  if (previews.isNotEmpty) {
    final paired = <int, Map<String, dynamic>>{};
    Map<String, dynamic>? takeFile(bool Function(Map<String, dynamic>) test) {
      final index = freeFiles.indexWhere(test);
      return index < 0 ? null : freeFiles.removeAt(index);
    }

    // The file the preview points at (a PDF previews itself).
    for (var i = 0; i < previews.length; i++) {
      final url = previews[i]['url']?.toString();
      final file = takeFile((file) => _sameFile(getFileUrl(file), url));
      if (file != null) paired[i] = file;
    }
    // The file the preview is named after.
    for (var i = 0; i < previews.length; i++) {
      if (paired.containsKey(i)) continue;
      final previewName = _nonEmpty(previews[i]['name'])?.toLowerCase();
      if (previewName == null) continue;
      final file = takeFile((file) {
        final name = _fileName(file)?.toLowerCase();
        return name != null &&
            (previewName == name || previewName == '$name.pdf');
      });
      if (file != null) paired[i] = file;
    }
    // The only file left for the only preview left.
    final unpaired = [
      for (var i = 0; i < previews.length; i++)
        if (!paired.containsKey(i)) i,
    ];
    if (unpaired.length == 1 && freeFiles.length == 1) {
      paired[unpaired.single] = freeFiles.removeAt(0);
    }

    return (
      deliveries: [
        for (var i = 0; i < previews.length; i++)
          _previewDelivery(previews[i], paired[i]),
      ],
      unpairedFiles: freeFiles,
    );
  }

  final htmlSources = <String>[
    for (final embed in embeds)
      if (extractEmbedSource(embed) case final source?
          when source.trimLeft().startsWith('<'))
        source,
  ];
  if (htmlSources.length != 1 || freeFiles.length > 1) {
    return (deliveries: const <DocumentDelivery>[], unpairedFiles: freeFiles);
  }

  if (freeFiles.isEmpty) {
    return (
      deliveries: [
        DocumentDelivery(
          kind: DocumentDeliveryKind.artifact,
          fileName: artifactName(),
          previewHtml: htmlSources.single,
        ),
      ],
      unpairedFiles: const <Map<String, dynamic>>[],
    );
  }

  final file = freeFiles.single;
  final fileUrl = getFileUrl(file)!;
  return (
    deliveries: [
      DocumentDelivery(
        kind: DocumentDeliveryKind.htmlPreview,
        fileName: _fileName(file),
        fileUrl: fileUrl,
        fileId: openWebUiFileIdFromUrl(fileUrl),
        previewHtml: htmlSources.single,
      ),
    ],
    unpairedFiles: const <Map<String, dynamic>>[],
  );
}

DocumentDelivery _previewDelivery(
  Map<String, dynamic> preview,
  Map<String, dynamic>? file,
) {
  final fileUrl = file == null ? null : getFileUrl(file);
  return DocumentDelivery(
    kind: DocumentDeliveryKind.preview,
    fileName: file == null ? null : _fileName(file),
    fileUrl: fileUrl,
    fileId: openWebUiFileIdFromUrl(fileUrl),
    previewUrl: preview['url'].toString().trim(),
    previewName: _nonEmpty(preview['name']),
    previewContentType: _nonEmpty(preview['content_type']),
  );
}

bool _sameFile(String? a, String? b) {
  if (a == null || b == null) return false;
  if (a.trim() == b.trim()) return true;
  final idA = openWebUiFileIdFromUrl(a);
  return idA != null && idA == openWebUiFileIdFromUrl(b);
}

String? _fileName(Map<String, dynamic> file) {
  final meta = file['meta'];
  return _nonEmpty(file['name']) ??
      _nonEmpty(file['filename']) ??
      (meta is Map ? _nonEmpty(meta['name']) : null);
}

/// Artifact name for the message's own embed: the workspace path a `show`
/// call delivered, as the tool trace records it.
String? _showCallArtifactName(List<Map<String, dynamic>> output) {
  for (final item in output) {
    if (item['type'] != 'function_call') continue;
    final status = item['status'];
    if (status != null && status != 'completed') continue;
    if (!(item['name']?.toString() ?? '').endsWith('show')) continue;
    final name = _pathArgumentName(item);
    if (name != null) return name;
  }
  return null;
}

String? _pathArgumentName(Map<String, dynamic>? call) {
  if (call == null) return null;
  Object? args = call['arguments'];
  if (args is String) {
    try {
      args = jsonDecode(args);
    } on FormatException {
      return null;
    }
  }
  if (args is! Map) return null;
  final path = _nonEmpty(args['path']);
  if (path == null) return null;
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty);
  return parts.isEmpty ? null : parts.last;
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<Map<String, dynamic>> _maps(Object? value) => [
  if (value is List)
    for (final entry in value)
      if (entry is Map)
        entry.map((key, value) => MapEntry(key.toString(), value)),
];
