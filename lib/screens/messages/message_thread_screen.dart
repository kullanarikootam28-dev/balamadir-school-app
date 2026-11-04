import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/message.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Direct chat thread between the current user and [peerId], with realtime
/// updates via Postgres Changes. Used by both the teacher's Messaging Portal
/// and the student's reply view — a conversation is just the pair of ids.
class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({super.key, required this.peerId, required this.peerName});

  final String peerId;
  final String peerName;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final _bodyCtrl = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  String get _myId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    _bodyCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('messages')
          .select()
          .or('and(sender_id.eq.$_myId,recipient_id.eq.${widget.peerId}),'
              'and(sender_id.eq.${widget.peerId},recipient_id.eq.$_myId)')
          .order('created_at');
      // Deleted messages stay in the thread as a placeholder (not filtered
      // out here) — that placeholder is the "notify the other participant"
      // behaviour confirmed for message deletion.
      setState(() {
        _messages = (data as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribe() {
    _channel = supabase
        .channel('messages:${widget.peerId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final msg = ChatMessage.fromJson(payload.newRecord);
            final isThisThread = (msg.senderId == _myId && msg.recipientId == widget.peerId) ||
                (msg.senderId == widget.peerId && msg.recipientId == _myId);
            if (isThisThread && mounted && !_messages.any((m) => m.id == msg.id)) {
              setState(() => _messages.add(msg));
              _scrollToEnd();
            }
          },
        )
        .onPostgresChanges(
          // Catches soft-deletes (deleted_at set) so the other participant
          // sees the "removed" placeholder live, without reloading.
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final msg = ChatMessage.fromJson(payload.newRecord);
            final index = _messages.indexWhere((m) => m.id == msg.id);
            if (index != -1 && mounted) {
              setState(() => _messages[index] = msg);
            }
          },
        )
        .subscribe();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _bodyCtrl.text.trim();
    if (text.isEmpty) return;
    _bodyCtrl.clear();
    try {
      final inserted = await supabase
          .from('messages')
          .insert({
            'sender_id': _myId,
            'recipient_id': widget.peerId,
            'body': text,
          })
          .select()
          .single();
      // Append immediately rather than waiting on the realtime echo, which
      // can lag noticeably behind the insert completing.
      final msg = ChatMessage.fromJson(inserted);
      if (mounted && !_messages.any((m) => m.id == msg.id)) {
        setState(() => _messages.add(msg));
        _scrollToEnd();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _confirmDelete(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this message?'),
        content: Text(
            'This deletes it for everyone in this conversation — ${widget.peerName} will see it was removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete for everyone'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await supabase.from('messages').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': _myId,
      }).eq('id', message.id);
      await AuditService.log(module: 'messages', action: 'delete', oldValue: {'id': message.id});
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1 && mounted) {
        setState(() {
          _messages[index] = ChatMessage(
            id: message.id,
            senderId: message.senderId,
            recipientId: message.recipientId,
            body: message.body,
            createdAt: message.createdAt,
            readAt: message.readAt,
            deletedAt: DateTime.now(),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet — say hello!'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final isMine = m.senderId == _myId;
                          final isDeleted = m.isDeleted;
                          return GestureDetector(
                            onLongPress: (isMine && !isDeleted)
                                ? () => _confirmDelete(m)
                                : null,
                            child: Align(
                              alignment: isMine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width * 0.75),
                                decoration: BoxDecoration(
                                  color: isDeleted
                                      ? theme.colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.5)
                                      : (isMine
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.surfaceContainerHighest),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isDeleted ? 'This message was removed' : m.body,
                                      style: TextStyle(
                                        fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                                        color: isDeleted
                                            ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                                            : (isMine
                                                ? theme.colorScheme.onPrimary
                                                : theme.colorScheme.onSurface),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat.jm().format(m.createdAt),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: (isDeleted
                                                ? theme.colorScheme.onSurface
                                                : (isMine
                                                    ? theme.colorScheme.onPrimary
                                                    : theme.colorScheme.onSurface))
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bodyCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Type a message…',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(24))),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
