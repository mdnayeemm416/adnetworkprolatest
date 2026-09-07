class UserStatsModel {
  final int totalLike;
  final int totalReceived;
  final int likesGiven;
  final int likesReceived;
  final int likesToday;
  final int likesGivenToday;
  final int likesReceivedToday;
  final int campaignsCompletedToday;
  final int campaignLikesReceivedToday;
  final int followers;
  final int following;
  final String activeLinkLimit;
  final int maxLikeBackLimit;

  UserStatsModel({
    this.totalLike = 0,
    this.totalReceived = 0,
    this.likesGiven = 0,
    this.likesReceived = 0,
    this.likesToday = 0,
    this.likesGivenToday = 0,
    this.likesReceivedToday = 0,
    this.campaignsCompletedToday = 0,
    this.campaignLikesReceivedToday = 0,
    this.followers = 0,
    this.following = 0,
    this.activeLinkLimit = '',
    this.maxLikeBackLimit = 0,
  });

  factory UserStatsModel.fromJson(Map<String, dynamic> json) {
    return UserStatsModel(
      totalLike: _parseInt(json['total_like']),
      totalReceived: _parseInt(json['total_received']),
      likesGiven: _parseInt(json['likes_given']),
      likesReceived: _parseInt(json['likes_received']),
      likesToday: _parseInt(json['likes_today']),
      likesGivenToday: _parseInt(json['likes_given_today']),
      likesReceivedToday: _parseInt(json['likes_received_today']),
      campaignsCompletedToday: _parseInt(json['campaigns_completed_today']),
      campaignLikesReceivedToday: _parseInt(json['campaign_likes_received_today']),
      followers: _parseInt(json['followers']),
      following: _parseInt(json['following']),
      activeLinkLimit: json['active_link_limit']?.toString() ?? '',
      maxLikeBackLimit: _parseInt(json['max_like_back_limit']),
    );
  }

  static int _parseInt(dynamic val) {
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }
}

