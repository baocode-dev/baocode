import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/context_keys.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/statusbar.dart';
import 'package:baocode/ide/workbench/storage.dart';

class _Counter extends ChangeNotifier {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Disposable implements WorkbenchDisposable {
  _Disposable(this.log, this.name);

  final List<String> log;
  final String name;

  @override
  void dispose() => log.add(name);
}

class _Participant implements WorkbenchStorageParticipant {
  _Participant(this.key);

  final String key;
  Object? value;

  @override
  void restoreState(Map<String, Object?> kept) => value = kept[key];

  @override
  void saveState(Map<String, Object?> into) {
    if (value != null) into[key] = value;
  }
}

void main() {
  group('WorkbenchServices', () {
    test('gets a service by its type, once', () {
      final services = WorkbenchServices();
      final counter = services.add(_Counter());
      expect(services.get<_Counter>(), same(counter));
      expect(services.find<ContextKeyService>(), isNull);
      expect(() => services.get<ContextKeyService>(), throwsStateError);
      expect(() => services.add(_Counter()), throwsStateError);
    });

    test('disposes the last added first', () {
      final log = <String>[];
      final services = WorkbenchServices()
        ..add(_Disposable(log, 'first'))
        ..add<WorkbenchDisposable>(_Disposable(log, 'second'));
      final counter = services.add(_Counter());
      services.dispose();
      expect(log, ['second', 'first']);
      expect(counter.disposed, isTrue);
    });

    test('removes a workspace\'s service, disposing it', () {
      final services = WorkbenchServices();
      final counter = services.add(_Counter());
      services.remove<_Counter>();
      expect(counter.disposed, isTrue);
      expect(services.has<_Counter>(), isFalse);
      final next = services.add(_Counter());
      services.remove<_Counter>(owned: false);
      expect(next.disposed, isFalse);
    });

    testWidgets('hands them to the widgets under the scope', (tester) async {
      final services = WorkbenchServices()..add(_Counter());
      addTearDown(services.dispose);
      late WorkbenchServices found;
      await tester.pumpWidget(
        WorkbenchScope(
          services: services,
          child: Builder(
            builder: (context) {
              found = WorkbenchScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, same(services));
    });
  });

  group('ContextKeyService', () {
    test('a key made is read before the providers', () {
      final keys = ContextKeyService();
      addTearDown(keys.dispose);
      final back = keys.createKey('canNavigateBack', false);
      keys.addProvider((key) => key == 'canNavigateBack' ? 'provided' : null);
      expect(keys.getValue('canNavigateBack'), isFalse);
      back.set(true);
      expect(keys.lookup('canNavigateBack'), isTrue);
      back.reset();
      expect(keys.getValue('canNavigateBack'), isFalse);
      expect(identical(keys.createKey('canNavigateBack', true), back), isTrue);
    });

    test('providers answer in order, null for keys they do not know', () {
      final keys = ContextKeyService();
      addTearDown(keys.dispose);
      final remove = keys.addProvider(
        (key) => key == 'terminalFocus' ? false : null,
      );
      keys.addProvider((key) => key == 'terminalFocus' ? true : 'other');
      expect(keys.getValue('terminalFocus'), isFalse);
      expect(keys.getValue('listFocus'), 'other');
      remove();
      expect(keys.getValue('terminalFocus'), isTrue);
    });

    test('binds a key to a listenable, telling of changes', () {
      final keys = ContextKeyService();
      addTearDown(keys.dispose);
      final count = ValueNotifier(0);
      var changes = 0;
      keys.addListener(() => changes++);
      final unbind = keys.bind('terminalCount', count);
      count.value = 2;
      expect(keys.getValue('terminalCount'), 2);
      expect(changes, 1);
      unbind();
      count.value = 3;
      expect(keys.getValue('terminalCount'), 2);
    });
  });

  group('ActionRegistry', () {
    test('runs actions with the services, the first of an id', () {
      final services = WorkbenchServices();
      final registry = services.add(ActionRegistry());
      final ran = <String>[];
      final remove = registry.register(
        WorkbenchAction(
          id: 'a',
          title: 'A',
          category: 'Test',
          precondition: (s) => identical(s, services),
          run: (s, args) => ran.add('a $args'),
          takesArgs: true,
        ),
      );
      registry.register(
        WorkbenchAction(
          id: 'b',
          title: 'B',
          palette: false,
          run: (s, _) => ran.add('b'),
        ),
      );
      final commands = registry.commands(services);
      expect([for (final c in commands) c.id], ['a', 'b']);
      expect(commands.first.title, 'Test: A');
      expect(commands.first.enabled, isTrue);
      commands.first.invoke('x');
      commands.first.invoke();
      expect(ran, ['a x', 'a null']);
      expect(
        [for (final c in registry.commands(services, palette: true)) c.id],
        ['a'],
      );
      remove();
      expect(registry.byId('a'), isNull);
      expect(registry.byId('b'), isNotNull);
      services.dispose();
    });
  });

  group('StatusbarService', () {
    testWidgets('orders entries by priority, then as added', (tester) async {
      final statusbar = StatusbarService();
      addTearDown(statusbar.dispose);
      final text = ValueNotifier('high');
      addTearDown(text.dispose);
      statusbar.addEntry(
        'low',
        StatusbarAlignment.right,
        (_) => const IdeStatusBarItem('low'),
        priority: 1,
      );
      final high = statusbar.addEntry(
        'high',
        StatusbarAlignment.right,
        (_) => IdeStatusBarItem(text.value),
        priority: 10,
        changes: text,
      );
      statusbar.addEntry(
        'also-low',
        StatusbarAlignment.right,
        (_) => const IdeStatusBarItem('also low'),
        priority: 1,
      );
      statusbar.addEntry(
        'left',
        StatusbarAlignment.left,
        (_) => const IdeStatusBarItem('left'),
      );
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      List<String> texts(StatusbarAlignment side) => [
        for (final item in statusbar.items(context, side)) item.text,
      ];
      expect(texts(StatusbarAlignment.right), ['high', 'low', 'also low']);
      expect(texts(StatusbarAlignment.left), ['left']);

      var changes = 0;
      statusbar.addListener(() => changes++);
      text.value = 'higher';
      expect(texts(StatusbarAlignment.right).first, 'higher');
      high.update((_) => null);
      expect(texts(StatusbarAlignment.right), ['low', 'also low']);
      high.dispose();
      text.value = 'gone';
      expect(changes, 3);
    });

    test('merges entries among the items not yet entries', () {
      const a = IdeStatusBarItem('a');
      const b = IdeStatusBarItem('b');
      const c = IdeStatusBarItem('c');
      const d = IdeStatusBarItem('d');
      expect(mergeStatusbarItems([(100, a), (50, c)], [(80, b), (50, d)]), [
        a,
        b,
        c,
        d,
      ]);
    });
  });

  group('WorkbenchStorage', () {
    test('each participant reads and writes its own keys', () {
      var changed = 0;
      final storage = WorkbenchStorage(onChanged: () => changed++);
      final widths = _Participant('sidebarWidth');
      final remove = storage.register(widths);
      storage.restore({'sidebarWidth': 300, 'view': 'search'});
      expect(widths.value, 300);
      // One added late reads what was kept.
      final view = _Participant('view');
      storage.register(view);
      expect(view.value, 'search');
      widths.value = 320;
      expect(storage.collect(), {'sidebarWidth': 320, 'view': 'search'});
      storage.changed();
      expect(changed, 1);
      remove();
      expect(storage.collect(), {'view': 'search'});
    });
  });

  test('registrations are undone in reverse', () {
    final log = <String>[];
    final registrations = WorkbenchRegistrations()
      ..add(() => log.add('first'))
      ..add(() => log.add('second'));
    disposeContributions([registrations]);
    expect(log, ['second', 'first']);
  });
}
