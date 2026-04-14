class CategoryModel {
  final int id;
  final String userId;
  final String name;
  final String? icon;
  final String type; // income, expense, task
  final String? color;

  CategoryModel({
    required this.id,
    required this.userId,
    required this.name,
    this.icon,
    required this.type,
    this.color,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'],
      userId: json['user_id'], // Standard naming convention in Supabase
      name: json['name'],
      icon: json['icon'],
      type: json['type'],
      color: json['color'],
    );
  }
  

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'name': name,
    'icon': icon,
    'type': type,
    'color': color,
  };
  
}
