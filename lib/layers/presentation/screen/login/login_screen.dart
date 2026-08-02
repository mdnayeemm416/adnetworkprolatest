import 'dart:ui';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:adnetwork/config/theme/styles_manager.dart';
import 'package:adnetwork/core/services/token_storage.dart';
import 'package:adnetwork/config/theme/routes_config.dart';
import 'package:adnetwork/core/functions/navigator.dart';
import 'package:adnetwork/layers/data/repo/remote/auth_repository.dart';
import 'package:adnetwork/layers/data/repo/remote/campaign_repository.dart';
import 'package:adnetwork/core/services/mobile_config_manager.dart';
import 'package:adnetwork/layers/presentation/controller/login/login_bloc.dart';
import 'package:adnetwork/layers/presentation/controller/profile/profile_bloc.dart';
import 'package:adnetwork/layers/presentation/widget/animated_background.dart';
import 'package:adnetwork/layers/presentation/widget/show_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:toastification/toastification.dart';

import 'component/login_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late AnimationController _cardAnimController;
  late Animation<double> _cardScaleAnim;
  late Animation<double> _cardFadeAnim;
  late LoginBloc _loginBloc;

  @override
  void initState() {
    super.initState();
    _loginBloc = LoginBloc(authRepository: context.read<AuthRepository>());
    _cardAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _cardScaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _cardAnimController, curve: Curves.easeOutBack),
    );
    _cardFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardAnimController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cardAnimController.forward();
    });

    _checkCachedCredentials();
  }

  Future<bool> _checkIsEmulator() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        debugPrint('--- EMULATOR DETECTION DEBUG INFO ---');
        debugPrint('Brand: ${androidInfo.brand}');
        debugPrint('Device: ${androidInfo.device}');
        debugPrint('Model: ${androidInfo.model}');
        debugPrint('Product: ${androidInfo.product}');
        debugPrint('Hardware: ${androidInfo.hardware}');
        debugPrint('Fingerprint: ${androidInfo.fingerprint}');
        debugPrint('Is Physical Device: ${androidInfo.isPhysicalDevice}');
        debugPrint('-------------------------------------');

        final isEmulator =
            !androidInfo.isPhysicalDevice ||
            androidInfo.fingerprint.startsWith('generic') ||
            androidInfo.fingerprint.startsWith('unknown') ||
            androidInfo.model.contains('google_sdk') ||
            androidInfo.model.contains('Emulator') ||
            androidInfo.model.contains('Android SDK built for x86') ||
            androidInfo.hardware.contains('goldfish') ||
            androidInfo.hardware.contains('ranchu') ||
            androidInfo.hardware.contains('vbox86') ||
            androidInfo.product.contains('sdk') ||
            androidInfo.product.contains('google_sdk') ||
            androidInfo.product.contains('sdk_x86') ||
            androidInfo.product.contains('vbox86p') ||
            androidInfo.board.toLowerCase().contains('nox') ||
            androidInfo.bootloader.toLowerCase().contains('nox') ||
            androidInfo.hardware.toLowerCase().contains('nox') ||
            androidInfo.product.toLowerCase().contains('nox') ||
            (androidInfo.brand.startsWith('generic') &&
                androidInfo.device.startsWith('generic'));

        return isEmulator;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        debugPrint('--- IOS SIMULATOR DETECTION ---');
        debugPrint('Model: ${iosInfo.model}');
        debugPrint('Name: ${iosInfo.name}');
        debugPrint('Is Physical Device: ${iosInfo.isPhysicalDevice}');
        debugPrint('-------------------------------------');
        return !iosInfo.isPhysicalDevice;
      }
    } catch (e) {
      debugPrint('Error checking emulator: $e');
    }
    return false;
  }

  Future<void> _checkCachedCredentials() async {
    final email = await TokenStorage.instance.getCachedEmail();
    final password = await TokenStorage.instance.getCachedPassword();
    if (email != null &&
        password != null &&
        email.isNotEmpty &&
        password.isNotEmpty) {
      if (mounted) {
        _emailController.text = email;
        _passwordController.text = password;

        // Ensure "Remember me" is checked visually
        _loginBloc.add(const InitializeRememberMe(true));

        final hasManuallyLoggedOut = await TokenStorage.instance
            .hasManuallyLoggedOut();
        if (!hasManuallyLoggedOut) {
          // Attempt auto-login only if they haven't explicitly logged out
          // _loginBloc.add(LoginSubmitted(email: email, password: password));
          Future.delayed(Duration(milliseconds: 300), () {
            if (mounted) {
              _loginBloc.add(LoginSubmitted(email: email, password: password));
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _cardAnimController.dispose();
    _loginBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 850;

    return BlocProvider.value(
      value: _loginBloc,
      child: BlocListener<LoginBloc, LoginState>(
        listener: (context, state) {
          if (state.status == LoginStatus.success) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              final isEmu = await _checkIsEmulator();
              if (!context.mounted) return;
              if (isEmu && !kDebugMode) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogCtx) => PopScope(
                    canPop: false,
                    child: AlertDialog(
                      backgroundColor: isDark
                          ? const Color(0xFF1E1E2E)
                          : colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: colorScheme.error.withValues(alpha: .2),
                        ),
                      ),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.error.withValues(alpha: .1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              color: colorScheme.error,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Emulator Detected',
                            style: getBoldStyle(
                              fontSize: 16,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      content: Text(
                        'In emulator this app can not be run , PC version are comminng soon ,',
                        style: getRegularStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withValues(alpha: .8),
                        ),
                      ),
                    ),
                  ),
                );
                return;
              }

              context.read<ProfileBloc>().add(const LoadProfile());

              final config = MobileConfigManager.instance.config;
              if (config.campaignMust == "1" || config.campaignMust == "1") {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogCtx) => const PopScope(
                    canPop: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );

                try {
                  final statusResponse = await context
                      .read<CampaignRepository>()
                      .getCampaignStatus();
                  if (context.mounted) {
                    Navigator.of(context).pop(); // dismiss loader
                  }

                  if (statusResponse.isSuccess && statusResponse.data != null) {
                    final campaignsAvailable =
                        statusResponse.data!.campaignsAvailable;
                    if (campaignsAvailable && context.mounted) {
                      showToast(
                        context: context,
                        message:
                            'Login Successful! Please complete your mandatory campaign.',
                        toastificationType: ToastificationType.success,
                      );
                      Navigator.pushReplacementNamed(
                        context,
                        Routes.campaign,
                        arguments: {'isMandatory': true},
                      );
                      return;
                    }
                  }
                } catch (e) {
                  debugPrint('LoginScreen: Error checking campaign status: $e');
                  if (context.mounted) {
                    try {
                      Navigator.of(context).pop();
                    } catch (_) {}
                  }
                }
              }

              if (context.mounted) {
                showToast(
                  context: context,
                  message: 'Login Successful!',
                  toastificationType: ToastificationType.success,
                );
                navigateAndReplace(context, Routes.home);
              }
            });
          }

          if (state.status == LoginStatus.failure &&
              state.errorMessage.isNotEmpty) {
            showToast(
              context: context,
              message: state.errorMessage,
              toastificationType: ToastificationType.error,
            );
          }
        },
        child: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: AnimatedBackground()),
              SafeArea(
                child: Center(
                  child: _CardEntryAnimation(
                    controller: _cardAnimController,
                    scaleAnimation: _cardScaleAnim,
                    fadeAnimation: _cardFadeAnim,
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      width: isMobile ? screenWidth * 0.92 : 440,
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 24 : 36,
                              vertical: isMobile ? 32 : 40,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(
                                alpha: isDark ? .05 : .5,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: colorScheme.onSurface.withValues(
                                  alpha: .08,
                                ),
                                width: 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(
                                    alpha: .06,
                                  ),
                                  blurRadius: 40,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: LoginForm(
                              emailController: _emailController,
                              passwordController: _passwordController,
                              formKey: _formKey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardEntryAnimation extends AnimatedWidget {
  final Animation<double> scaleAnimation;
  final Animation<double> fadeAnimation;
  final Widget child;

  const _CardEntryAnimation({
    required AnimationController controller,
    required this.scaleAnimation,
    required this.fadeAnimation,
    required this.child,
  }) : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: fadeAnimation.value,
      child: Transform.scale(scale: scaleAnimation.value, child: child),
    );
  }
}
