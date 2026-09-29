class LeaderboardEntry {
  final int rank;
  final String userId;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? appname;
  final double ecpm;
  final double revenue;
  final int impressions;
  final int clicks;
  final String? lastSyncAt;

  LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    this.firstName,
    this.lastName,
    this.appname,
    this.ecpm = 0.0,
    this.revenue = 0.0,
    this.impressions = 0,
    this.clicks = 0,
    this.lastSyncAt,
  });

  String get displayName {
    if (firstName != null && firstName!.isNotEmpty) {
      if (lastName != null && lastName!.isNotEmpty) {
        return '$firstName $lastName';
      }
      return firstName!;
    }
    return username;
  }

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: int.tryParse(json['rank']?.toString() ?? '0') ?? 0,
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Publisher',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      appname: json['appname'] as String?,
      ecpm: double.tryParse(json['ecpm']?.toString() ?? '0.0') ?? 0.0,
      revenue: double.tryParse(json['revenue']?.toString() ?? '0.0') ?? 0.0,
      impressions: int.tryParse(json['impressions']?.toString() ?? '0') ?? 0,
      clicks: int.tryParse(json['clicks']?.toString() ?? '0') ?? 0,
      lastSyncAt: json['last_sync_at'] as String?,
    );
  }
}

class LeaderboardSummary {
  final double totalRevenue;
  final int totalImpressions;
  final int totalClicks;
  final double avgEcpm;

  LeaderboardSummary({
    this.totalRevenue = 0.0,
    this.totalImpressions = 0,
    this.totalClicks = 0,
    this.avgEcpm = 0.0,
  });

  factory LeaderboardSummary.fromJson(Map<String, dynamic> json) {
    return LeaderboardSummary(
      totalRevenue: double.tryParse(json['total_revenue']?.toString() ?? '0.0') ?? 0.0,
      totalImpressions: int.tryParse(json['total_impressions']?.toString() ?? '0') ?? 0,
      totalClicks: int.tryParse(json['total_clicks']?.toString() ?? '0') ?? 0,
      avgEcpm: double.tryParse(json['avg_ecpm']?.toString() ?? '0.0') ?? 0.0,
    );
  }
}

class CurrentUserRankDetail {
  final int rank;
  final double value;

  CurrentUserRankDetail({this.rank = 0, this.value = 0.0});

  factory CurrentUserRankDetail.fromJson(Map<String, dynamic> json) {
    return CurrentUserRankDetail(
      rank: int.tryParse(json['rank']?.toString() ?? '0') ?? 0,
      value: double.tryParse(json['value']?.toString() ?? '0.0') ?? 0.0,
    );
  }
}

class CurrentUserLeaderboardStatus {
  final bool hasKey;
  final String? tokenStatus;
  final String? lastSyncAt;
  final CurrentUserRankDetail? ecpm;
  final CurrentUserRankDetail? revenue;
  final CurrentUserRankDetail? impressions;

  CurrentUserLeaderboardStatus({
    this.hasKey = false,
    this.tokenStatus,
    this.lastSyncAt,
    this.ecpm,
    this.revenue,
    this.impressions,
  });

  factory CurrentUserLeaderboardStatus.fromJson(Map<String, dynamic> json) {
    return CurrentUserLeaderboardStatus(
      hasKey: json['has_key'] == true,
      tokenStatus: json['token_status'] as String?,
      lastSyncAt: json['last_sync_at'] as String?,
      ecpm: json['ecpm'] is Map<String, dynamic>
          ? CurrentUserRankDetail.fromJson(json['ecpm'] as Map<String, dynamic>)
          : null,
      revenue: json['revenue'] is Map<String, dynamic>
          ? CurrentUserRankDetail.fromJson(json['revenue'] as Map<String, dynamic>)
          : null,
      impressions: json['impressions'] is Map<String, dynamic>
          ? CurrentUserRankDetail.fromJson(json['impressions'] as Map<String, dynamic>)
          : null,
    );
  }
}

class HourlyLeaderboardResponse {
  final String? statDate;
  final int? statHour;
  final String? hourLabel;
  final String? updatedAt;
  final String? nextSyncAt;
  final bool isCached;
  final int totalPublishers;
  final LeaderboardSummary summary;
  final List<LeaderboardEntry> ecpmLeaderboard;
  final List<LeaderboardEntry> revenueLeaderboard;
  final List<LeaderboardEntry> impressionsLeaderboard;
  final CurrentUserLeaderboardStatus? currentUser;

  HourlyLeaderboardResponse({
    this.statDate,
    this.statHour,
    this.hourLabel,
    this.updatedAt,
    this.nextSyncAt,
    this.isCached = false,
    this.totalPublishers = 0,
    required this.summary,
    this.ecpmLeaderboard = const [],
    this.revenueLeaderboard = const [],
    this.impressionsLeaderboard = const [],
    this.currentUser,
  });

  factory HourlyLeaderboardResponse.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> data = json.containsKey('data') && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    final summaryMap = data['summary'] is Map<String, dynamic>
        ? data['summary'] as Map<String, dynamic>
        : <String, dynamic>{};

    final leaderboardsMap = data['leaderboards'] is Map<String, dynamic>
        ? data['leaderboards'] as Map<String, dynamic>
        : <String, dynamic>{};

    List<LeaderboardEntry> parseList(dynamic rawList) {
      if (rawList is List) {
        return rawList
            .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    }

    final currentUserMap = data['currentUser'] is Map<String, dynamic>
        ? data['currentUser'] as Map<String, dynamic>
        : null;

    return HourlyLeaderboardResponse(
      statDate: data['stat_date']?.toString(),
      statHour: int.tryParse(data['stat_hour']?.toString() ?? ''),
      hourLabel: data['hour_label']?.toString(),
      updatedAt: data['updated_at']?.toString(),
      nextSyncAt: data['next_sync_at']?.toString(),
      isCached: data['is_cached'] == true,
      totalPublishers: int.tryParse(data['total_publishers']?.toString() ?? '0') ?? 0,
      summary: LeaderboardSummary.fromJson(summaryMap),
      ecpmLeaderboard: parseList(leaderboardsMap['ecpm']),
      revenueLeaderboard: parseList(leaderboardsMap['revenue']),
      impressionsLeaderboard: parseList(leaderboardsMap['impressions']),
      currentUser: currentUserMap != null
          ? CurrentUserLeaderboardStatus.fromJson(currentUserMap)
          : null,
    );
  }
}
