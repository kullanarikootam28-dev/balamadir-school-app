import 'package:flutter/material.dart';

import 'package:school_management_app/services/attachment_download_service.dart';
import 'package:school_management_app/services/broadcast_media_service.dart';

/// A notice's attachment, as shown on the student Alerts dashboard, the
/// teacher noticeboard and admin broadcasts: images preview inline, videos
/// and documents show as a file card — and every kind gets Open and
/// Download. The file itself lives in Cloudflare R2.
class MediaAttachmentPreview extends StatelessWidget {
  const MediaAttachmentPreview({super.key, required this.url});

  final String url;

  IconData get _icon {
    final name = BroadcastMediaService.fileNameFor(url).toLowerCase();
    if (BroadcastMediaService.isVideo(url)) return Icons.play_circle_outline;
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.doc') || name.endsWith('.docx') || name.endsWith('.txt')) {
      return Icons.description_outlined;
    }
    if (name.endsWith('.xls') || name.endsWith('.xlsx') || name.endsWith('.csv')) {
      return Icons.table_chart_outlined;
    }
    if (name.endsWith('.ppt') || name.endsWith('.pptx')) return Icons.slideshow_outlined;
    if (name.endsWith('.mp3') || name.endsWith('.m4a')) return Icons.audiotrack_outlined;
    if (name.endsWith('.zip')) return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final fileName = BroadcastMediaService.fileNameFor(url);
    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          icon: Icon(BroadcastMediaService.isVideo(url) ? Icons.play_arrow : Icons.open_in_new,
              size: 18),
          label: Text(BroadcastMediaService.isVideo(url) ? 'Play' : 'Open'),
          onPressed: () => AttachmentDownloadService.open(url),
        ),
        const SizedBox(width: 4),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Download'),
          onPressed: () => AttachmentDownloadService.download(context, url),
        ),
      ],
    );

    if (BroadcastMediaService.isImage(url)) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: () => AttachmentDownloadService.open(url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  height: 180,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 60,
                    child: Center(child: Text('Preview unavailable — use Download')),
                  ),
                ),
              ),
            ),
            actions,
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(_icon, size: 32),
              title: Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(BroadcastMediaService.isVideo(url) ? 'Video' : 'Attached file'),
            ),
            actions,
          ],
        ),
      ),
    );
  }
}
