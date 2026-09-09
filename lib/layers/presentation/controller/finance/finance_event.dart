part of 'finance_bloc.dart';

abstract class FinanceEvent extends Equatable {
  const FinanceEvent();

  @override
  List<Object?> get props => [];
}

class LoadFinanceSummary extends FinanceEvent {
  final String cycle;
  final String? namespace;

  const LoadFinanceSummary({required this.cycle, this.namespace});

  @override
  List<Object?> get props => [cycle, namespace];
}

class LoadDailyDetail extends FinanceEvent {
  final String? date;
  final String? namespace;
  final int page;
  final int limit;

  const LoadDailyDetail({
    this.date,
    this.namespace,
    this.page = 1,
    this.limit = 50,
  });

  @override
  List<Object?> get props => [date, namespace, page, limit];
}

class LogPayout extends FinanceEvent {
  final double shakilAmount;
  final double nayeemAmount;
  final double rashedAmount;
  final String cycle;
  final String? namespace;
  final String? notes;

  const LogPayout({
    required this.shakilAmount,
    required this.nayeemAmount,
    required this.rashedAmount,
    required this.cycle,
    this.namespace,
    this.notes,
  });

  @override
  List<Object?> get props => [
        shakilAmount,
        nayeemAmount,
        rashedAmount,
        cycle,
        namespace,
        notes,
      ];
}

class ClearFinanceMessages extends FinanceEvent {
  const ClearFinanceMessages();
}
