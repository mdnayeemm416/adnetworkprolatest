import 'package:adnetwork/layers/data/model/link_model.dart';

class UserModel {
  final String? id;
  final String? username;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? profilePhoto;
  final String? bio;
  final String? gender;
  final String? role;
  final int? isApproved;
  final int? isBlocked;
  final double? baseScore;
  final double? cachedScore;
  final int? lifetimeLikesGiven;
  final DateTime? lastScoreUpdatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? resetRequested;
  final int? activeLinkLimit;
  final String? appname;
  final int? globalAdmin;
  final String? allowedNamespaces;
  final int? autolike;
  final DateTime? subscriptionStartedAt;
  final int? isFreeSubscription;
  final String? subscriptionToggledBy;
  final String? paymentMethod;
  final String? resetPassword;
  final int? campaignsCompleted;
  final int? currentCampaignLikesGiven;
  final int? currentCampaignTotalLinks;
  final int? feedLikesGivenInCycle;
  final int? campaignCycleUnlocked;
  final DateTime? campaignCycleCompletedAt;
  int followersCount;
  int followingCount;
  int linkCount;
  int campaignLinkCount;
  int likesReceived;
  final double? campaignScore;
  final double? effectiveScore;
  final String? status;
  bool isFollowing;
  final List<LinkModel>? links;

