import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/services/broadcast_media_service.dart';

class _Slide {
  const _Slide({required this.title, required this.imageUrl, required this.isGlobal});
  final String title;
  final String imageUrl;
  final bool isGlobal;
}

/// Photos posted with the school's notices, shown as a slideshow at the top
/// of the student dashboard. A picture stays here for as long as its notice
/// is live — when an admin or teacher deletes the notice, it disappears from
/// here too (deleted notices are filtered out).
///
/// It's an ordinary part of the page, not a pinned banner, so it scrolls
/// away with everything else.
class AnnouncementSlideshow extends ConsumerStatefulWidget {
  const AnnouncementSlideshow({super.key});

  @override
  ConsumerState<AnnouncementSlideshow> createState() => _AnnouncementSlideshowState();
}

class _AnnouncementSlideshowState extends ConsumerState<AnnouncementSlideshow> {
  static const _slideDuration = Duration(seconds: 5);

  final _controller = PageController();
  Timer? _timer;
  List<_Slide> _slides = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final studentId = ref.viewedStudentId;
      final enrollment = await supabase
          .from('class_students')
          .select('class_id')
          .eq('student_id', studentId)
          .maybeSingle();
      final classId = enrollment?['class_id'] as String?;

      final base = supabase
          .from('announcements')
          .select('title, media_url, class_id, created_at')
          .not('media_url', 'is', null)
          .isFilter('deleted_at', null);
      final rows = await (classId == null
              ? base.isFilter('class_id', null)
              : base.or('class_id.eq.$classId,class_id.is.null'))
          .order('created_at', ascending: false)
          .limit(20);

      final slides = [
        for (final row in rows)
          if (BroadcastMediaService.isImage(row['media_url'] as String))
            _Slide(
              title: row['title'] as String,
              imageUrl: row['media_url'] as String,
              isGlobal: row['class_id'] == null,
            ),
      ];
      if (!mounted) return;
      setState(() => _slides = slides);
      if (slides.length > 1) {
        _timer = Timer.periodic(_slideDuration, (_) {
          if (!mounted || !_controller.hasClients) return;
          _controller.animateToPage(
            (_index + 1) % _slides.length,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        });
      }
    } catch (_) {
      // The dashboard shouldn't show an error strip for a decorative
      // element — with no pictures it simply takes up no space.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(viewedStudentIdProvider, (_, __) => _load());
    if (_slides.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 190,
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final slide = _slides[i];
                  return GestureDetector(
                    onTap: () => context.push('/student/alerts'),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: slide.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(child: Icon(Icons.image_not_supported_outlined)),
                          ),
                        ),
                        // Keeps the title readable over any photo.
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.center,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                slide.isGlobal ? 'School-wide notice' : 'Class notice',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                              Text(
                                slide.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (_slides.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
