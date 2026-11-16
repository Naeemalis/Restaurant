import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/app_database.dart';
import 'data/inventory_schema.dart';
import 'screens/login_screen.dart';
import 'app_locale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await AppDatabase.instance.database;
  await InventorySchema.ensure(database);
  await AppDatabase.instance.ensureDefaultAdmin();
  runApp(const NaeemSoftRestaurantApp());
}

class NaeemSoftRestaurantApp extends StatelessWidget {
  const NaeemSoftRestaurantApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(valueListenable: appLocale,builder:(context,locale,_)=>MaterialApp(
    title: 'NaeemSoft Restaurant',
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B55))),
    home: FutureBuilder<bool>(
      future: AppDatabase.instance.hasAdmin(),
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return LoginScreen(firstRun: state.data != true);
      },
    ),
  ));
}
