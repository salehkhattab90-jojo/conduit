import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/apply_brand_strings.dart';

const _arb = '''
{
  "@@locale": "en",
  "appTitle": "Conduit",
  "@appTitle": {
    "description": "Conduit is the app's name."
  },
  "aboutConduit": "About Conduit",
  "messageHintText": "Ask Conduit",
  "queued": "Queued messages stay only while Conduit is open. Conduit's queue.",
  "conduitPro": "ConduitPro and Conduits stay",
  "named": "Hello {Conduit}, {Conduit, select, other{Conduit rocks}}",
  "@named": {
    "placeholders": {"Conduit": {"type": "String"}}
  },
  "count": "{count, plural, =1{Conduit has one} other{Conduit has {count}}}",
  "escaped": "Say \\"Conduit\\" twice"
}
''';

void main() {
  test('renames the product in message values only', () {
    final out = applyBrandToArb(_arb, to: 'Acme Chat');
    final json = jsonDecode(out) as Map<String, dynamic>;

    expect(json['appTitle'], 'Acme Chat');
    expect(json['aboutConduit'], 'About Acme Chat');
    expect(json['messageHintText'], 'Ask Acme Chat');
    expect(
      json['queued'],
      "Queued messages stay only while Acme Chat is open. Acme Chat's queue.",
    );
    expect(json['conduitPro'], 'ConduitPro and Conduits stay');
    expect(
      json['count'],
      '{count, plural, =1{Acme Chat has one} other{Acme Chat has {count}}}',
    );
    expect(json['escaped'], 'Say "Acme Chat" twice');
    // Keys, metadata and placeholder names are untouched.
    expect(json.containsKey('aboutConduit'), isTrue);
    expect(
      (json['@appTitle'] as Map)['description'],
      "Conduit is the app's name.",
    );
    expect(
      json['named'],
      'Hello {Conduit}, {Conduit, select, other{Acme Chat rocks}}',
    );
  });

  test('changes nothing but the renamed words', () {
    final out = applyBrandToArb(_arb, to: 'Acme');
    final changed = <int>[];
    final before = _arb.split('\n');
    final after = out.split('\n');
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      if (before[i] != after[i]) changed.add(i);
      expect(after[i].replaceAll('Acme', 'Conduit'), before[i]);
    }
    expect(changed, isNotEmpty);
  });

  test('is idempotent, also for a name containing the old one', () {
    for (final name in ['Acme', 'Conduit Pro', 'My "Conduit"']) {
      final once = applyBrandToArb(_arb, to: name);
      expect(applyBrandToArb(once, to: name), once, reason: name);
    }
    expect(applyBrandToArb(_arb, to: 'Conduit'), _arb);
  });

  test('every shipped ARB file still parses after a rename', () {
    final files = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((file) => RegExp(r'app_[A-Za-z_]+\.arb$').hasMatch(file.path));
    expect(files, isNotEmpty);
    for (final file in files) {
      final source = file.readAsStringSync();
      final renamed = applyBrandToArb(source, to: 'Acme');
      final before = jsonDecode(source) as Map<String, dynamic>;
      final after = jsonDecode(renamed) as Map<String, dynamic>;
      expect(after.keys, before.keys, reason: file.path);
      for (final key in before.keys.where((key) => key.startsWith('@'))) {
        expect(after[key], before[key], reason: '${file.path} $key');
      }
      // A branch that already renamed the product has no "Conduit" left to
      // rename; the rename must still leave the file intact.
      final namesProduct = before.entries.any(
        (entry) =>
            !entry.key.startsWith('@') &&
            entry.value is String &&
            RegExp(r'\bConduit\b').hasMatch(entry.value as String),
      );
      if (namesProduct) {
        expect(
          after.values.whereType<String>().any((v) => v.contains('Acme')),
          isTrue,
          reason: file.path,
        );
      }
    }
  });
}
