import 'package:flight_time/models/athletes.dart';
import 'package:flight_time/screens/about_page.dart';
import 'package:flight_time/screens/athletes_navigation_page.dart';
import 'package:flight_time/screens/camera_page.dart';
import 'package:flight_time/screens/nitro_camera_experiment_page.dart';
import 'package:flight_time/screens/playback_page.dart';
import 'package:flight_time/widgets/helpers.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Athletes.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        primaryColor: Color.fromRGBO(0x00, 0x1f, 0x3b, 1),
        appBarTheme:
            AppBarTheme(backgroundColor: darkBlue, foregroundColor: white),
        sliderTheme:
            SliderThemeData(thumbColor: orange, activeTrackColor: orange),
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: IconButton.styleFrom(
                foregroundColor: white, backgroundColor: darkBlue)),
        iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
                foregroundColor: white,
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: whiteBlue.withValues(alpha: 0.2))),
        drawerTheme: DrawerThemeData(backgroundColor: white),
      ),
      initialRoute: AthletesNavigationPage.routeName,
      routes: {
        CameraPage.routeName: (context) => const CameraPage(),
        NitroCameraExperimentPage.routeName: (context) =>
            const NitroCameraExperimentPage(),
        PlaybackPage.routeName: (context) => const PlaybackPage(),
        AthletesNavigationPage.routeName: (context) =>
            const AthletesNavigationPage(),
        AboutPage.routeName: (context) => const AboutPage(),
      },
    );
  }
}
