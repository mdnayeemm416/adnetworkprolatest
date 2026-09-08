import 'package:adnetwork/core/services/token_storage.dart';
import 'package:adnetwork/core/services/mobile_config_manager.dart';
import 'package:adnetwork/layers/data/repo/remote/auth_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final AuthRepository authRepository;

  LoginBloc({required this.authRepository}) : super(const LoginState()) {
    on<LoginSubmitted>(_onLoginSubmitted);
    on<TogglePasswordVisibility>(_onTogglePasswordVisibility);
    on<ToggleRememberMe>(_onToggleRememberMe);
    on<InitializeRememberMe>(_onInitializeRememberMe);
    on<ForgotPasswordSubmitted>(_onForgotPasswordSubmitted);
  }

  void _onInitializeRememberMe(
    InitializeRememberMe event,
    Emitter<LoginState> emit,
  ) {
    emit(state.copyWith(isRememberMe: event.value));
  }

  Future<void> _onLoginSubmitted(
    LoginSubmitted event,
    Emitter<LoginState> emit,
  ) async {
    // Basic validation
    if (event.email.isEmpty || event.password.isEmpty) {
      emit(
        state.copyWith(
          status: LoginStatus.failure,
          errorMessage: 'Please fill in all fields',
        ),
      );
      return;
    }

    emit(state.copyWith(status: LoginStatus.loading, errorMessage: ''));

    try {
      final response = await authRepository.login(
        email: event.email,
        password: event.password,
      );

      if (response.isSuccess && response.data != null) {
        // Save token
        final token = response.data!.token;
        if (token != null) {
          await TokenStorage.instance.saveToken(token);
        }

        // Save user ID
        final userId = response.data!.user?.id;
        if (userId != null) {
          await TokenStorage.instance.saveUserId(userId);
        }

        // Cache credentials if Remember Me is checked, otherwise clear them
        if (state.isRememberMe) {
          await TokenStorage.instance.saveCredentials(
            event.email,
            event.password,
          );
        } else {
          await TokenStorage.instance.clearCredentials();
        }

        // Clear manual logout flag
        await TokenStorage.instance.setManualLogout(false);
        // Turn off autoplay flag in TokenStorage on login
        await TokenStorage.instance.resetAutoplayFlagsOnLogin();
        // Fetch subscription check
        final username = response.data!.user?.username;
        if (username != null && username.isNotEmpty) {
          try {
            final subResponse = await authRepository.checkSubscription(
              username,
            );
            debugPrint('login_bloc: checkSubscription response success: ${subResponse.isSuccess}, data: ${subResponse.data}');
            if (subResponse.isSuccess && subResponse.data != null) {
              final subData = subResponse.data;
              if (subData is Map<String, dynamic>) {
                final subscription = subData['subscription'];
                if (subscription is Map) {
                  final autolike = subscription['autolike'];
                  final isEnabled = autolike == 1 || autolike == '1' || autolike.toString() == '1';
                  await TokenStorage.instance.saveAutoLikeEnabled(isEnabled);
                  debugPrint('login_bloc: parsed autolike as $autolike, saving enabled: $isEnabled');
                } else {
                  debugPrint('login_bloc: subscription field is not a Map: $subscription');
                }
              } else {
                debugPrint('login_bloc: subResponse.data is not a Map: $subData');
              }
            }
          } catch (e) {
            debugPrint('login_bloc: Error checking subscription: $e');
          }
        }

        // Fetch mobile config from API and cache it on login success
        try {
          await MobileConfigManager.instance.fetchAndCacheConfig();
        } catch (e) {
          debugPrint('login_bloc: Error fetching mobile config: $e');
        }

        emit(state.copyWith(status: LoginStatus.success));
      } else {
        emit(
          state.copyWith(
            status: LoginStatus.failure,
            errorMessage: response.message ?? 'Login failed',
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(status: LoginStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  void _onTogglePasswordVisibility(
    TogglePasswordVisibility event,
    Emitter<LoginState> emit,
  ) {
    emit(state.copyWith(isPasswordVisible: !state.isPasswordVisible));
  }

  void _onToggleRememberMe(ToggleRememberMe event, Emitter<LoginState> emit) {
    emit(state.copyWith(isRememberMe: !state.isRememberMe));
  }

  Future<void> _onForgotPasswordSubmitted(
    ForgotPasswordSubmitted event,
    Emitter<LoginState> emit,
  ) async {
    if (event.identifier.isEmpty) {
      emit(
        state.copyWith(
          status: LoginStatus.failure,
          errorMessage: 'Please enter your email or username',
        ),
      );
      return;
    }
    if (event.newPassword.isEmpty) {
      emit(
        state.copyWith(
          status: LoginStatus.failure,
          errorMessage: 'Please enter your new password',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: LoginStatus.loading,
        errorMessage: '',
        forgotPasswordSuccessMessage: '',
      ),
    );

    try {
      final response = await authRepository.forgotPassword(
        identifier: event.identifier,
        newPassword: event.newPassword,
      );

      if (response.isSuccess) {
        emit(
          state.copyWith(
            status: LoginStatus.initial,
            forgotPasswordSuccessMessage:
                response.message ??
                'Password reset requested successfully. Please wait for an administrator.',
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: LoginStatus.failure,
            errorMessage:
                response.message ?? 'Failed to request password reset',
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(status: LoginStatus.failure, errorMessage: e.toString()),
      );
    }
  }
}
