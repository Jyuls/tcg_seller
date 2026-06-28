import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../app/providers.dart';
import '../models/app_models.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_title.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String filter = 'pending';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> action(OrderSummary order, String action) async {
    final repo = ref.read(repositoryProvider);
    if (action == 'edit') {
      await editDelivery(order);
      return;
    }
    if (action == 'confirm') {
      try {
        final result = await repo.sendOrderConfirmation(order);
        if (mounted) {
          final blocked = result['photos_blocked'] as int? ?? 0;
          final viaTemplate = result['via_template'] == true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                blocked > 0
                    ? 'Confirmación enviada por template. Meta bloqueó $blocked foto(s) por ventana cerrada.'
                    : viaTemplate
                    ? 'Confirmación enviada por template aprobado.'
                    : 'Confirmación enviada con fotos.',
              ),
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('No se pudo enviar: $error')));
        }
      }
      return;
    }
    if (action == 'paid') await repo.markOrderPaid(order.id);
    if (action == 'delivered') await repo.markOrderDelivered(order.id);
    if (action == 'cancelled') await repo.cancelOrder(order.id);
    if (action == 'pack') await repo.packOrderNext(order.id);
    if (action == 'unpack') await repo.unpackOrder(order.id);
    ref.invalidate(ordersProvider);
  }

  Future<void> editDelivery(OrderSummary order) async {
    final repo = ref.read(repositoryProvider);
    final locations = await repo.getDeliveryLocations();
    if (!mounted) return;
    String? locationId = order.deliveryLocationId;
    int? zone = order.deliveryZone;
    final booth = TextEditingController(text: order.boothNumber?.toString());
    final notes = TextEditingController(text: order.deliveryNotes);
    bool requiresBooth() =>
        locationId != null &&
        locations.any(
          (location) =>
              location['id'] == locationId &&
              location['requires_booth'] == true,
        );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Editar entrega'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: locationId,
                  decoration: const InputDecoration(
                    labelText: 'Lugar de entrega',
                  ),
                  items: locations
                      .map(
                        (location) => DropdownMenuItem(
                          value: location['id'] as String,
                          child: Text(location['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialog(() {
                    locationId = value;
                    if (!requiresBooth()) zone = null;
                  }),
                ),
                if (requiresBooth()) ...[
                  const SizedBox(height: 10),
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
                    onChanged: (value) => setDialog(() => zone = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: booth,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'NÃºmero de puesto (1â€“900)',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final boothNumber = int.tryParse(booth.text);
    if (save == true &&
        (!requiresBooth() ||
            (zone != null &&
                boothNumber != null &&
                boothNumber >= 1 &&
                boothNumber <= 900))) {
      await repo.updateOrderDelivery(
        orderId: order.id,
        deliveryLocationId: locationId,
        zone: requiresBooth() ? zone : null,
        boothNumber: requiresBooth() ? boothNumber : null,
        notes: notes.text,
      );
      ref.invalidate(ordersProvider);
    }
    booth.dispose();
    notes.dispose();
  }

  Future<void> createManual() async {
    final repo = ref.read(repositoryProvider);
    final page = await ref.read(selectedPageProvider.future);
    final customers = await repo.getCustomers();
    final locations = await repo.getDeliveryLocations();
    if (page == null || customers.isEmpty || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Primero crea un cliente.')),
        );
      }
      return;
    }
    String customerId = customers.first.id;
    String? locationId = locations.isEmpty
        ? null
        : locations.first['id'] as String;
    var deliveryMode = locations.isEmpty
        ? 'general'
        : locations.first['default_delivery_mode'] as String? ?? 'general';
    final source = TextEditingController(text: 'Venta manual');
    final price = TextEditingController();
    final fixedBooth = TextEditingController(
      text: locations.isEmpty
          ? ''
          : locations.first['default_fixed_booth_name'] as String? ?? '',
    );
    final booth = TextEditingController();
    final notes = TextEditingController();
    final helpText = TextEditingController(
      text: locations.isEmpty
          ? ''
          : locations.first['location_help_text'] as String? ?? '',
    );
    int? zone;
    bool requiresBooth() =>
        locationId != null &&
        locations.firstWhere(
              (location) => location['id'] == locationId,
            )['requires_booth'] ==
            true;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Crear pedido manual'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: customerId,
                  decoration: const InputDecoration(labelText: 'Cliente'),
                  items: customers
                      .map(
                        (customer) => DropdownMenuItem(
                          value: customer.id,
                          child: Text(customer.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialog(() => customerId = value!),
                ),
                if (locations.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: locationId,
                    decoration: const InputDecoration(
                      labelText: 'Lugar de entrega',
                    ),
                    items: locations
                        .map(
                          (location) => DropdownMenuItem(
                            value: location['id'] as String,
                            child: Text(location['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialog(() {
                      locationId = value;
                      final selected = locations.firstWhere(
                        (location) => location['id'] == value,
                      );
                      deliveryMode =
                          selected['default_delivery_mode'] as String? ??
                          deliveryMode;
                      fixedBooth.text =
                          selected['default_fixed_booth_name'] as String? ??
                          fixedBooth.text;
                      helpText.text =
                          selected['location_help_text'] as String? ??
                          helpText.text;
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: deliveryMode,
                    decoration: const InputDecoration(labelText: 'Modo'),
                    items: const [
                      DropdownMenuItem(
                        value: 'general',
                        child: Text('General'),
                      ),
                      DropdownMenuItem(
                        value: 'fixed_booth',
                        child: Text('Puesto fijo'),
                      ),
                      DropdownMenuItem(
                        value: 'roaming',
                        child: Text('Ambulando'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialog(() => deliveryMode = value!),
                  ),
                  if (deliveryMode == 'fixed_booth') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: fixedBooth,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del puesto fijo',
                      ),
                    ),
                  ],
                  if (requiresBooth()) ...[
                    const SizedBox(height: 10),
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
                      onChanged: (value) => setDialog(() => zone = value),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: booth,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'NÃºmero de puesto (1â€“900)',
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: source,
                  decoration: const InputDecoration(
                    labelText: 'DescripciÃ³n del artÃ­culo',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Precio',
                    prefixText: '\$',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas de entrega',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: helpText,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'C?mo encontrar el lugar',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final amount = int.tryParse(price.text);
      final boothNumber = int.tryParse(booth.text);
      if (requiresBooth() &&
          (zone == null ||
              boothNumber == null ||
              boothNumber < 1 ||
              boothNumber > 900)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Indica zona y puesto del 1 al 900.')),
          );
        }
        return;
      }
      if (!mounted) return;
      final photoSource = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Tomar foto'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir de galer?a'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (photoSource == null) return;
      final photo = await ImagePicker().pickImage(
        source: photoSource,
        imageQuality: 90,
      );
      if (amount != null && photo != null) {
        await repo.createManualOrderItem(
          page: page,
          customer: customers.firstWhere(
            (customer) => customer.id == customerId,
          ),
          image: File(photo.path),
          sourceLabel: source.text,
          price: amount,
          deliveryLocationId: locationId,
          deliveryMode: deliveryMode,
          fixedBoothName: fixedBooth.text,
          deliveryZone: requiresBooth() ? zone : null,
          boothNumber: requiresBooth() ? boothNumber : null,
          locationHelpText: helpText.text,
          deliveryNotes: notes.text,
        );
        ref.invalidate(ordersProvider);
      }
    }
    source.dispose();
    price.dispose();
    fixedBooth.dispose();
    booth.dispose();
    notes.dispose();
    helpText.dispose();
  }

  Future<void> assignAuctionItem() async {
    final repo = ref.read(repositoryProvider);
    final claimable = await repo.getClaimableAuctionItems();
    final customers = await repo.getCustomers();
    if (!mounted) return;
    if (claimable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay artÃ­culos de subasta por asignar.'),
        ),
      );
      return;
    }
    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay clientes. Sincroniza Messenger o espera a que respondan.',
          ),
        ),
      );
      return;
    }
    final selectedPublication =
        await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          builder: (context) => _AuctionPickerSheet(items: claimable),
        );
    if (selectedPublication == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AuctionAssignmentBoard(
          publication: selectedPublication,
          initialItems: claimable.where((item) {
            final publication = item['publications'] as Map<String, dynamic>;
            return publication['id'] == selectedPublication['id'];
          }).toList(),
          customers: customers,
          imageUrl: repo.signedImageUrl,
          assignItem: (item, customer) =>
              repo.assignClaimedAuctionItemsToCustomer(
                customerId: customer.id,
                items: [item],
              ),
          clearRemaining: () =>
              repo.discardRemainingClaimableItems(selectedPublication['id']),
        ),
      ),
    );
    ref.invalidate(ordersProvider);
  }

  Future<void> sendBulk(String action) async {
    final repo = ref.read(repositoryProvider);
    final locations = await repo.getDeliveryLocations();
    if (!mounted) return;
    String? locationId = locations.isEmpty
        ? null
        : locations.first['id'] as String;
    final detail = TextEditingController(
      text: locations.isEmpty
          ? ''
          : repo.deliveryDetailText(
              locationName: locations.first['name'] as String?,
              deliveryMode:
                  locations.first['default_delivery_mode'] as String? ??
                  'general',
              fixedBoothName:
                  locations.first['default_fixed_booth_name'] as String?,
              helpText: locations.first['location_help_text'] as String? ?? '',
            ),
    );
    final description = TextEditingController();
    final until = TextEditingController();
    File? image;
    Future<void> pickImage(StateSetter setDialog, ImageSource source) async {
      final selected = await ImagePicker().pickImage(
        source: source,
        imageQuality: 88,
      );
      if (selected != null) setDialog(() => image = File(selected.path));
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            action == 'bulk_delivery_reminder'
                ? 'Recordar entrega'
                : 'Ya estoy en ubicaciÃ³n',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locations.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: locationId,
                    decoration: const InputDecoration(
                      labelText: 'Enviar a pedidos de',
                    ),
                    items: locations
                        .map(
                          (location) => DropdownMenuItem(
                            value: location['id'] as String,
                            child: Text(location['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialog(() {
                      locationId = value;
                      final selected = locations.firstWhere(
                        (location) => location['id'] == value,
                      );
                      detail.text = repo.deliveryDetailText(
                        locationName: selected['name'] as String?,
                        deliveryMode:
                            selected['default_delivery_mode'] as String? ??
                            'general',
                        fixedBoothName:
                            selected['default_fixed_booth_name'] as String?,
                        helpText:
                            selected['location_help_text'] as String? ?? '',
                      );
                    }),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: detail,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Detalle de entrega',
                  ),
                ),
                if (action == 'bulk_arrival_notice') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              pickImage(setDialog, ImageSource.camera),
                          icon: const Icon(Icons.photo_camera),
                          label: const Text('Foto'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              pickImage(setDialog, ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('GalerÃ­a'),
                        ),
                      ),
                    ],
                  ),
                  if (image != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(image!, height: 120, fit: BoxFit.cover),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(
                      labelText: 'Ropa o descripciÃ³n',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: until,
                    decoration: const InputDecoration(
                      labelText: 'EstarÃ© hasta',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        final result = await repo.sendBulkOrderMessage(
          action: action,
          deliveryLocationId: locationId,
          deliveryDetail: detail.text,
          description: description.text,
          until: until.text,
          image: image,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Enviados: ${result['sent'] ?? 0}. Fallidos: ${result['failed'] ?? 0}.',
              ),
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('No se pudo enviar: $error')));
        }
      }
    }
    detail.dispose();
    description.dispose();
    until.dispose();
  }

  Future<void> deleteOrderItem(
    BuildContext context,
    OrderSummary order,
    Map<String, dynamic> item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar artÃ­culo'),
        content: Text(
          'Â¿Quitar "${item['source_label'] ?? 'este artÃ­culo'}" '
          'del pedido de ${order.customerName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).removeOrderItem(item);
      if (!context.mounted) return;
      Navigator.pop(context);
      ref.invalidate(ordersProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ArtÃ­culo eliminado.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $error')));
    }
  }

  void detail(OrderSummary order) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .65,
      maxChildSize: .9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            order.customerName,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            order.paymentStatus == 'paid'
                ? 'PAGADO'
                : 'Total: \$${order.total}',
          ),
          Text(
            [
              order.deliveryLocation ?? 'Entrega por definir',
              if (order.deliveryZone != null) 'Zona ${order.deliveryZone}',
              if (order.boothNumber != null) 'Puesto ${order.boothNumber}',
            ].join(' Â· '),
          ),
          if (order.deliveryNotes.isNotEmpty) Text(order.deliveryNotes),
          const Divider(height: 28),
          ...order.items.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: item['photo_storage_path'] == null
                  ? const CircleAvatar(child: Icon(Icons.style))
                  : FutureBuilder<String>(
                      future: ref
                          .read(repositoryProvider)
                          .signedImageUrl(item['photo_storage_path'] as String),
                      builder: (context, snapshot) => CircleAvatar(
                        backgroundImage: snapshot.hasData
                            ? NetworkImage(snapshot.data!)
                            : null,
                        child: snapshot.hasData
                            ? null
                            : const Icon(Icons.image_outlined),
                      ),
                    ),
              title: Text(item['source_label'] as String? ?? 'ArtÃ­culo'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('\$${item['price']}'),
                  IconButton(
                    tooltip: 'Eliminar artÃ­culo',
                    icon: const Icon(Icons.delete_outline),
                    color: Theme.of(context).colorScheme.error,
                    onPressed: () => deleteOrderItem(context, order, item),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(ordersProvider),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SectionTitle(
              title: 'Pedidos',
              subtitle: 'Ganancias agrupadas por cliente y entrega.',
              trailing: IconButton.filled(
                onPressed: createManual,
                icon: const Icon(Icons.add),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar pedidos...',
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text('Pendientes')),
                ButtonSegment(value: 'delivered', label: Text('Entregados')),
                ButtonSegment(value: 'cancelled', label: Text('Cancelados')),
              ],
              selected: {filter},
              onSelectionChanged: (value) =>
                  setState(() => filter = value.first),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => sendBulk('bulk_delivery_reminder'),
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: const Text('Recordar entrega'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => sendBulk('bulk_arrival_notice'),
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('Ya estoy en ubicaciÃ³n'),
                ),
                FilledButton.tonalIcon(
                  onPressed: assignAuctionItem,
                  icon: const Icon(Icons.gavel),
                  label: const Text('Asignar subasta'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off,
                title: 'No se pudieron cargar',
                description: error.toString(),
              ),
              data: (orders) {
                final term = search.text.toLowerCase();
                final items = orders
                    .where(
                      (order) =>
                          order.deliveryStatus == filter &&
                          order.customerName.toLowerCase().contains(term),
                    )
                    .toList();
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Sin pedidos',
                    description:
                        'AquÃ­ aparecerÃ¡n los pedidos automÃ¡ticos o manuales.',
                  );
                }
                return Column(
                  children: items
                      .map(
                        (order) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _OrderCard(
                            order: order,
                            onOpen: () => detail(order),
                            onAction: (value) => action(order, value),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: createManual,
        icon: const Icon(Icons.add),
        label: const Text('Pedido'),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderSummary order;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;
  const _OrderCard({
    required this.order,
    required this.onOpen,
    required this.onAction,
  });
  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onOpen,
    child: Column(
      children: [
        Row(
          children: [
            CircleAvatar(
              child: Text(order.customerName.characters.first.toUpperCase()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.customerName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${order.items.length} artÃ­culo(s) Â· ${order.deliveryLocation ?? 'Entrega por definir'}',
                  ),
                  if (order.packingPosition != null)
                    Text(
                      'Caja #${order.packingPosition}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            if (order.paymentStatus == 'paid')
              const Chip(label: Text('PAGADO'))
            else
              Text(
                '\$${order.total}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            PopupMenuButton<String>(
              onSelected: onAction,
              itemBuilder: (_) => [
                if (order.deliveryStatus == 'pending')
                  const PopupMenuItem(
                    value: 'confirm',
                    child: Text('Enviar confirmaciÃ³n'),
                  ),
                if (order.paymentStatus != 'paid')
                  const PopupMenuItem(
                    value: 'paid',
                    child: Text('Marcar pagado'),
                  ),
                if (order.deliveryStatus == 'pending')
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Editar entrega'),
                  ),
                if (order.deliveryStatus == 'pending')
                  PopupMenuItem(
                    value: order.packingPosition == null ? 'pack' : 'unpack',
                    child: Text(
                      order.packingPosition == null
                          ? 'Poner en caja'
                          : 'Quitar de caja',
                    ),
                  ),
                if (order.deliveryStatus == 'pending')
                  const PopupMenuItem(
                    value: 'cancelled',
                    child: Text('Cancelar pedido'),
                  ),
              ],
            ),
          ],
        ),
        if (order.deliveryStatus == 'pending') ...[
          const SizedBox(height: 12),
          if (order.packingPosition == null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onAction('pack'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Poner en caja'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => onAction('delivered'),
              icon: const Icon(Icons.check),
              label: const Text('Marcar entregado'),
            ),
          ),
        ],
      ],
    ),
  );
}

class _AuctionPickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _AuctionPickerSheet({required this.items});

  String _formatDate(String? raw) {
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return 'Sin fecha';
    final months = const [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    var hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '${date.day} ${months[date.month - 1]}, $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final publication = item['publications'] as Map<String, dynamic>;
      grouped.putIfAbsent(publication['id'] as String, () => []).add(item);
    }
    final entries = grouped.entries.toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      minChildSize: .45,
      maxChildSize: .92,
      builder: (context, controller) => SafeArea(
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              'Elegir subasta',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'SÃ³lo aparecen subastas terminadas con pujas pendientes.',
            ),
            const SizedBox(height: 16),
            ...entries.map((entry) {
              final publication =
                  entry.value.first['publications'] as Map<String, dynamic>;
              final endsAt = _formatDate(publication['ends_at'] as String?);
              final total = entry.value.fold<int>(
                0,
                (sum, item) => sum + (item['winning_amount'] as int? ?? 0),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  onTap: () => Navigator.pop(context, publication),
                  child: Row(
                    children: [
                      const CircleAvatar(child: Icon(Icons.gavel)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${publication['title'] ?? 'Subasta'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text('Cierre: $endsAt'),
                            Text(
                              '${entry.value.length} artÃ­culo(s) por asignar',
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '\$$total',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _AuctionAssignmentBoard extends StatefulWidget {
  final Map<String, dynamic> publication;
  final List<Map<String, dynamic>> initialItems;
  final List<Customer> customers;
  final Future<String> Function(String path) imageUrl;
  final Future<void> Function(Map<String, dynamic> item, Customer customer)
  assignItem;
  final Future<void> Function() clearRemaining;

  const _AuctionAssignmentBoard({
    required this.publication,
    required this.initialItems,
    required this.customers,
    required this.imageUrl,
    required this.assignItem,
    required this.clearRemaining,
  });

  @override
  State<_AuctionAssignmentBoard> createState() =>
      _AuctionAssignmentBoardState();
}

class _AuctionAssignmentBoardState extends State<_AuctionAssignmentBoard> {
  late List<Map<String, dynamic>> items;
  final imageFutures = <String, Future<String>>{};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    items = [...widget.initialItems]
      ..sort(
        (a, b) =>
            (a['position'] as int? ?? 0).compareTo(b['position'] as int? ?? 0),
      );
  }

  Future<void> assign(Map<String, dynamic> item) async {
    final customer = await showDialog<Customer>(
      context: context,
      builder: (context) => _CustomerPickerDialog(customers: widget.customers),
    );
    if (customer == null) return;
    setState(() => busy = true);
    try {
      await widget.assignItem(item, customer);
      if (!mounted) return;
      setState(() {
        items.removeWhere((entry) => entry['id'] == item['id']);
        busy = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Asignado a ${customer.name}.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo asignar: $error')));
    }
  }

  Future<void> clearRemaining() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar subasta'),
        content: Text(
          'Se quitarÃ¡n ${items.length} artÃ­culo(s) pendientes de esta lista. '
          'Ãšsalo cuando ya terminaste de asignar lo reclamado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => busy = true);
    await widget.clearRemaining();
    if (!mounted) return;
    setState(() {
      items = [];
      busy = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Subasta limpiada.')));
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.publication['title'] ?? 'Subasta'}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton.icon(
            onPressed: busy || items.isEmpty ? null : clearRemaining,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Limpiar'),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (items.isEmpty)
            const Center(
              child: EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Subasta asignada',
                description:
                    'Ya no quedan artÃ­culos pendientes en esta subasta.',
              ),
            )
          else
            GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: .72,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                final path = item['storage_path'] as String;
                final position = item['position'] as int? ?? 0;
                final amount = item['winning_amount'] as int? ?? 0;
                return AppCard(
                  onTap: busy ? null : () => assign(item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: FutureBuilder<String>(
                            future: imageFutures.putIfAbsent(
                              path,
                              () => widget.imageUrl(path),
                            ),
                            builder: (context, snapshot) => snapshot.hasData
                                ? Image.network(
                                    snapshot.data!,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    cacheWidth: 420,
                                  )
                                : const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ArtÃ­culo ${position + 1}'),
                            Text(
                              '\$$amount',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const Text('Toca para asignar'),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (busy)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _CustomerPickerDialog extends StatefulWidget {
  final List<Customer> customers;
  const _CustomerPickerDialog({required this.customers});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final search = TextEditingController();

  String normalize(String value) => value
      .toLowerCase()
      .replaceAll('Ã¡', 'a')
      .replaceAll('Ã©', 'e')
      .replaceAll('Ã­', 'i')
      .replaceAll('Ã³', 'o')
      .replaceAll('Ãº', 'u')
      .replaceAll('Ã¼', 'u')
      .replaceAll('Ã±', 'n');

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = normalize(search.text);
    final customers = widget.customers
        .where((customer) => normalize(customer.name).contains(term))
        .toList();
    return AlertDialog(
      title: const Text('Elegir cliente ganador'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar cliente...',
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: customers.length,
                itemBuilder: (context, index) {
                  final customer = customers[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(customer.name.characters.first.toUpperCase()),
                    ),
                    title: Text(customer.name),
                    subtitle: customer.preferredDeliveryLocation == null
                        ? null
                        : Text(customer.preferredDeliveryLocation!),
                    onTap: () => Navigator.pop(context, customer),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
