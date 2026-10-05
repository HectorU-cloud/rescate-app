class User {
  final int id;
  final String name;
  final String email;
  final bool isBusiness;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.isBusiness,
  });

  factory User.fromJson(
    Map<String, dynamic> json,
  ) {
    return User(
      id: (json['user_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      isBusiness:
          json['is_business'] as bool? ?? false,
    );
  }
}