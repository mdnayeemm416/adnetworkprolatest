// Models for Adsterra Publisher Tools API (api3.adsterratools.com)

class AdsterraPlacementModel {
  final int id;
  final String name;
  final int? domainId;
  final String? domainName;
  final String type;
  final String status;
  final String? directUrl;

  AdsterraPlacementModel({
    required this.id,
    required this.name,
    this.domainId,
    this.domainName,
    required this.type,
    required this.status,
    this.directUrl,
  });

  factory AdsterraPlacementModel.fromJson(Map<String, dynamic> json) {
    final titleVal = json['title'] as String?;
    final aliasVal = json['alias'] as String?;
    final nameVal = json['name'] as String? ?? titleVal ?? aliasVal ?? 'Placement #${json['id']}';

    // direct_url might be directly under 'direct_url', or extracted from 'code'
    String? url = json['direct_url'] as String?;
    if (url == null && json['code'] != null) {
      final codeStr = json['code'].toString();
      final match = RegExp(r'https?://[^\s"<>]+').firstMatch(codeStr);
      if (match != null) {
        url = match.group(0);
      }
    }

    return AdsterraPlacementModel(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: nameVal,
      domainId: json['domain_id'] is int
          ? json['domain_id'] as int
          : int.tryParse(json['domain_id']?.toString() ?? ''),
      domainName: json['domain_name'] as String?,
      type: json['type'] as String? ?? json['ad_unit_type'] as String? ?? 'Direct Link',
      status: json['status'] as String? ?? 'approved',
      directUrl: url,
    );
  }
}

class AdsterraBalanceModel {
  final double balance;
  final String currency;

  AdsterraBalanceModel({
    required this.balance,
    this.currency = 'USD',
  });

  factory AdsterraBalanceModel.fromJson(Map<String, dynamic> json) {
    double b = 0.0;
    if (json['balance'] != null) {
      b = double.tryParse(json['balance'].toString()) ?? 0.0;
    }
    return AdsterraBalanceModel(
      balance: b,
      currency: json['currency']?.toString() ?? 'USD',
    );
  }
}

class AdsterraStatItem {
  final String? date;
  final int impressions;
  final int clicks;
  final double ctr;
  final double cpm;
  final double revenue;

  AdsterraStatItem({
    this.date,
    this.impressions = 0,
    this.clicks = 0,
    this.ctr = 0.0,
    this.cpm = 0.0,
    this.revenue = 0.0,
  });

  int get day {
    if (date == null) return 1;
    try {
      return DateTime.parse(date!).day;
    } catch (_) {
      return 1;
    }
  }

  factory AdsterraStatItem.fromJson(Map<String, dynamic> json) {
    return AdsterraStatItem(
      date: json['date'] as String?,
      impressions: int.tryParse((json['impression'] ?? json['impressions'])?.toString() ?? '0') ?? 0,
      clicks: int.tryParse(json['clicks']?.toString() ?? '0') ?? 0,
      ctr: double.tryParse(json['ctr']?.toString() ?? '0.0') ?? 0.0,
      cpm: double.tryParse(json['cpm']?.toString() ?? '0.0') ?? 0.0,
      revenue: double.tryParse(json['revenue']?.toString() ?? '0.0') ?? 0.0,
    );
  }
}
