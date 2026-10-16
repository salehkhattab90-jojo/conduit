import 'package:checks/checks.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/models/model_controls.dart';
import 'package:conduit_core/models/server_user_settings.dart';
import 'package:test/test.dart';

/// `info.params.model_controls` as Open WebUI 0.12.2 lists it for a model
/// (server `public_model_params`: labels only, no option params).
const _thinkingControls = <String, dynamic>{
  'thinking': {
    'label': 'Thinking',
    'description': 'How much the model reasons first',
    'default': 'auto',
    'options': {
      'off': {'label': 'Off'},
      'auto': {'label': 'Auto'},
      'on': {'label': 'On'},
    },
  },
  'style': {
    'label': 'Style',
    'display': 'slider',
    'options': {
      'short': {'label': 'Short'},
      'long': {'label': 'Long'},
    },
  },
};

Map<String, dynamic> _modelItem(String id, Object? controls) => {
  'id': id,
  'name': id,
  'info': {
    'id': id,
    'params': {'model_controls': ?controls},
  },
};

void main() {
  group('parseModelControls', () {
    test('reads controls and options in the server order', () {
      final controls = parseModelControls(_thinkingControls);

      check(controls.keys.toList()).deepEquals(['thinking', 'style']);
      final thinking = controls['thinking']!;
      check(thinking.label).equals('Thinking');
      check(thinking.description).equals('How much the model reasons first');
      check(thinking.defaultOption).equals('auto');
      check(thinking.display).equals('menu');
      check(
        thinking.options.map((option) => option.value).toList(),
      ).deepEquals(['off', 'auto', 'on']);
      check(thinking.option('on')!.label).equals('On');
      check(controls['style']!.display).equals('slider');
      check(controls['style']!.defaultOption).isNull();
    });

    test('skips malformed controls and options', () {
      final controls = parseModelControls({
        'no_label': {
          'options': {
            'a': {'label': 'A'},
          },
        },
        'no_options': {'label': 'Empty', 'options': <String, dynamic>{}},
        'bad_default': {
          'label': 'Mode',
          'default': 'missing',
          'options': {
            'a': {'label': 'A'},
            'b': {'label': ' '},
            'c': 'not a map',
          },
        },
        'not_a_map': 'x',
      });

      check(controls.keys.toList()).deepEquals(['bad_default']);
      check(controls['bad_default']!.defaultOption).isNull();
      check(controls['bad_default']!.options.length).equals(1);
      check(parseModelControls(null)).isEmpty();
      check(parseModelControls(const <String, dynamic>{})).isEmpty();
    });

    test('a model exposes its controls from info.params', () {
      final model = Model.fromJson(_modelItem('m1', _thinkingControls));
      check(model.modelControls.keys.toList()).deepEquals([
        'thinking',
        'style',
      ]);

      final plain = Model.fromJson(const {'id': 'm2', 'name': 'm2'});
      check(plain.modelControls).isEmpty();
    });

    test('survives the model cache round trip', () {
      final model = Model.fromJson(_modelItem('m1', _thinkingControls));
      final cached = Model.fromJson(model.toJson());
      check(cached.modelControls.keys.toList()).deepEquals([
        'thinking',
        'style',
      ]);
    });
  });

  group('choices', () {
    test('stored picks keep only string options', () {
      final choices = parseModelControlChoices({
        'm1': {'thinking': 'on', 'style': 3, 'empty': ''},
        'm2': 'not a map',
        'm3': <String, dynamic>{},
      });
      check(choices).deepEquals({
        'm1': {'thinking': 'on'},
      });
    });

    test('picks the model no longer offers are dropped', () {
      final controls = parseModelControls(_thinkingControls);
      check(
        applicableModelControlChoice({
          'thinking': 'on',
          'style': 'removed-option',
          'removed_control': 'x',
        }, controls),
      ).deepEquals({'thinking': 'on'});
    });

    test('the request carries each target model its own offered picks', () {
      final param = openWebUiModelControlsParam(
        storedChoices: {
          'm1': {'thinking': 'off', 'style': 'gone'},
          'm2': {'thinking': 'on'},
          'm3': {'thinking': 'on'},
          'unrelated': {'thinking': 'on'},
        },
        modelItems: {
          'm1': _modelItem('m1', _thinkingControls),
          'm2': _modelItem('m2', _thinkingControls),
          // A model without controls gets nothing.
          'm3': _modelItem('m3', null),
        },
      );

      check(param).isNotNull().deepEquals({
        'm1': {'thinking': 'off'},
        'm2': {'thinking': 'on'},
      });
    });

    test('nothing to send is null', () {
      check(
        openWebUiModelControlsParam(
          storedChoices: {
            'm1': {'thinking': 'gone'},
          },
          modelItems: {'m1': _modelItem('m1', _thinkingControls)},
        ),
      ).isNull();
      check(
        openWebUiModelControlsParam(
          storedChoices: null,
          modelItems: {'m1': _modelItem('m1', _thinkingControls)},
        ),
      ).isNull();
    });
  });

  test('user settings read the picks from ui.params.model_controls', () {
    final settings = ServerUserSettings.fromJson({
      'ui': {
        'params': {
          'temperature': 0.4,
          'model_controls': {
            'm1': {'thinking': 'on'},
          },
        },
      },
      // The legacy root params never hold model controls.
      'params': {
        'model_controls': {
          'm2': {'thinking': 'off'},
        },
      },
    });

    check(settings.modelControls).deepEquals({
      'm1': {'thinking': 'on'},
    });
    check(
      settings.copyWith(systemPrompt: 'x').modelControls,
    ).deepEquals(settings.modelControls);
    check(const ServerUserSettings().modelControls).isEmpty();
  });
}