  UserModel({
    this.id,
    this.username,
    this.firstName,
    this.lastName,
    this.email,
    this.profilePhoto,
    this.bio,
    this.gender,
    this.role,
    this.isApproved,
    this.isBlocked,
    this.baseScore,
    this.cachedScore,
    this.lifetimeLikesGiven,
    this.lastScoreUpdatedAt,
    this.createdAt,
    this.updatedAt,
    this.resetRequested,
    this.activeLinkLimit,
    this.appname,
    this.globalAdmin,
    this.allowedNamespaces,
    this.autolike,
    this.subscriptionStartedAt,
    this.isFreeSubscription,
    this.subscriptionToggledBy,
    this.paymentMethod,
    this.resetPassword,
    this.campaignsCompleted,
    this.currentCampaignLikesGiven,
    this.currentCampaignTotalLinks,
    this.feedLikesGivenInCycle,
    this.campaignCycleUnlocked,
    this.campaignCycleCompletedAt,
    this.followersCount = 0,
    this.followingCount = 0,
    this.linkCount = 0,
    this.campaignLinkCount = 0,
    this.likesReceived = 0,
    this.campaignScore,
    this.effectiveScore,
    this.status,
    this.isFollowing = false,
    this.links,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString(),
      username: json['username'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      email: json['email'] as String?,
      profilePhoto: json['profile_photo'] as String?,
      bio: json['bio'] as String?,
      gender: json['gender'] as String?,
      role: json['role'] as String?,
      isApproved: json['is_approved'] as int?,
      isBlocked: json['is_blocked'] as int?,
      baseScore: (json['base_score'] as num?)?.toDouble(),
      cachedScore: (json['cached_score'] as num?)?.toDouble(),
      lifetimeLikesGiven: json['lifetime_likes_given'] as int?,
      lastScoreUpdatedAt: json['last_score_updated_at'] != null
          ? DateTime.tryParse(json['last_score_updated_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      resetRequested: json['reset_requested'] as int?,
      activeLinkLimit: json['active_link_limit'] as int?,
      appname: json['appname'] as String?,
      globalAdmin: json['global_admin'] as int?,
      allowedNamespaces: json['allowed_namespaces'] as String?,
      autolike: json['subscription'] != null 
          ? json['subscription']['autolike'] as int? 
          : json['autolike'] as int?,
      subscriptionStartedAt: json['subscription'] != null && json['subscription']['subscription_started_at'] != null
          ? DateTime.tryParse(json['subscription']['subscription_started_at'].toString())
          : json['subscription_started_at'] != null
              ? DateTime.tryParse(json['subscription_started_at'].toString())
              : null,
      isFreeSubscription: json['subscription'] != null
          ? json['subscription']['is_free_subscription'] as int?
          : json['is_free_subscription'] as int?,
      subscriptionToggledBy: json['subscription'] != null
          ? json['subscription']['subscription_toggled_by'] as String?
          : json['subscription_toggled_by'] as String?,
      paymentMethod: json['subscription'] != null
          ? json['subscription']['payment_method'] as String?
          : json['payment_method'] as String?,
      resetPassword: json['reset_password'] as String?,
      campaignsCompleted: json['campaigns_completed'] as int?,
      currentCampaignLikesGiven: json['current_campaign_likes_given'] as int?,
      currentCampaignTotalLinks: json['current_campaign_total_links'] as int?,
      feedLikesGivenInCycle: json['feed_likes_given_in_cycle'] as int?,
      campaignCycleUnlocked: json['campaign_cycle_unlocked'] as int?,
      campaignCycleCompletedAt: json['campaign_cycle_completed_at'] != null
          ? DateTime.tryParse(json['campaign_cycle_completed_at'].toString())
          : null,
      followersCount: (json['follower_count'] as int?) ?? (json['followers_count'] as int?) ?? 0,
      followingCount: (json['following_count'] as int?) ?? 0,
      linkCount: (json['link_count'] as int?) ?? 0,
      campaignLinkCount: (json['campaign_link_count'] as int?) ?? 0,
      likesReceived: (json['likes_received'] as int?) ?? 0,
      campaignScore: (json['campaign_score'] as num?)?.toDouble(),
      effectiveScore: (json['effective_score'] as num?)?.toDouble(),
      status: json['status'] as String?,
      isFollowing: (json['is_following'] as bool?) ?? false,
      links: json['links'] != null
          ? (json['links'] as List).map((l) => LinkModel.fromJson(l as Map<String, dynamic>)).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'first_name': firstName,
    'last_name': lastName,
    'email': email,
    'profile_photo': profilePhoto,
    'bio': bio,
    'gender': gender,
    'role': role,
    'is_approved': isApproved,
    'is_blocked': isBlocked,
    'base_score': baseScore,
    'cached_score': cachedScore,
    'lifetime_likes_given': lifetimeLikesGiven,
    'last_score_updated_at': lastScoreUpdatedAt?.toIso8601String(),
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'reset_requested': resetRequested,
    'active_link_limit': activeLinkLimit,
    'appname': appname,
    'global_admin': globalAdmin,
    'allowed_namespaces': allowedNamespaces,
    'autolike': autolike,
    'subscription_started_at': subscriptionStartedAt?.toIso8601String(),
    'is_free_subscription': isFreeSubscription,
    'subscription_toggled_by': subscriptionToggledBy,
    'payment_method': paymentMethod,
    'reset_password': resetPassword,
    'campaigns_completed': campaignsCompleted,
    'current_campaign_likes_given': currentCampaignLikesGiven,
    'current_campaign_total_links': currentCampaignTotalLinks,
    'feed_likes_given_in_cycle': feedLikesGivenInCycle,
    'campaign_cycle_unlocked': campaignCycleUnlocked,
    'campaign_cycle_completed_at': campaignCycleCompletedAt?.toIso8601String(),
    'followers_count': followersCount,
    'following_count': followingCount,
    'link_count': linkCount,
    'campaign_link_count': campaignLinkCount,
    'likes_received': likesReceived,
    'campaign_score': campaignScore,
    'effective_score': effectiveScore,
    'status': status,
    'is_following': isFollowing,
  };

  UserModel copyWith({
    String? id,
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? profilePhoto,
    String? bio,
    String? gender,
    String? role,
    int? isApproved,
    int? isBlocked,
    double? baseScore,
    double? cachedScore,
    int? lifetimeLikesGiven,
    DateTime? lastScoreUpdatedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? resetRequested,
    int? activeLinkLimit,
    String? appname,
    int? globalAdmin,
    String? allowedNamespaces,
    int? autolike,
    DateTime? subscriptionStartedAt,
    int? isFreeSubscription,
    String? subscriptionToggledBy,
    String? paymentMethod,
    String? resetPassword,
    int? campaignsCompleted,
    int? currentCampaignLikesGiven,
    int? currentCampaignTotalLinks,
    int? feedLikesGivenInCycle,
    int? campaignCycleUnlocked,
    DateTime? campaignCycleCompletedAt,
    int? followersCount,
    int? followingCount,
    int? linkCount,
    int? campaignLinkCount,
    int? likesReceived,
    double? campaignScore,
    double? effectiveScore,
    String? status,
    bool? isFollowing,
    List<LinkModel>? links,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      bio: bio ?? this.bio,
      gender: gender ?? this.gender,
      role: role ?? this.role,
      isApproved: isApproved ?? this.isApproved,
      isBlocked: isBlocked ?? this.isBlocked,
      baseScore: baseScore ?? this.baseScore,
      cachedScore: cachedScore ?? this.cachedScore,
      lifetimeLikesGiven: lifetimeLikesGiven ?? this.lifetimeLikesGiven,
      lastScoreUpdatedAt: lastScoreUpdatedAt ?? this.lastScoreUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      resetRequested: resetRequested ?? this.resetRequested,
      activeLinkLimit: activeLinkLimit ?? this.activeLinkLimit,
      appname: appname ?? this.appname,
      globalAdmin: globalAdmin ?? this.globalAdmin,
      allowedNamespaces: allowedNamespaces ?? this.allowedNamespaces,
      autolike: autolike ?? this.autolike,
      subscriptionStartedAt: subscriptionStartedAt ?? this.subscriptionStartedAt,
      isFreeSubscription: isFreeSubscription ?? this.isFreeSubscription,
      subscriptionToggledBy: subscriptionToggledBy ?? this.subscriptionToggledBy,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      resetPassword: resetPassword ?? this.resetPassword,
      campaignsCompleted: campaignsCompleted ?? this.campaignsCompleted,
      currentCampaignLikesGiven: currentCampaignLikesGiven ?? this.currentCampaignLikesGiven,
      currentCampaignTotalLinks: currentCampaignTotalLinks ?? this.currentCampaignTotalLinks,
      feedLikesGivenInCycle: feedLikesGivenInCycle ?? this.feedLikesGivenInCycle,
      campaignCycleUnlocked: campaignCycleUnlocked ?? this.campaignCycleUnlocked,
      campaignCycleCompletedAt: campaignCycleCompletedAt ?? this.campaignCycleCompletedAt,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      linkCount: linkCount ?? this.linkCount,
      campaignLinkCount: campaignLinkCount ?? this.campaignLinkCount,
      likesReceived: likesReceived ?? this.likesReceived,
      campaignScore: campaignScore ?? this.campaignScore,
      effectiveScore: effectiveScore ?? this.effectiveScore,
      status: status ?? this.status,
      isFollowing: isFollowing ?? this.isFollowing,
      links: links ?? this.links,
    );
  }
}
