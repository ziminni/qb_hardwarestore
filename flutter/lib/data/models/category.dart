class Category {
  const Category({
    required this.id,
    required this.name,
    required this.description,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String description;
  final bool isActive;

  Category copyWith({String? name, String? description, bool? isActive}) {
    return Category(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
    );
  }
}
