import 'package:adnetwork/config/theme/routes_config.dart';
import 'package:adnetwork/config/theme/theme_manager.dart';
import 'package:adnetwork/core/services/link_queue_manager.dart';
import 'package:adnetwork/core/services/mobile_config_manager.dart';
import 'package:adnetwork/layers/data/repo/remote/auth_repository.dart';
import 'package:adnetwork/layers/data/repo/remote/link_repository.dart';
import 'package:adnetwork/layers/data/repo/remote/user_repository.dart';
import 'package:adnetwork/layers/data/repo/remote/campaign_repository.dart';
import 'package:adnetwork/layers/presentation/controller/profile/profile_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/theme/theme_cubit.dart';
import 'package:adnetwork/layers/presentation/controller/campaign/campaign_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileConfigManager.instance.init();
  await LinkQueueManager.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => AuthRepository()),
        RepositoryProvider(create: (_) => UserRepository()),
        RepositoryProvider(create: (_) => LinkRepository()),
        RepositoryProvider(create: (_) => CampaignRepository()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) =>
                ProfileBloc(userRepository: ctx.read<UserRepository>())
                  ..add(const LoadProfile()),
          ),
          BlocProvider(
            create: (ctx) => CampaignBloc(
              campaignRepository: ctx.read<CampaignRepository>(),
            ),
          ),
          BlocProvider(create: (_) => ThemeCubit()),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            return MaterialApp(
              title: 'Ad Network',
              debugShowCheckedModeBanner: false,
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: themeMode,
              onGenerateRoute: AppRoutes.onGenerateRoute,
              initialRoute: Routes.splashRoute,
              navigatorObservers: [routeObserver],
            );
          },
        ),
      ),
    );
  }
}

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();
