import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_title.dart';
import 'chat_order_editor_screen.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  late Future<List<Map<String, dynamic>>> future;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<List<Map<String, dynamic>>> load({bool sync = false}) async {
    if (sync) {
      await ref.read(repositoryProvider).syncMessagesFromMeta();
    }
    return ref.read(repositoryProvider).getConversations();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void refresh({bool sync = false}) =>
      setState(() => future = load(sync: sync));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: RefreshIndicator(
      onRefresh: () async {
        await ref.read(repositoryProvider).syncMessagesFromMeta();
        refresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionTitle(
            title: 'Mensajes',
            subtitle: 'Inbox básico de la página y respuestas rápidas.',
            trailing: IconButton.filled(
              onPressed: () => refresh(sync: true),
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar cliente o mensaje...',
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Cargando mensajes, espera un momento...'),
                      ],
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.cloud_off,
                  title: 'No se pudieron cargar mensajes',
                  description: snapshot.error.toString(),
                  action: FilledButton(
                    onPressed: refresh,
                    child: const Text('Reintentar'),
                  ),
                );
              }
              final term = search.text.trim().toLowerCase();
              final conversations = (snapshot.data ?? []).where((row) {
                final customer = row['customers'] as Map<String, dynamic>?;
                final name = (customer?['display_name'] as String? ?? '')
                    .toLowerCase();
                final psid = (row['messenger_psid'] as String? ?? '')
                    .toLowerCase();
                return term.isEmpty ||
                    name.contains(term) ||
                    psid.contains(term);
              }).toList();
              if (conversations.isEmpty) {
                return const AppCard(
                  child: EmptyState(
                    icon: Icons.mark_chat_unread_outlined,
                    title: 'Sin conversaciones todav?a',
                    description:
                        'Cuando alguien escriba a la página, aparecerá aquí. Si envía un código de subasta, se vinculará automáticamente.',
                  ),
                );
              }
              return Column(
                children: conversations
                    .map(
                      (conversation) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ConversationCard(
                          conversation: conversation,
                          onTap: () async {
                            final customer =
                                conversation['customers']
                                    as Map<String, dynamic>?;
                            final title =
                                customer?['display_name'] as String? ??
                                'Cliente de Messenger';
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ConversationScreen(
                                  conversationId: conversation['id'] as String,
                                  title: title,
                                ),
                              ),
                            );
                            refresh();
                          },
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _ConversationCard extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onTap;

  const _ConversationCard({required this.conversation, required this.onTap});

  String _latestMessagePreview(Map<String, dynamic> message) {
    final body = message['body'] as String? ?? 'Adjunto';
    final prefix = message['direction'] == 'outgoing' ? 'Tú: ' : '';
    return '$prefix$body';
  }

  @override
  Widget build(BuildContext context) {
    final customer = conversation['customers'] as Map<String, dynamic>?;
    final title =
        customer?['display_name'] as String? ?? 'Cliente de Messenger';
    final unread = conversation['unread_count'] as int? ?? 0;
    final canMessageUntil = conversation['can_message_until'] == null
        ? null
        : DateTime.parse(conversation['can_message_until'] as String).toLocal();
    final lastMessageAt = conversation['last_message_at'] == null
        ? null
        : DateTime.parse(conversation['last_message_at'] as String).toLocal();
    final openWindow =
        canMessageUntil != null && canMessageUntil.isAfter(DateTime.now());
    final formatter = DateFormat('d MMM ? h:mm a', 'es');
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: customer?['picture_url'] == null
                ? null
                : NetworkImage(customer!['picture_url'] as String),
            child: customer?['picture_url'] == null
                ? const Icon(Icons.person_outline)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (unread > 0)
                      Badge(label: Text(unread > 99 ? '99+' : '$unread')),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  openWindow
                      ? 'Puedes responder por Messenger'
                      : 'Ventana de Messenger cerrada',
                  style: TextStyle(
                    color: openWindow
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                if (lastMessageAt != null) ...[
                  const SizedBox(height: 4),
                  Text('?ltimo mensaje: ${formatter.format(lastMessageAt)}'),
                ],
                if (conversation['latest_message'] is Map<String, dynamic>) ...[
                  const SizedBox(height: 4),
                  Text(
                    _latestMessagePreview(
                      conversation['latest_message'] as Map<String, dynamic>,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class ConversationScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String title;

  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  late Future<List<Map<String, dynamic>>> future;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<List<Map<String, dynamic>>> load() =>
      ref.read(repositoryProvider).getMessages(widget.conversationId);

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (controller.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await ref
          .read(repositoryProvider)
          .sendMessage(widget.conversationId, controller.text);
      controller.clear();
      setState(() => future = load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo enviar: $error')));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> markRead() async {
    await ref
        .read(repositoryProvider)
        .markConversationRead(widget.conversationId);
  }

  Future<void> createOrder() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatOrderEditorScreen(
          conversationId: widget.conversationId,
          title: widget.title,
        ),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido creado desde el chat.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'Crear pedido',
          onPressed: createOrder,
          icon: const Icon(Icons.add_shopping_cart),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              markRead();
              if (snapshot.data!.isEmpty) {
                return const Center(
                  child: EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Sin mensajes',
                    description:
                        'La conversación aparecerá aquí al recibir o enviar mensajes.',
                  ),
                );
              }
              scrollToBottom();
              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final message = snapshot.data![index];
                  final outgoing = message['direction'] == 'outgoing';
                  return Align(
                    alignment: outgoing
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      constraints: const BoxConstraints(maxWidth: 320),
                      decoration: BoxDecoration(
                        color: outgoing
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(message['body'] as String? ?? 'Adjunto'),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sending ? null : send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
