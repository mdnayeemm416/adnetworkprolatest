import 'package:adnetwork/layers/data/model/device_association_model.dart';
import 'package:adnetwork/layers/data/model/user_model.dart';
import 'package:adnetwork/layers/data/repo/remote/admin_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'admin_event.dart';
part 'admin_state.dart';

class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final AdminRepository adminRepository;

  AdminBloc({required this.adminRepository}) : super(const AdminState()) {
    on<LoadAllUsers>(_onLoadAll);
    on<LoadPendingUsers>(_onLoadPending);
    on<ApproveUser>(_onApprove);
    on<RejectUser>(_onReject);
    on<BlockUser>(_onBlock);
    on<UnblockUser>(_onUnblock);
    on<MakeModerator>(_onMakeModerator);
    on<RemoveModerator>(_onRemoveModerator);
    on<ChangeTab>(_onChangeTab);
    on<SearchUsers>(_onSearch);
    on<LoadResetRequests>(_onLoadResetRequests);
    on<ResetUserPassword>(_onResetPassword);
    on<LoadPendingDevices>(_onLoadPendingDevices);
    on<ApproveDevice>(_onApproveDevice);
    on<RejectDevice>(_onRejectDevice);
    on<ToggleSelectionMode>(_onToggleSelectionMode);
    on<ToggleUserSelection>(_onToggleUserSelection);
    on<UpdateSubscription>(_onUpdateSubscription);
    on<BulkUpdateSubscription>(_onBulkUpdateSubscription);
    on<ClearMessages>((event, emit) {
      emit(state.copyWith(errorMessage: '', successMessage: ''));
    });
  }

  Future<void> _onLoadAll(LoadAllUsers event, Emitter<AdminState> emit) async {
    emit(state.copyWith(status: AdminStatus.loading));

    try {
      final response = await adminRepository.getAllUsers();

      if (response.isSuccess) {
        final users = response.dataList ?? <UserModel>[];
        emit(state.copyWith(
          status: AdminStatus.loaded,
          allUsers: users,
          filteredUsers: _filterByTab(users, state.currentTab),
        ));
      } else {
        emit(state.copyWith(
          status: AdminStatus.error,
          errorMessage: response.message ?? 'Failed to load users',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: AdminStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onLoadPending(
    LoadPendingUsers event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(status: AdminStatus.loading));

    try {
      final response = await adminRepository.getPendingApprovals();

      if (response.isSuccess) {
        final pending = response.dataList ?? <UserModel>[];
        emit(state.copyWith(
          status: AdminStatus.loaded,
          pendingUsers: pending,
        ));
      } else {
        emit(state.copyWith(
          status: AdminStatus.error,
          errorMessage: response.message ?? 'Failed to load pending users',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: AdminStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onApprove(ApproveUser event, Emitter<AdminState> emit) async {
    emit(state.copyWith(actionUserId: event.userId, actionType: 'approve'));
    try {
      final response = await adminRepository.approveUser(event.userId);
      if (response.isSuccess) {
        _updateUserInList(emit, event.userId, isApproved: 1);
        emit(state.copyWith(successMessage: 'User approved successfully', actionUserId: '', actionType: ''));
      } else {
        emit(state.copyWith(errorMessage: response.message ?? 'Failed', actionUserId: '', actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }

  void _onToggleSelectionMode(ToggleSelectionMode event, Emitter<AdminState> emit) {
    if (state.isSelectionMode) {
      emit(state.copyWith(isSelectionMode: false, selectedUserIds: {}));
    } else {
      emit(state.copyWith(isSelectionMode: true));
    }
  }

  void _onToggleUserSelection(ToggleUserSelection event, Emitter<AdminState> emit) {
    final updatedSelection = Set<String>.from(state.selectedUserIds);
    if (updatedSelection.contains(event.userId)) {
      updatedSelection.remove(event.userId);
    } else {
      updatedSelection.add(event.userId);
    }
    emit(state.copyWith(selectedUserIds: updatedSelection));
  }

  Future<void> _onUpdateSubscription(UpdateSubscription event, Emitter<AdminState> emit) async {
    emit(state.copyWith(actionUserId: event.userId, actionType: 'update_sub'));
    try {
      final response = await adminRepository.updateSubscription(
        event.userId,
        event.autolike,
        isFree: event.isFree,
        paymentMethod: event.paymentMethod,
        txid: event.txid,
      );
      if (response.isSuccess) {
        _updateUserInList(emit, event.userId, autolike: event.autolike);
        emit(state.copyWith(successMessage: 'Subscription updated', actionUserId: '', actionType: ''));
      } else {
        emit(state.copyWith(errorMessage: response.message ?? 'Failed', actionUserId: '', actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }

  Future<void> _onBulkUpdateSubscription(BulkUpdateSubscription event, Emitter<AdminState> emit) async {
    if (state.selectedUserIds.isEmpty) return;

    emit(state.copyWith(actionType: 'bulk_update_sub'));
    try {
      final userIdsList = state.selectedUserIds.toList();
      final response = await adminRepository.bulkUpdateSubscription(userIdsList, event.autolike);
      if (response.isSuccess) {
        for (var userId in userIdsList) {
          _updateUserInList(emit, userId, autolike: event.autolike);
        }
        emit(state.copyWith(
          successMessage: 'Bulk subscription updated',
          actionType: '',
          isSelectionMode: false,
          selectedUserIds: {},
        ));
      } else {
        emit(state.copyWith(errorMessage: response.message ?? 'Failed to update bulk', actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString(), actionType: ''));
    }
  }

  Future<void> _onReject(RejectUser event, Emitter<AdminState> emit) async {
    emit(state.copyWith(actionUserId: event.userId, actionType: 'reject'));
    try {
      final response = await adminRepository.rejectUser(event.userId);
      if (response.isSuccess) {
        // Remove from pending list
        final pendingUsers = state.pendingUsers.where((u) => u.id != event.userId).toList();
        emit(state.copyWith(pendingUsers: pendingUsers, successMessage: 'User rejected', actionUserId: '', actionType: ''));
      } else {
        emit(state.copyWith(errorMessage: response.message ?? 'Failed', actionUserId: '', actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }

  Future<void> _onBlock(BlockUser event, Emitter<AdminState> emit) async {
    emit(state.copyWith(actionUserId: event.userId, actionType: 'block'));
    try {
      final response = await adminRepository.blockUser(event.userId);
      if (response.isSuccess) {
        _updateUserInList(emit, event.userId, isBlocked: 1);
        emit(state.copyWith(successMessage: 'User blocked', actionUserId: '', actionType: ''));
      } else {
        emit(state.copyWith(errorMessage: response.message ?? 'Failed', actionUserId: '', actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }

  Future<void> _onUnblock(UnblockUser event, Emitter<AdminState> emit) async {
    emit(state.copyWith(actionUserId: event.userId, actionType: 'unblock'));
    try {
      final response = await adminRepository.unblockUser(event.userId);
      if (response.isSuccess) {
        _updateUserInList(emit, event.userId, isBlocked: 0);
        emit(state.copyWith(successMessage: 'User unblocked', actionUserId: '', actionType: ''));
      } else {
        emit(state.copyWith(errorMessage: response.message ?? 'Failed', actionUserId: '', actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }



  Future<void> _onMakeModerator(
    MakeModerator event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(
        actionUserId: event.userId, actionType: 'make-moderator'));
    try {
      final response = await adminRepository.makeModerator(event.userId);
      if (response.isSuccess) {
        _updateUserInList(emit, event.userId, role: 'moderator');
        emit(state.copyWith(
            successMessage: 'User promoted to moderator',
            actionUserId: '',
            actionType: ''));
      } else {
        emit(state.copyWith(
            errorMessage: response.message ?? 'Failed',
            actionUserId: '',
            actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(
          errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }

  Future<void> _onRemoveModerator(
    RemoveModerator event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(
        actionUserId: event.userId, actionType: 'remove-moderator'));
    try {
      final response = await adminRepository.removeModerator(event.userId);
      if (response.isSuccess) {
        _updateUserInList(emit, event.userId, role: 'user');
        emit(state.copyWith(
            successMessage: 'Moderator role removed',
            actionUserId: '',
            actionType: ''));
      } else {
        emit(state.copyWith(
            errorMessage: response.message ?? 'Failed',
            actionUserId: '',
            actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(
          errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }

  Future<void> _onLoadResetRequests(
    LoadResetRequests event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(status: AdminStatus.loading));

    try {
      final response = await adminRepository.getResetRequests();

      if (response.isSuccess) {
        final users = response.dataList ?? <UserModel>[];
        emit(state.copyWith(
          status: AdminStatus.loaded,
          resetRequestedUsers: users,
        ));
      } else {
        emit(state.copyWith(
          status: AdminStatus.error,
          errorMessage: response.message ?? 'Failed to load reset requests',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: AdminStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onResetPassword(
    ResetUserPassword event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(
        actionUserId: event.userId, actionType: 'reset-password'));
    try {
      final response = await adminRepository.resetPassword(event.userId);
      if (response.isSuccess) {
        _updateUserInList(emit, event.userId, resetRequested: 0);
        // Also remove from resetRequestedUsers list if it exists there
        final resetUsers = state.resetRequestedUsers
            .where((u) => u.id != event.userId)
            .toList();
        emit(state.copyWith(
            resetRequestedUsers: resetUsers,
            successMessage: 'Password reset successfully to 123456',
            actionUserId: '',
            actionType: ''));
      } else {
        emit(state.copyWith(
            errorMessage: response.message ?? 'Failed',
            actionUserId: '',
            actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(
          errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }

  Future<void> _onLoadPendingDevices(
    LoadPendingDevices event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(status: AdminStatus.loading));

    try {
      final response = await adminRepository.getPendingDevices();

      if (response.isSuccess) {
        final devices = response.dataList ?? <DeviceAssociationModel>[];
        emit(state.copyWith(
          status: AdminStatus.loaded,
          pendingDevices: devices,
        ));
      } else {
        emit(state.copyWith(
          status: AdminStatus.error,
          errorMessage: response.message ?? 'Failed to load pending devices',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: AdminStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onApproveDevice(
    ApproveDevice event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(
        actionUserId: event.userId, actionType: 'approve-device'));
    try {
      final response = await adminRepository.approveDevice(event.userId, event.deviceId);
      if (response.isSuccess) {
        final remaining = state.pendingDevices
            .where((d) => d.userId != event.userId || d.deviceId != event.deviceId)
            .toList();
        emit(state.copyWith(
            pendingDevices: remaining,
            successMessage: 'Device approved successfully',
            actionUserId: '',
            actionType: ''));
      } else {
        emit(state.copyWith(
            errorMessage: response.message ?? 'Failed',
            actionUserId: '',
            actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(
          errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }

  Future<void> _onRejectDevice(
    RejectDevice event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(
        actionUserId: event.userId, actionType: 'reject-device'));
    try {
      final response = await adminRepository.rejectDevice(event.userId, event.deviceId);
      if (response.isSuccess) {
        final remaining = state.pendingDevices
            .where((d) => d.userId != event.userId || d.deviceId != event.deviceId)
            .toList();
        emit(state.copyWith(
            pendingDevices: remaining,
            successMessage: 'Device rejected successfully',
            actionUserId: '',
            actionType: ''));
      } else {
        emit(state.copyWith(
            errorMessage: response.message ?? 'Failed',
            actionUserId: '',
            actionType: ''));
      }
    } catch (e) {
      emit(state.copyWith(
          errorMessage: e.toString(), actionUserId: '', actionType: ''));
    }
  }

  void _onChangeTab(ChangeTab event, Emitter<AdminState> emit) {
    final filtered = _filterByTab(state.allUsers, event.tab);
    emit(state.copyWith(currentTab: event.tab, filteredUsers: filtered, searchQuery: ''));
    if (event.tab == AdminTab.devices && state.pendingDevices.isEmpty) {
      add(const LoadPendingDevices());
    }
  }

  void _onSearch(SearchUsers event, Emitter<AdminState> emit) {
    final query = event.query.toLowerCase();
    final tabUsers = _filterByTab(state.allUsers, state.currentTab);
    final searched = query.isEmpty
        ? tabUsers
        : tabUsers.where((u) {
            final name = (u.username ?? '').toLowerCase();
            final email = (u.email ?? '').toLowerCase();
            return name.contains(query) || email.contains(query);
          }).toList();
    emit(state.copyWith(filteredUsers: searched, searchQuery: event.query));
  }

  List<UserModel> _filterByTab(List<UserModel> users, AdminTab tab) {
    switch (tab) {
      case AdminTab.all:
        return users;
      case AdminTab.pending:
        return users.where((u) => u.isApproved == 0).toList();
      case AdminTab.blocked:
        return users.where((u) => u.isBlocked == 1).toList();
      case AdminTab.moderators:
        return users.where((u) => u.role == 'moderator').toList();
      case AdminTab.resetRequests:
        return users.where((u) => u.resetRequested == 1).toList();
      case AdminTab.devices:
        return users; // pending devices list is stored separately
    }
  }

  void _updateUserInList(
    Emitter<AdminState> emit,
    String userId, {
    int? isApproved,
    int? isBlocked,
    int? resetRequested,
    String? role,
    int? autolike,
  }) {
    final allUsers = state.allUsers.map((u) {
      if (u.id == userId) {
        return u.copyWith(
          isApproved: isApproved ?? u.isApproved,
          isBlocked: isBlocked ?? u.isBlocked,
          resetRequested: resetRequested ?? u.resetRequested,
          role: role ?? u.role,
          autolike: autolike ?? u.autolike,
        );
      }
      return u;
    }).toList();

    final filtered = _filterByTab(allUsers, state.currentTab);
    emit(state.copyWith(allUsers: allUsers, filteredUsers: filtered));
  }
}
