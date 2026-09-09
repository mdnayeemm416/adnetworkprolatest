import 'package:adnetwork/layers/data/model/finance_summary_model.dart';
import 'package:adnetwork/layers/data/model/finance_daily_detail_model.dart';
import 'package:adnetwork/layers/data/repo/remote/admin_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'finance_event.dart';
part 'finance_state.dart';

class FinanceBloc extends Bloc<FinanceEvent, FinanceState> {
  final AdminRepository adminRepository;

  FinanceBloc({required this.adminRepository}) : super(const FinanceState()) {
    on<LoadFinanceSummary>(_onLoadSummary);
    on<LoadDailyDetail>(_onLoadDailyDetail);
    on<LogPayout>(_onLogPayout);
    on<ClearFinanceMessages>(_onClearMessages);
  }

  Future<void> _onLoadSummary(
    LoadFinanceSummary event,
    Emitter<FinanceState> emit,
  ) async {
    emit(state.copyWith(
      status: FinanceStatus.loading,
      activeCycle: event.cycle,
      activeNamespace: event.namespace ?? 'all',
      errorMessage: '',
      successMessage: '',
    ));

    try {
      final response = await adminRepository.getFinanceSummary(
        cycle: event.cycle,
        namespace: event.namespace,
      );

      if (response.isSuccess && response.data != null) {
        emit(state.copyWith(
          status: FinanceStatus.loaded,
          summary: response.data,
        ));
      } else {
        emit(state.copyWith(
          status: FinanceStatus.error,
          errorMessage: response.message ?? 'Failed to load finance summary',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onLogPayout(
    LogPayout event,
    Emitter<FinanceState> emit,
  ) async {
    emit(state.copyWith(
      status: FinanceStatus.logging,
      errorMessage: '',
      successMessage: '',
    ));

    try {
      final response = await adminRepository.logPartnerPayout(
        shakilAmount: event.shakilAmount,
        nayeemAmount: event.nayeemAmount,
        rashedAmount: event.rashedAmount,
        cycle: event.cycle,
        namespace: event.namespace,
        notes: event.notes,
      );

      if (response.isSuccess) {
        emit(state.copyWith(
          status: FinanceStatus.success,
          successMessage: response.message ?? 'Partner payout recorded successfully',
        ));
        // Reload summary and daily detail after logging successfully
        add(LoadFinanceSummary(
          cycle: event.cycle,
          namespace: event.namespace,
        ));
        add(LoadDailyDetail(
          date: state.activeDetailDate,
          namespace: event.namespace,
        ));
      } else {
        emit(state.copyWith(
          status: FinanceStatus.error,
          errorMessage: response.message ?? 'Failed to log partner payout',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onLoadDailyDetail(
    LoadDailyDetail event,
    Emitter<FinanceState> emit,
  ) async {
    emit(state.copyWith(
      detailStatus: FinanceStatus.loading,
      activeDetailDate: event.date,
      activeNamespace: event.namespace ?? state.activeNamespace,
      currentDetailPage: event.page,
      errorMessage: '',
      successMessage: '',
    ));

    try {
      final response = await adminRepository.getDailyDetail(
        date: event.date,
        namespace: event.namespace ?? (state.activeNamespace == 'all' ? null : state.activeNamespace),
        page: event.page,
        limit: event.limit,
      );

      if (response.isSuccess && response.data != null) {
        emit(state.copyWith(
          detailStatus: FinanceStatus.loaded,
          dailyDetail: response.data,
          currentDetailPage: event.page,
        ));
      } else {
        emit(state.copyWith(
          detailStatus: FinanceStatus.error,
          errorMessage: response.message ?? 'Failed to load daily details',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        detailStatus: FinanceStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onClearMessages(
    ClearFinanceMessages event,
    Emitter<FinanceState> emit,
  ) {
    emit(state.copyWith(errorMessage: '', successMessage: ''));
  }
}
