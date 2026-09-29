import 'package:intl/intl.dart';

class LinkModel {
  final String? id;
  final String? userId;
  final String? username;
  final String? userPhoto;
  String? title;
  String? url;
  String? description;
  String? tags;
  final DateTime? publishedDate;
  int likesCount;
  int commentCount;
  int viewCount;
  bool isLiked;
  String? status;

  String? _formattedPublishedDate;
  String? _formattedDateOnly;

  String get formattedPublishedDate {
    if (_formattedPublishedDate != null) return _formattedPublishedDate!;
    final date = publishedDate ?? DateTime.now();
    _formattedPublishedDate = DateFormat('dd MMM yyyy, hh:mm a').format(date);
    return _formattedPublishedDate!;
  }

  String get formattedDateOnly {
    if (_formattedDateOnly != null) return _formattedDateOnly!;
    final date = publishedDate ?? DateTime.now();
    _formattedDateOnly = DateFormat('dd MMM yyyy').format(date);
    return _formattedDateOnly!;
  }

  LinkModel({
    this.id,
    this.userId,
    this.username,
    this.userPhoto,
    this.title,
    this.url,
    this.description,
    this.tags,
    this.publishedDate,
    this.likesCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.isLiked = false,
    this.status,
  });

  factory LinkModel.fromJson(Map<String, dynamic> json) {
    return LinkModel(
      id: json['id']?.toString(),
      userId: json['user_id']?.toString(),
      username: json['username'] as String?,
      userPhoto: json['user_photo'] as String?,
      title: json['title'] as String?,
      url: json['url'] as String?,
      description: json['description'] as String?,
      tags: json['tags'] as String?,
      publishedDate: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : (json['published_date'] != null
              ? DateTime.tryParse(json['published_date'].toString())
              : null),
      likesCount: (json['like_count'] as int?) ?? 0,
      commentCount: (json['comment_count'] as int?) ?? 0,
      viewCount: (json['view_count'] as int?) ?? 0,
      isLiked: (json['is_liked'] as bool?) ?? false,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'username': username,
        'user_photo': userPhoto,
        'title': title,
        'url': url,
        'description': description,
        'tags': tags,
        'created_at': publishedDate?.toIso8601String(),
        'like_count': likesCount,
        'comment_count': commentCount,
        'view_count': viewCount,
        'is_liked': isLiked,
        'status': status,
      };

  LinkModel copyWith({
    String? id,
    String? userId,
    String? username,
    String? userPhoto,
    String? title,
    String? url,
    String? description,
    String? tags,
    DateTime? publishedDate,
    int? likesCount,
    int? commentCount,
    int? viewCount,
    bool? isLiked,
    String? status,
  }) {
    return LinkModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userPhoto: userPhoto ?? this.userPhoto,
      title: title ?? this.title,
      url: url ?? this.url,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      publishedDate: publishedDate ?? this.publishedDate,
      likesCount: likesCount ?? this.likesCount,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      isLiked: isLiked ?? this.isLiked,
      status: status ?? this.status,
    );
  }
}
