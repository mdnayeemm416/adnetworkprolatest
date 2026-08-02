part of 'admin_bloc.dart';

abstract class AdminEvent extends Equatable {
  const AdminEvent();
  @override
  List<Object?> get props => [];
}

class LoadAllUsers extends AdminEvent {
  const LoadAllUsers();
}

class LoadPendingUsers extends AdminEvent {
  const LoadPendingUsers();
}

class ApproveUser extends AdminEvent {
  final String userId;
  const ApproveUser(this.userId);
  @override
  List<Object?> get props => [userId];
}

class RejectUser extends AdminEvent {
  final String userId;
  const RejectUser(this.userId);
  @override
  List<Object?> get props => [userId];
}

class BlockUser extends AdminEvent {
  final String userId;
  const BlockUser(this.userId);
  @override
  List<Object?> get props => [userId];
}

class UnblockUser extends AdminEvent {
  final String userId;
  const UnblockUser(this.userId);
  @override
  List<Object?> get props => [userId];
}

class MakeModerator extends AdminEvent {
  final String userId;
  const MakeModerator(this.userId);
  @override
  List<Object?> get props => [userId];
}

class RemoveModerator extends AdminEvent {
  final String userId;
  const RemoveModerator(this.userId);
  @override
  List<Object?> get props => [userId];
}

class ChangeTab extends AdminEvent {
  final AdminTab tab;
  const ChangeTab(this.tab);
  @override
  List<Object?> get props => [tab];
}

class SearchUsers extends AdminEvent {
  final String query;
  const SearchUsers(this.query);
  @override
  List<Object?> get props => [query];
}

class LoadResetRequests extends AdminEvent {
  const LoadResetRequests();
}

class ResetUserPassword extends AdminEvent {
  final String userId;
  const ResetUserPassword(this.userId);
  @override
  List<Object?> get props => [userId];
}

class LoadPendingDevices extends AdminEvent {
  const LoadPendingDevices();
}

class ApproveDevice extends AdminEvent {
  final String userId;
  final String deviceId;
  const ApproveDevice(this.userId, this.deviceId);
  @override
  List<Object?> get props => [userId, deviceId];
}

class RejectDevice extends AdminEvent {
  final String userId;
  final String deviceId;
  const RejectDevice(this.userId, this.deviceId);
  @override
  List<Object?> get props => [userId, deviceId];
}

class ToggleSelectionMode extends AdminEvent {
  const ToggleSelectionMode();
}

class ToggleUserSelection extends AdminEvent {
  final String userId;
  const ToggleUserSelection(this.userId);
  @override
  List<Object?> get props => [userId];
}

class UpdateSubscription extends AdminEvent {
  final String userId;
  final int autolike;
  final int? isFree;
  final String? paymentMethod;
  final String? txid;
  const UpdateSubscription(this.userId, this.autolike, {this.isFree, this.paymentMethod, this.txid});
  @override
  List<Object?> get props => [userId, autolike, isFree, paymentMethod, txid];
}

class ClearMessages extends AdminEvent {
  const ClearMessages();
  @override
  List<Object?> get props => [];
}

class BulkUpdateSubscription extends AdminEvent {
  final int autolike;
  const BulkUpdateSubscription(this.autolike);
  @override
  List<Object?> get props => [autolike];
}
