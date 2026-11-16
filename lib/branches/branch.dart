import 'package:flutter/foundation.dart';

/// A branch of the credit union, as offered in branch pickers.
///
/// The backend's branch list sends each branch's id and name (owner
/// decision 16 November 2026). [location] is read if the backend ever sends
/// it, and is otherwise null.
@immutable
class Branch {
  const Branch({required this.id, required this.name, this.location});

  final String id;
  final String name;
  final String? location;

  /// How the branch is shown in a picker.
  String get label => location == null ? name : '$name · $location';

  static Branch? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final name = json['name'];
    final location = json['location'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return Branch(
      id: id,
      name: name,
      location: location is String && location.isNotEmpty ? location : null,
    );
  }

  @override
  bool operator ==(Object other) => other is Branch && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
