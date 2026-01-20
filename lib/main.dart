import 'package:flutter/material.dart';
// import 'package:firebase_core/firebase_core.dart';
import 'services/notification_service.dart';
import 'services/enhanced_notification_service.dart';
import 'screens/login_register.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reward_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/appliance_recommendation_screen.dart';
import 'screens/ai_insights_screen.dart';
import 'screens/bill_prediction_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await Firebase.initializeApp();
  await NotificationService.initialize();
  await EnhancedNotificationService.initialize();
  runApp(const WattBuddyApp());
}

class WattBuddyApp extends StatelessWidget {
  const WattBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WattBuddy',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0A0A2A),
        fontFamily: 'Roboto',
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginRegisterScreen(),
        '/dashboard': (context) => DashboardScreen(),
        '/profile': (context) => ProfileScreen(),
        '/rewards': (context) => const RewardsScreen(),
        '/devices': (context) => const DevicesScreen(),
        '/recommendations': (context) => const ApplianceRecommendationScreen(),
        '/insights': (context) => AIInsightsScreen(userId: 'user_id_here'),
        '/bill-prediction': (context) => const BillPredictionScreen(),
      },
    );
  }
}
