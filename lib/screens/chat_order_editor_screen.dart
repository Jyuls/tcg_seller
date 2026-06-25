import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';

class ChatOrderEditorScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String title;

  const ChatOrderEditorScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  @override
  ConsumerState<ChatOrderEditorScreen> createState() =>
      _ChatOrderEditorScreenState();
}

class _ChatOrderEditorScreenState extends ConsumerState<ChatOrderEditorScreen> {
  static const stepTitles = ['Origen', 'Entrega', 'Resumen'];

  final description = TextEditingController(text: 'Pedido desde chat');
  final price = TextEditingController();
  final fixedBooth = TextEditingController();
  final booth = TextEditingController();
  final helpText = TextEditingController();
  final notes = TextEditingController();

  int step = 0;
  bool saving = false;
  String mode = 'manual';
  File? image;
  List<Map<String, dynamic>> locations = const [];
  List<Map<String, dynamic>> claimable = const [];
  List<Map<String, dynamic>> selectedItems = [];
  final signedImageFutures = <String, Future<String>>{};
  String? locationId;
  String deliveryMode = 'general';
  int? zone;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final repo = ref.read(repositoryProvider);
    final loadedLocations = await repo.getDeliveryLocations();
    final loadedClaimable = await repo.getClaimableAuctionItems();
    if (!mounted) return;
    setState(() {
      locations = loadedLocations;
      claimable = loadedClaimable;
      if (locations.isNotEmpty) applyLocation(locations.first);
    });
  }

  @override
  void dispose() {
    description.dispose();
    price.dispose();
    fixedBooth.dispose();
    booth.dispose();
    helpText.dispose();
    notes.dispose();
    super.dispose();
  }

  void applyLocation(Map<String, dynamic> location) {
    locationId = location['id'] as String;
    deliveryMode = location['default_delivery_mode'] as String? ?? deliveryMode;
    fixedBooth.text =
        location['default_fixed_booth_name'] as String? ?? fixedBooth.text;
    helpText.text = location['location_help_text'] as String? ?? helpText.text;
    zone = location['default_zone'] as int?;
    booth.text = (location['default_booth_number'] as int?)?.toString() ?? '';
  }

  bool requiresBooth() {
    if (locationId == null) return false;
    final selected = locations.firstWhere(
      (location) => location['id'] == locationId,
      orElse: () => <String, dynamic>{},
    );
    return selected['requires_booth'] == true;
  }

  int get total => selectedItems.isNotEmpty
      ? selectedItems.fold<int>(
          0,
          (sum, item) => sum + (item['winning_amount'] as int? ?? 0),
        )
      : int.tryParse(price.text) ?? 0;

  Future<void> pickPhoto(ImageSource source) async {
    final selected = await ImagePicker().pickImage(
      source: source,
      imageQuality: 88,
    );
    if (selected == null) return;
    setState(() {
      mode = 'manual';
      selectedItems = [];
      image = File(selected.path);
    });
  }

  Future<void> chooseAuctionItems() async {
    final picked = await Navigator.of(context).push<List<Map<String, dynamic>>>(
      MaterialPageRoute(
        builder: (_) => _ClaimableAuctionPickerScreen(
          claimable: claimable,
          selectedItems: selectedItems,
          imageUrl: (path) => ref.read(repositoryProvider).signedImageUrl(path),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      mode = 'auction';
      image = null;
      selectedItems = picked;
      description.text = picked.length == 1
          ? 'Artículo de subasta'
          : '${picked.length} art?culos de subasta';
      price.text = total.toString();
    });
  }

  void toggleItem(Map<String, dynamic> item) {
    final id = item['id'] as String;
    setState(() {
      mode = 'auction';
      image = null;
      if (selectedItems.any((entry) => entry['id'] == id)) {
        selectedItems = selectedItems
            .where((entry) => entry['id'] != id)
            .toList();
      } else {
        selectedItems = [...selectedItems, item];
      }
      description.text = selectedItems.length == 1
          ? 'Artículo de subasta'
          : '${selectedItems.length} art?culos de subasta';
      price.text = total.toString();
    });
  }

  bool validateStep() {
    if (step == 0) {
      if (mode == 'auction' && selectedItems.isEmpty) {
        showError('Selecciona al menos un art?culo de subasta.');
        return false;
      }
      if (mode == 'manual' && description.text.trim().isEmpty) {
        showError('Agrega una descripción.');
        return false;
      }
      if (total <= 0) {
        showError('Agrega un precio v?lido.');
        return false;
      }
    }
    return true;
  }

  void showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void next() {
    if (!validateStep()) return;
    setState(() => step++);
  }

  Future<void> createOrder() async {
    if (!validateStep()) return;
    setState(() => saving = true);
    try {
      final repo = ref.read(repositoryProvider);
      final boothNumber = int.tryParse(booth.text);
      if (selectedItems.isNotEmpty) {
        await repo.createOrderFromClaimedAuctionItems(
          conversationId: widget.conversationId,
          items: selectedItems,
          deliveryLocationId: locationId,
          deliveryMode: deliveryMode,
          fixedBoothName: fixedBooth.text,
          deliveryZone: requiresBooth() ? zone : null,
          boothNumber: requiresBooth() ? boothNumber : null,
          locationHelpText: helpText.text,
          deliveryNotes: notes.text,
        );
      } else {
        await repo.createManualOrderFromConversation(
          conversationId: widget.conversationId,
          image: image,
          sourceLabel: description.text,
          price: total,
          deliveryLocationId: locationId,
          deliveryMode: deliveryMode,
          fixedBoothName: fixedBooth.text,
          deliveryZone: requiresBooth() ? zone : null,
          boothNumber: requiresBooth() ? boothNumber : null,
          locationHelpText: helpText.text,
          deliveryNotes: notes.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => saving = false);
        showError('No se pudo crear el pedido: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (saving) return _loading();
    return Scaffold(
      appBar: AppBar(title: Text(stepTitles[step])),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (step + 1) / stepTitles.length),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  Text('Paso ${step + 1} de ${stepTitles.length}'),
                  const Spacer(),
                  Text('Cliente: ${widget.title}'),
                ],
              ),
            ),
            Expanded(child: _step()),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  if (step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => step--),
                        child: const Text('Anterior'),
                      ),
                    ),
                  if (step > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: step == stepTitles.length - 1
                          ? createOrder
                          : next,
                      icon: Icon(
                        step == stepTitles.length - 1
                            ? Icons.check
                            : Icons.arrow_forward,
                      ),
                      label: Text(
                        step == stepTitles.length - 1
                            ? 'Crear pedido'
                            : 'Siguiente',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step() => switch (step) {
    0 => _originStep(),
    1 => _deliveryStep(),
    _ => _previewStep(),
  };

  Widget _page(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(18), children: children);

  Widget _originStep() => _page([
    const Text('Elige de d?nde saldr? el art?culo del pedido.'),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => pickPhoto(ImageSource.camera),
            icon: const Icon(Icons.photo_camera),
            label: const Text('Tomar foto'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => pickPhoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text('Galería'),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    if (image != null)
      AppCard(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(image!, height: 180, fit: BoxFit.cover),
        ),
      ),
    TextField(
      controller: description,
      decoration: const InputDecoration(labelText: 'Descripci?n'),
    ),
    const SizedBox(height: 10),
    TextField(
      controller: price,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Precio', prefixText: '\$'),
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: 10),
    SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: chooseAuctionItems,
        icon: const Icon(Icons.gavel),
        label: Text(
          selectedItems.isEmpty
              ? 'Elegir subasta'
              : 'Cambiar subasta (${selectedItems.length})',
        ),
      ),
    ),
    if (selectedItems.isNotEmpty) ...[
      const SizedBox(height: 16),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Art?culos seleccionados',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ...selectedItems.map((item) {
              final publication = item['publications'] as Map<String, dynamic>;
              final position = item['position'] as int? ?? 0;
              final amount = item['winning_amount'] as int? ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: FutureBuilder<String>(
                  future: signedImageFutures.putIfAbsent(
                    item['storage_path'] as String,
                    () => ref
                        .read(repositoryProvider)
                        .signedImageUrl(item['storage_path'] as String),
                  ),
                  builder: (context, snapshot) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: snapshot.hasData
                        ? Image.network(
                            snapshot.data!,
                            width: 58,
                            height: 58,
                            fit: BoxFit.cover,
                            cacheWidth: 120,
                          )
                        : const SizedBox(
                            width: 58,
                            height: 58,
                            child: Icon(Icons.image),
                          ),
                  ),
                ),
                title: Text(
                  '${publication['title'] ?? 'Subasta'} · Artículo ${position + 1}',
                ),
                subtitle: Text('\$$amount'),
              );
            }),
          ],
        ),
      ),
    ],
  ]);

  Widget _deliveryStep() => _page([
    const Text('Confirma el lugar de entrega para este pedido.'),
    const SizedBox(height: 16),
    AppCard(
      child: Column(
        children: [
          if (locations.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: locationId,
              decoration: const InputDecoration(labelText: 'Entrega'),
              items: locations
                  .map(
                    (location) => DropdownMenuItem(
                      value: location['id'] as String,
                      child: Text(location['name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                final selected = locations.firstWhere(
                  (location) => location['id'] == value,
                );
                applyLocation(selected);
              }),
            ),
          if (requiresBooth()) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: zone,
              decoration: const InputDecoration(labelText: 'Zona'),
              items: const [1, 2, 3]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text('Zona $value'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => zone = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: booth,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Puesto'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: fixedBooth,
            decoration: const InputDecoration(
              labelText: 'Puesto fijo / referencia',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: helpText,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'C?mo encontrar el lugar',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notas'),
          ),
        ],
      ),
    ),
  ]);

  Widget _previewStep() => _page([
    AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pedido para ${widget.title}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (selectedItems.isNotEmpty)
            ...selectedItems.map((item) {
              final publication = item['publications'] as Map<String, dynamic>;
              final position = item['position'] as int? ?? 0;
              final amount = item['winning_amount'] as int? ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.gavel),
                title: Text(
                  '${publication['title'] ?? 'Subasta'} · Artículo ${position + 1}',
                ),
                subtitle: Text('\$$amount'),
              );
            })
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.shopping_bag_outlined),
              title: Text(description.text),
              subtitle: Text('\$$total'),
            ),
          const Divider(),
          Text(
            'Total: \$$total',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Entrega: ${_deliverySummary()}'),
        ],
      ),
    ),
  ]);

  String _deliverySummary() {
    String? location;
    for (final entry in locations) {
      if (entry['id'] == locationId) {
        location = entry['name'] as String?;
        break;
      }
    }
    final parts = [
      ?location,
      if (fixedBooth.text.trim().isNotEmpty) fixedBooth.text.trim(),
      if (zone != null) 'zona $zone',
      if (booth.text.trim().isNotEmpty) 'puesto ${booth.text.trim()}',
    ];
    return parts.isEmpty ? 'Por confirmar' : parts.join(' · ');
  }

  Widget _loading() => const Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Creando pedido...'),
        ],
      ),
    ),
  );
}

