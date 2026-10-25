import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/research_flavor.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/game_screen.dart';
import 'package:mars_terraforming/presentation/research_tree.dart';

class _MobileResearchSave implements SaveRepository {
  @override
  Future<SaveLoadResult> load() async =>
      const SaveLoadResult(data: null, recovered: false, generation: 1);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {}
}

const _phoneSize = Size(873, 393);
const _phoneInsets = EdgeInsets.fromLTRB(24, 8, 24, 16);

Widget _screen(GameController controller, double textScale) => Builder(
  builder: (context) {
    final product = MarsApp(
      showTitle: false,
      controller: controller,
      renderScene: false,
      showIntroduction: false,
    ).build(context) as MaterialApp;
    final theme = product.theme!;
    return MaterialApp(
      locale: product.locale,
      supportedLocales: product.supportedLocales,
      localizationsDelegates: product.localizationsDelegates,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'NotoSansJP'),
        primaryTextTheme: theme.primaryTextTheme.apply(
          fontFamily: 'NotoSansJP',
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: _phoneInsets,
          viewPadding: _phoneInsets,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: GameScreen(
        showTitle: false,
        controller: controller,
        renderScene: false,
        showIntroduction: false,
      ),
    );
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('NotoSansJP')
      ..addFont(rootBundle.load('assets/fonts/NotoSansJP.ttf'));
    await loader.load();
  });

  Future<GameController> mount(WidgetTester tester, double textScale) async {
    tester.view.physicalSize = _phoneSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameController(
      _MobileResearchSave(),
      now: () => DateTime.utc(2026, 10, 20),
    );
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    controller.state
      ..openingSeen = true
      ..firstRunTutorial = FirstRunTutorialStep.completed;
    await tester.pumpWidget(_screen(controller, textScale));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-2')));
    await tester.pumpAndSettle();
    return controller;
  }

  Finder getCanvas() => find.byKey(const Key('research-tree-canvas'));
  Finder getDetail() => find.byKey(const Key('research-detail'));
  Finder getDetailScrollable() =>
      find.descendant(of: getDetail(), matching: find.byType(Scrollable)).first;

  for (final textScale in [1.0, 1.4]) {
    testWidgets(
      'phone research uses the safe width until a card is selected at scale $textScale',
      (tester) async {
        await mount(tester, textScale);
        final safeWidth =
            _phoneSize.width - _phoneInsets.left - _phoneInsets.right;
        final whole = tester.getRect(getCanvas());
        expect(getDetail(), findsNothing);
        expect(
          tester.widget<ResearchTree>(find.byType(ResearchTree)).selectedId,
          isNull,
        );
        expect(whole.left, closeTo(_phoneInsets.left, .1));
        expect(whole.width, closeTo(safeWidth, .1));
        final viewer = tester.widget<InteractiveViewer>(getCanvas());
        expect(
          viewer.transformationController!.value.storage[0],
          greaterThanOrEqualTo(.85),
        );

        await tester.tap(find.byKey(const Key('research-node-life_support')));
        await tester.pumpAndSettle();
        expect(getDetail(), findsOneWidget);
        expect(tester.getSize(getCanvas()).width, lessThan(whole.width));
        final close = find.byKey(const Key('close-research-detail'));
        expect(close.hitTestable(), findsOneWidget);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(getDetail(), findsNothing);
        expect(tester.getSize(getCanvas()).width, closeTo(whole.width, .1));

        await tester.tap(find.byKey(const Key('research-node-life_support')));
        await tester.pumpAndSettle();
        expect(getDetail(), findsOneWidget);
        final bio = find.byKey(const Key('research-filter-bio'));
        await tester.ensureVisible(bio);
        await tester.tap(bio);
        await tester.pumpAndSettle();
        expect(getDetail(), findsNothing);
        expect(
          tester.widget<ResearchTree>(find.byType(ResearchTree)).selectedId,
          isNull,
        );
        expect(tester.getSize(getCanvas()).width, closeTo(whole.width, .1));
        expect(
          find.byKey(const Key('research-node-orbital_gardens')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'phone facts stay on one line and flavor is readable without disclosure at scale $textScale',
      (tester) async {
        await mount(tester, textScale);
        await tester.tap(find.byKey(const Key('research-node-life_support')));
        await tester.pumpAndSettle();
        expect(getDetail(), findsOneWidget);

        for (final label in ['必要RP', '保有RP', 'RP生産']) {
          final finder = find.descendant(
            of: getDetail(),
            matching: find.text(label),
          );
          await tester.scrollUntilVisible(
            finder,
            100,
            scrollable: getDetailScrollable(),
          );
          await tester.pumpAndSettle();
          final text = tester.widget<Text>(finder);
          expect(text.maxLines, 1, reason: '$label is one unbroken label');
          expect(text.softWrap, isFalse);
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length),
          );
          expect(boxes, isNotEmpty);
          expect(
            boxes.map((box) => box.top.round()).toSet(),
            hasLength(1),
            reason:
                '$label must render on one baseline with the bundled Japanese font',
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          final labelRect = tester.getRect(finder);
          final viewport = tester.getRect(getDetail());
          expect(labelRect.left, greaterThanOrEqualTo(viewport.left));
          expect(labelRect.right, lessThanOrEqualTo(viewport.right + .1));
        }

        expect(find.text('方式の特徴・科学メモ'), findsNothing);
        expect(find.text('科学メモ・出典'), findsNothing);
        expect(find.textContaining('科学メモ'), findsNothing);
        final flavor = find.byKey(const Key('research-flavor-life_support'));
        await tester.scrollUntilVisible(
          flavor,
          150,
          scrollable: getDetailScrollable(),
        );
        final state = tester.state<ScrollableState>(getDetailScrollable());
        state.position.jumpTo(state.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(flavor, findsOneWidget);
        expect(
          find.ancestor(of: flavor, matching: find.byType(ExpansionTile)),
          findsNothing,
        );
        final passage = ResearchFlavor.forTechnology('life_support');
        final passageFinder = find.descendant(
          of: flavor,
          matching: find.text(passage),
        );
        expect(passageFinder, findsOneWidget);
        expect(tester.widget<Text>(passageFinder).maxLines, isNull);
        final paragraph = tester.renderObject<RenderParagraph>(passageFinder);
        expect(paragraph.didExceedMaxLines, isFalse);
        final lastLine = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: passage.length - 1,
                extentOffset: passage.length,
              ),
            )
            .last;
        final bottom = paragraph.localToGlobal(lastLine.toRect().bottomRight);
        final viewport = tester.getRect(getDetail());
        expect(bottom.dy, greaterThan(viewport.top));
        expect(bottom.dy, lessThanOrEqualTo(viewport.bottom + .1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
