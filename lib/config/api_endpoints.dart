/// Centralized API endpoint paths.
/// All endpoint strings are relative to [EnvConfig.baseUrl].
class ApiEndpoints {
  ApiEndpoints._();

  // ──────────────────────────── App Updates ───────────────────────
  static const String appUpdates = '/api/app-updates/latest';

  // ──────────────────────────── Auth ────────────────────────────
  static const String register = '/api/auth/register';
  static const String login = '/api/auth/login';
  static const String forgotPassword = '/api/auth/forgot-password';

  // ──────────────────────────── Users ───────────────────────────
  static const String changePassword = '/api/users/change-password';
  static const String myScore = '/api/users/me/score';
  static const String myStats = '/api/users/me/stats';
  static const String myActivityStats = '/api/users/me/activity-stats';
  static const String likeBackLimit = '/api/users/me/like-back-limit';
  static String userProfile(String id) => '/api/users/$id';
  static const String exploreUsers = '/api/users/explore';
  static String toggleFollow(String id) => '/api/users/$id/follow';
  static String followers(String id) => '/api/users/$id/followers';
  static String following(String id) => '/api/users/$id/following';

  // ──────────────────────────── Links ───────────────────────────
  static const String links = '/api/links';
  static const String myLinks = '/api/mylinks';
  static String linkById(String id) => '/api/links/$id';
  static String toggleLike(String id) => '/api/links/$id/like';
  static String addComment(String id) => '/api/links/$id/comment';
  static String linkComments(String id) => '/api/links/$id/comments';

  // ──────────────────────────── Admin ───────────────────────────
  static const String adminUsers = '/api/admin/users';
  static const String adminPending = '/api/admin/users/pending';
  static String adminApprove(String id) => '/api/admin/users/$id/approve';
  static String adminReject(String id) => '/api/admin/users/$id/reject';
  static String adminBlock(String id) => '/api/admin/users/$id/block';
  static String adminUnblock(String id) => '/api/admin/users/$id/unblock';
  static String adminMakeAdmin(String id) => '/api/admin/users/$id/make-admin';
  static String adminRemoveAdmin(String id) =>
      '/api/admin/users/$id/remove-admin';
  static String adminMakeModerator(String id) =>
      '/api/admin/users/$id/make-moderator';
  static String adminRemoveModerator(String id) =>
      '/api/admin/users/$id/remove-moderator';
  static String adminResetPassword(String id) =>
      '/api/admin/users/$id/reset-password';
  static const String adminResetRequests = '/api/admin/users/reset-requests';
  static String adminUpdateSubscription(String id) => '/api/admin/users/$id/subscription';
  static const String adminBulkUpdateSubscription = '/api/admin/users/bulk/subscription';
  static const String adminPendingDevices = '/api/admin/devices/pending';
  static const String adminApproveDevice = '/api/admin/devices/approve';
  static const String adminRejectDevice = '/api/admin/devices/reject';

  // ──────────────────────────── Notices ───────────────────────────
  static const String notices = '/api/notices';
  static String noticeById(String id) => '/api/notices/$id';

  // ──────────────────────────── Subscriptions ─────────────────────
  static const String checkSubscription = '/api/subscriptions/check';
  static const String getPrice = '/api/getprice';
  static const String setPrice = '/api/setprice';
  static const String adminClients = '/api/admin/clients';
  static String adminClientById(String id) => '/api/admin/clients/$id';

  // ──────────────────────────── Finance ───────────────────────────
  static const String financeSummary = '/api/admin/finance/summary';
  static const String financePayouts = '/api/admin/finance/payouts';
  static const String financeDailyDetail = '/api/admin/finance/daily-detail';
}
