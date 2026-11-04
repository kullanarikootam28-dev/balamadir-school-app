import 'package:equatable/equatable.dart';

class Announcement extends Equatable {
  const Announcement({
    required this.id,
    required this.authorId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.classId,
    this.authorName,
    this.mediaUrl,
  });

  final String id;
  final String authorId;
  final String? authorName;
  final String? classId; // null = school-wide broadcast
  final String title;
  final String body;
  final DateTime createdAt;
  final String? mediaUrl;

  bool get isGlobal => classId == null;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        id: json['id'] as String,
        authorId: json['author_id'] as String,
        authorName:
            (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
        classId: json['class_id'] as String?,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        mediaUrl: json['media_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'author_id': authorId,
        'class_id': classId,
        'title': title,
        'body': body,
        'media_url': mediaUrl,
      };

  @override
  List<Object?> get props => [id, authorId, classId, title, body, createdAt];
}
