import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../app/providers.dart';
import '../models/app_models.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';

class PublicationDetailScreen extends ConsumerStatefulWidget {
  final String publicationId;
  const PublicationDetailScreen({super.key, required this.publicationId});

  @override
  ConsumerState<PublicationDetailScreen> createState() =>
      _PublicationDetailScreenState();
}

class _PublicationDetailScreenState
    extends ConsumerState<PublicationDetailScreen> {
  late Future<AuctionPublication> future;
  bool reminding = false;
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    future = ref.read(repositoryProvider).getPublication(widget.publicationId);
  }

  void reload() {
    setState(() {
      future = ref
          .read(repositoryProvider)
          .getPublication(widget.publicationId);
    });
  }

  Future<void> syncBids() async {
    if (syncing) return;
    setState(() => syncing = true);
    try {
      await ref
          .read(repositoryProvider)
          .refreshPublicationFromMeta(widget.publicationId);
      reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pujas actualizadas desde Facebook.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron actualizar pujas: $error')),
      );
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> remind(AuctionPublication publication) async {
    final alreadySent = publication.items.any((item) => item.reminderCount > 0);
    if (alreadySent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reenviar recordatorio'),
          content: const Text(
            'Esta subasta ya tiene recordatorios enviados. ¿Quieres enviar otro comentario en cada artículo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reenviar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => reminding = true);
    try {
      await ref
          .read(repositoryProvider)
          .remindAuction(publication.id, force: alreadySent);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Recordatorios enviados.')));
      reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo recordar: $error')));
    } finally {
      if (mounted) setState(() => reminding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de subasta'),
        actions: [
          IconButton(
            tooltip: 'Actualizar pujas',
            onPressed: syncing ? null : syncBids,
            icon: syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: FutureBuilder<AuctionPublication>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final publication = snapshot.data!;
          final format = DateFormat('d MMMM y · h:mm a', 'es');
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            publication.title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Chip(label: Text(_statusLabel(publication.status))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Inicio: ${format.format(publication.startsAt)}'),
                    Text('Fin: ${format.format(publication.endsAt)}'),
                    const SizedBox(height: 8),
                    Text(
                      'Puja inicial: \$${publication.startingBid} · Puja mínima: \$${publication.bidIncrement}',
                    ),
                    const Divider(height: 28),
                    Text(
                      'Acumulado: \$${publication.total}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (publication.metaPostId != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: reminding
                                ? null
                                : () => remind(publication),
                            icon: reminding
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.notification_add_outlined),
                            label: Text(
                              publication.items.any(
                                    (item) => item.reminderCount > 0,
                                  )
                                  ? 'Reenviar recordatorio'
                                  : 'Recordar terminación',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                'https://www.facebook.com/${publication.metaPostId}',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Abrir en Facebook'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Artículos',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (publication.items.isEmpty)
                const EmptyState(
                  icon: Icons.photo_outlined,
                  title: 'Sin artículos',
                  description: 'Las fotografías todavía no se han procesado.',
                )
              else
                ...publication.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ItemCard(item: item),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _statusLabel(PublicationStatus status) => switch (status) {
    PublicationStatus.draft => 'Borrador',
    PublicationStatus.scheduled => 'Programada',
    PublicationStatus.publishing => 'Publicando',
    PublicationStatus.active => 'Activa',
    PublicationStatus.ended => 'Finalizada',
    PublicationStatus.review => 'Revisión',
    PublicationStatus.failed => 'Error',
    PublicationStatus.archived => 'Archivada',
  };
}

class _ItemCard extends ConsumerWidget {
  final AuctionItem item;
  const _ItemCard({required this.item});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AppCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: FutureBuilder<String>(
            future: ref
                .read(repositoryProvider)
                .signedImageUrl(item.storagePath),
            builder: (context, snapshot) => snapshot.hasData
                ? CachedNetworkImage(
                    imageUrl: snapshot.data!,
                    width: 92,
                    height: 112,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 92,
                    height: 112,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Artículo ${item.position + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              if (item.winningAmount != null) ...[
                Text(
                  item.resolutionStatus == 'winner'
                      ? 'Puja ganadora'
                      : 'Puja más alta',
                ),
                Text(
                  '\$${item.winningAmount}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(item.winningAuthor ?? 'Usuario de Facebook'),
              ] else
                Text(
                  item.resolutionStatus == 'review'
                      ? 'Requiere revisión'
                      : item.resolutionStatus == 'no_bids'
                      ? 'Sin pujas'
                      : 'Subasta abierta',
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
