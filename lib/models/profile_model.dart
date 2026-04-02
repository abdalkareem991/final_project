class ProfileModel {
  final String id;
  final String fullName;
  final double totalNetWorth;
  final String? phone;

  ProfileModel({
    required this.id,
    required this.fullName,
    required this.totalNetWorth,
    this.phone,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'],
      fullName: json['full_name'] ?? '',
      totalNetWorth: (json['total_net_worth'] ?? 0).toDouble(),
      phone: json['phone'],
    );
  }
}
