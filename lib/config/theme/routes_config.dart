import 'package:adnetwork/layers/presentation/screen/about/about_screen.dart';
import 'package:adnetwork/layers/presentation/screen/admin/admin_notices_screen.dart';
import 'package:adnetwork/layers/presentation/screen/admin/admin_screen.dart';
import 'package:adnetwork/layers/presentation/screen/admin/admin_subscriptions_screen.dart';
import 'package:adnetwork/layers/presentation/screen/admin/finance_screen.dart';
import 'package:adnetwork/layers/presentation/screen/contact/contact_screen.dart';
import 'package:adnetwork/layers/presentation/screen/home/home_page.dart';
import 'package:adnetwork/layers/presentation/screen/login/login_screen.dart';
import 'package:adnetwork/layers/presentation/screen/profile/user_profile_screen.dart';
import 'package:adnetwork/layers/presentation/screen/settings/change_password_screen.dart';
import 'package:adnetwork/layers/presentation/screen/settings/faq_screen.dart';
import 'package:adnetwork/layers/presentation/screen/settings/privacy_policy_screen.dart';
import 'package:adnetwork/layers/presentation/screen/settings/settings_screen.dart';
import 'package:adnetwork/layers/presentation/screen/settings/terms_screen.dart';
import 'package:adnetwork/layers/presentation/screen/signup/signup_screen.dart';
import 'package:adnetwork/layers/presentation/screen/social/social_screens.dart';
import 'package:adnetwork/layers/presentation/screen/splash/splash_screen.dart';
import 'package:adnetwork/layers/presentation/screen/stats/stats_screen.dart';
import 'package:adnetwork/layers/presentation/screen/campaign/campaign_screen.dart';
import 'package:flutter/material.dart';

class Routes {
  static const String splashRoute = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';
  static const String userProfile = '/user-profile';
  static const String followers = '/followers';
  static const String following = '/following';
  static const String about = '/about';
  static const String contact = '/contact';
  static const String settings = '/settings';
  static const String changePassword = '/change-password';
  static const String stats = '/stats';
  static const String faq = '/faq';
  static const String privacy = '/privacy';
  static const String terms = '/terms';
  static const String admin = '/admin';
  static const String adminNotices = '/admin/notices';
  static const String adminSubscriptions = '/admin/subscriptions';
  static const String adminFinance = '/admin/finance';
  static const String campaign = '/campaign';
}

class AppRoutes {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.splashRoute:
        return MaterialPageRoute(builder: (_) => SplashPage());
      case Routes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case Routes.signup:
        return MaterialPageRoute(builder: (_) => const SignupScreen());
      case Routes.home:
        return MaterialPageRoute(builder: (_) => const HomePage());
      case Routes.userProfile:
        final userId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => UserProfileScreen(userId: userId),
        );
      case Routes.followers:
        return MaterialPageRoute(builder: (_) => const FollowersScreen());
      case Routes.following:
        return MaterialPageRoute(builder: (_) => const FollowingScreen());
      case Routes.about:
        return MaterialPageRoute(builder: (_) => const AboutScreen());
      case Routes.contact:
        return MaterialPageRoute(builder: (_) => const ContactScreen());
      case Routes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case Routes.changePassword:
        return MaterialPageRoute(builder: (_) => const ChangePasswordScreen());
      case Routes.stats:
        return MaterialPageRoute(builder: (_) => const StatsScreen());
      case Routes.faq:
        return MaterialPageRoute(builder: (_) => const FaqScreen());
      case Routes.privacy:
        return MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen());
      case Routes.terms:
        return MaterialPageRoute(builder: (_) => const TermsScreen());
      case Routes.admin:
        return MaterialPageRoute(builder: (_) => const AdminScreen());
      case Routes.adminNotices:
        return MaterialPageRoute(builder: (_) => const AdminNoticesScreen());
      case Routes.adminSubscriptions:
        return MaterialPageRoute(builder: (_) => const AdminSubscriptionsScreen());
      case Routes.adminFinance:
        return MaterialPageRoute(builder: (_) => const FinanceScreen());
      case Routes.campaign:
        final args = settings.arguments as Map<String, dynamic>?;
        final isMandatory = args?['isMandatory'] as bool? ?? false;
        return MaterialPageRoute(
          builder: (_) => CampaignScreen(isMandatory: isMandatory),
        );
      default:
        return _unDefinedRoute();
    }
  }

  static Route<dynamic> _unDefinedRoute() {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text("Page Not Found")),
        body: const Center(child: Text("Page Not Found")),
      ),
    );
  }
}