class _ClaimableAuctionPickerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> claimable;
  final List<Map<String, dynamic>> selectedItems;
  final Future<String> Function(String path) imageUrl;

  const _ClaimableAuctionPickerScreen({
    required this.claimable,
    required this.selectedItems,
    required this.imageUrl,
  });

  @override
  State<_ClaimableAuctionPickerScreen> createState() =>
      _ClaimableAuctionPickerScreenState();
}

class _ClaimableAuctionPickerScreenState
    extends State<_ClaimableAuctionPickerScreen> {
  late Set<String> selectedIds;
  final imageFutures = <String, Future<String>>{};

  @override
  void initState() {
    super.initState();
    selectedIds = widget.selectedItems
        .map((item) => item['id'] as String)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in widget.claimable) {
      final publication = item['publications'] as Map<String, dynamic>;
      grouped.putIfAbsent(publication['id'] as String, () => []).add(item);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Elegir subasta')),
      body: widget.claimable.isEmpty
          ? const Center(
              child: EmptyState(
                icon: Icons.gavel,
                title: 'Sin artículos por reclamar',
                description:
                    'Los ganadores de subastas cerradas aparecerán aquí.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: grouped.entries.map((entry) {
                final publication =
                    entry.value.first['publications'] as Map<String, dynamic>;
                final endsAt = DateTime.tryParse(
                  publication['ends_at'] as String? ?? '',
                )?.toLocal();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${publication['title'] ?? 'Subasta'}'
                          '${endsAt == null ? '' : ' · ${DateFormat('d MMM, h:mm a', 'es_MX').format(endsAt)}'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: entry.value.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: .72,
                              ),
                          itemBuilder: (context, index) {
                            final item = entry.value[index];
                            final id = item['id'] as String;
                            final selected = selectedIds.contains(id);
                            final position = item['position'] as int? ?? 0;
                            final amount = item['winning_amount'] as int? ?? 0;
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => setState(() {
                                if (selected) {
                                  selectedIds.remove(id);
                                } else {
                                  selectedIds.add(id);
                                }
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).dividerColor,
                                    width: selected ? 3 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(14),
                                            ),
                                        child: FutureBuilder<String>(
                                          future: imageFutures.putIfAbsent(
                                            item['storage_path'] as String,
                                            () => widget.imageUrl(
                                              item['storage_path'] as String,
                                            ),
                                          ),
                                          builder: (context, snapshot) =>
                                              snapshot.hasData
                                              ? Image.network(
                                                  snapshot.data!,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  cacheWidth: 420,
                                                )
                                              : const Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Artículo ${position + 1}\n\$$amount',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            selected
                                                ? Icons.check_circle
                                                : Icons.circle_outlined,
                                            color: selected
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(
              context,
              widget.claimable
                  .where((item) => selectedIds.contains(item['id']))
                  .toList(),
            ),
            icon: const Icon(Icons.check),
            label: Text('Usar selección (${selectedIds.length})'),
          ),
        ),
      ),
    );
  }
}
