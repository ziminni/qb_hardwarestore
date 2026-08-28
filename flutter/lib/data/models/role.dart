class Role {
  const Role({
    required this.id,
    required this.name,
    required this.displayName,
    this.permissions = const [],
  });

  final int id;
  final String name;
  final String displayName;
  final List<int> permissions;

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'] as int,
      name: json['name'] as String,
      displayName: json['display_name'] as String? ?? json['name'] as String,
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .map((permission) => permission as int)
          .toList(growable: false),
    );
  }
}
