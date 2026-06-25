import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../app/app_state.dart';
import '../app/providers.dart';
import '../models/app_models.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_title.dart';
import 'auction_editor_screen.dart';
import 'publication_detail_screen.dart';

class AuctionsScreen extends ConsumerStatefulWidget {
  final AppState appState;
  const AuctionsScreen({super.key, required this.appState});

  @override
  ConsumerState<AuctionsScreen> createState() => _AuctionsScreenState();
}

class _AuctionsScreenState extends ConsumerState<AuctionsScreen> {
  final searchController = TextEditingController();
  String filter = 'active';
  bool refreshingMeta = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshFromMetaSilently();
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> createAuction() async {
    final page = await ref.read(selectedPageProvider.future);
    if (page == null || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AuctionEditorScreen(appState: widget.appState, page: page),
      ),
    );
    if (created == true) ref.invalidate(publicationsProvider);
  }

  Future<void> refreshFromMetaSilently() async {
    if (refreshingMeta) return;
    setState(() => refreshingMeta = true);
    try {
      await ref.read(repositoryProvider).refreshPublicationsFromMeta();
      if (mounted) ref.invalidate(publicationsProvider);
    } catch (_) {
      // La lista local ya se muestra; Meta puede tardar o rate-limitar.
    } finally {
      if (mounted) setState(() => refreshingMeta = false);
    }
  }

  Future<void> retryPublication(AuctionPublication publication) async {
    try {
      await ref.read(repositoryProvider).retryMetaPublication(publication.id);
      ref.invalidate(publicationsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo reintentar: $error')),
        );
      }
    }
  }

  Future<void> deleteFromFacebook(AuctionPublication publication) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar también de Facebook'),
        content: const Text(
          'Esta acción eliminará la publicación de la página. El historial local se conservará archivado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(repositoryProvider).deleteFromFacebook(publication.id);
    await ref.read(repositoryProvider).archivePublication(publication.id);
    ref.invalidate(publicationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final publications = ref.watch(publicationsProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await refreshFromMetaSilently();
          ref.invalidate(publicationsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SectionTitle(
              title: 'Publicaciones',
              subtitle: refreshingMeta
                  ? 'Actualizando comentarios y pujas...'
                  : 'Subastas activas, programadas y finalizadas.',
              trailing: IconButton.filled(
                onPressed: createAuction,
                icon: const Icon(Icons.add),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar publicaciones...',
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    {
                          'all': 'Todas',
                          'scheduled': 'Programadas',
                          'active': 'Activas',
                          'ended': 'Finalizadas',
                          'review': 'Revisión',
                          'failed': 'Con error',
                          'archived': 'Archivadas',
                        }.entries
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(entry.value),
                              selected: filter == entry.key,
                              onSelected: (_) =>
                                  setState(() => filter = entry.key),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
            const SizedBox(height: 14),
            publications.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off,
                title: 'No se pudieron cargar',
                description: error.toString(),
                action: FilledButton(
                  onPressed: () => ref.invalidate(publicationsProvider),
                  child: const Text('Reintentar'),
                ),
              ),
              data: (all) {
                final term = searchController.text.trim().toLowerCase();
                final items = all
                    .where(
                      (item) =>
                          (filter == 'all' || item.status.name == filter) &&
                          (term.isEmpty ||
                              item.title.toLowerCase().contains(term) ||
                              item.body.toLowerCase().contains(term)),
                    )
                    .toList();
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.photo_library_outlined,
                    title: 'Sin publicaciones',
                    description: filter == 'all'
                        ? 'Crea tu primera subasta desde la cámara.'
                        : 'No hay subastas con este filtro.',
                    action: FilledButton.icon(
                      onPressed: createAuction,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Crear subasta'),
                    ),
                  );
                }
                return Column(
                  children: items
                      .map(
                        (publication) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PublicationCard(
                            publication: publication,
                            onOpen: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PublicationDetailScreen(
                                  publicationId: publication.id,
                                ),
                              ),
                            ),
                            onArchive: () async {
                              await ref
                                  .read(repositoryProvider)
                                  .archivePublication(publication.id);
                              ref.invalidate(publicationsProvider);
                            },
                            onRetry: () => retryPublication(publication),
                            onDelete: () => deleteFromFacebook(publication),
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
}

class _PublicationCard extends ConsumerWidget {
  final AuctionPublication publication;
  final VoidCallback onOpen;
  final VoidCallback onArchive;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  const _PublicationCard({
    required this.publication,
    required this.onOpen,
    required this.onArchive,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = DateFormat('d MMM ? h:mm a', 'es');
    return AppCard(
      onTap: onOpen,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (publication.coverPath != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: FutureBuilder<String>(
                future: ref
                    .read(repositoryProvider)
                    .signedImageUrl(publication.coverPath!),
                builder: (context, snapshot) => snapshot.hasData
                    ? CachedNetworkImage(
                        imageUrl: snapshot.data!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        height: 180,
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        publication.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _StatusBadge(status: publication.status),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'archive') onArchive();
                        if (value == 'retry') onRetry();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        if (publication.status == PublicationStatus.failed)
                          const PopupMenuItem(
                            value: 'retry',
                            child: ListTile(
                              leading: Icon(Icons.refresh),
                              title: Text('Reintentar publicación'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'archive',
                          child: ListTile(
                            leading: Icon(Icons.archive_outlined),
                            title: Text('Archivar'),
                          ),
                        ),
                        if (publication.metaPostId != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_forever_outlined),
                              title: Text('Eliminar de Facebook'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Inicia ${formatter.format(publication.startsAt)}'),
                Text('Termina ${formatter.format(publication.endsAt)}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.gavel, size: 18),
                    const SizedBox(width: 6),
                    Text('${publication.items.length} artículos'),
                    const Spacer(),
                    Text(
                      '\$${publication.total}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                if (publication.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    publication.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final PublicationStatus status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final labels = {
      'draft': 'Borrador',
      'scheduled': 'Programada',
      'publishing': 'Publicando',
      'active': 'Activa',
      'ended': 'Finalizada',
      'review': 'Revisión',
      'failed': 'Error',
      'archived': 'Archivada',
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(labels[status.name] ?? status.name),
    );
  }
}
