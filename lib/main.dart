import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/notification_service.dart';
import 'storage/app_prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await NotificationService.instance.init();
  await NotificationService.instance.requestAndroidPermissionIfNeeded();

  final onboardingComplete = await AppPrefs.isOnboardingComplete();
  final textSize = await AppPrefs.getTextSize();

  runApp(BedtimeApp(
    showOnboarding: !onboardingComplete,
    initialTextSize: textSize,
  ));
}

class BedtimeApp extends StatefulWidget {
  final bool showOnboarding;
  final String initialTextSize;

  const BedtimeApp({
    super.key,
    required this.showOnboarding,
    required this.initialTextSize,
  });

  @override
  State<BedtimeApp> createState() => _BedtimeAppState();
}

class _BedtimeAppState extends State<BedtimeApp> {
  late bool _showOnboarding;
  late String _textSize;

  @override
  void initState() {
    super.initState();
    _showOnboarding = widget.showOnboarding;
    _textSize = widget.initialTextSize;
  }

  // called by OnboardingScreen when the user hits "Let's go" on the last page
  void _onOnboardingComplete() =>
      setState(() => _showOnboarding = false);

  // called by SettingsScreen when the user changes their text size preference
  void _onTextSizeChanged(String size) =>
      setState(() => _textSize = size);

  // maps the string preference to a scale factor applied to all text in the app
  double _textScaleFactor() {
    switch (_textSize) {
      case 'small': return 0.85;
      case 'large': return 1.2;
      default: return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Drift',
      theme: _buildTheme(),
      // wrap the whole app in a MediaQuery override so text size changes
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_textScaleFactor()),
        ),
        child: child!,
      ),
      // first-time users see onboarding, everyone else goes straight to the app
      home: _showOnboarding
          ? OnboardingScreen(onComplete: _onOnboardingComplete)
          : AppShell(
              onTextSizeChanged: _onTextSizeChanged,
              textSize: _textSize,
            ),
    );
  }

  // centralised theme so every screen inherits consistent colours, shapes and component styles
  ThemeData _buildTheme() {
    const bgColor = Color(0xFF0D0F1C);
    const surfaceColor = Color(0xFF161829);
    const accentColor = Color(0xFF7B82E8);
    const textColor = Color(0xFFE8E9F3);
    const subtleColor = Color(0xFF8B8FA8);
    const borderColor = Color(0xFF2E3156);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgColor,
      colorScheme: const ColorScheme.dark(
        background: bgColor,
        surface: surfaceColor,
        primary: accentColor,
        onPrimary: Colors.white,
        onBackground: textColor,
        onSurface: textColor,
        secondary: Color(0xFF9FA4F0),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: textColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        indicatorColor: accentColor.withOpacity(0.2),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const TextStyle(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.w600);
          }
          return const TextStyle(color: subtleColor, fontSize: 11);
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const IconThemeData(color: accentColor);
          }
          return const IconThemeData(color: subtleColor);
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentColor,
          side: const BorderSide(color: borderColor, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          textStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderColor, width: 1),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected)
                ? accentColor
                : subtleColor),
        trackColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected)
                ? accentColor.withOpacity(0.3)
                : const Color(0xFF2A2D45)),
      ),
      dividerTheme: const DividerThemeData(
        color: borderColor,
        thickness: 0.5,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: textColor,
        iconColor: subtleColor,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceColor,
        contentTextStyle: const TextStyle(color: textColor),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return accentColor.withOpacity(0.2);
            }
            return surfaceColor;
          }),
          foregroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return accentColor;
            }
            return subtleColor;
          }),
          side: MaterialStateProperty.all(
              const BorderSide(color: borderColor, width: 1)),
        ),
      ),
    );
  }
}