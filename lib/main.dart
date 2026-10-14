import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'application/game_controller.dart';
import 'infrastructure/save_factory.dart';
import 'presentation/game_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Keep the canvas UI accessible to keyboard and assistive technology.
    SemanticsBinding.instance.ensureSemantics();
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  try {
    const development = bool.fromEnvironment('DEV_TOOLS');
    final repository = await createSaveRepository(
      slot: development ? 'development' : 'normal',
    );
    final controller = GameController(repository, devTools: development);
    runApp(MarsApp(controller: controller));
    await controller.initialize();
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('起動できませんでした。端末の空き容量を確認して再起動してください。\n$error'),
          ),
        ),
      ),
    );
  }
}

class MarsApp extends StatelessWidget {
  const MarsApp({
    super.key,
    required this.controller,
    this.sceneBuilder,
    this.renderScene = true,
  });
  final GameController controller;
  final bool renderScene;
  final Widget Function(bool earth, int earthLevel, int habitats, bool cargo)?
  sceneBuilder;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '火星開発計画',
    locale: const Locale('ja'),
    supportedLocales: const [Locale('ja')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      fontFamily: kIsWeb ? 'NotoSansJP' : null,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff9ddbc5),
        brightness: Brightness.dark,
        surface: const Color(0xff14212b),
        primary: const Color(0xffa2dfc8),
        secondary: const Color(0xffe8a57c),
      ),
      scaffoldBackgroundColor: const Color(0xff0b151e),
      useMaterial3: true,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 13, height: 1.45),
        bodySmall: TextStyle(
          fontSize: 11,
          height: 1.4,
          color: Color(0xffb6c4cc),
        ),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      visualDensity: VisualDensity.compact,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          // Component text styles replace the default style, so they must
          // carry the bundled Web font instead of triggering network fallback.
          textStyle: const TextStyle(
            fontFamily: kIsWeb ? 'NotoSansJP' : null,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
      chipTheme: const ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
        side: BorderSide(color: Color(0xff52645e)),
        labelStyle: TextStyle(
          fontFamily: kIsWeb ? 'NotoSansJP' : null,
          fontSize: 12,
          color: Color(0xffdce8df),
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: kIsWeb ? 'NotoSansJP' : null,
          fontSize: 12,
          color: Color(0xffe8f3e9),
        ),
        backgroundColor: Color(0xff17272e),
        selectedColor: Color(0xff355047),
        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          side: BorderSide(color: Color(0xff52645e)),
        ),
      ),
    ),
    home: GameScreen(
      controller: controller,
      sceneBuilder: sceneBuilder,
      renderScene: renderScene,
    ),
  );
}
