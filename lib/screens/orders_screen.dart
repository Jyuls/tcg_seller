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
        await repo.sendOrderConfirmation(order);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Confirmación enviada.')),
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
                      labelText: 'Número de puesto (1–900)',
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
                        labelText: 'Número de puesto (1–900)',
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: source,
                  decoration: const InputDecoration(
                    labelText: 'Descripción del artículo',
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
                : 'Ya estoy en ubicación',
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
                          label: const Text('Galería'),
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
                      labelText: 'Ropa o descripción',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: until,
                    decoration: const InputDecoration(
                      labelText: 'Estaré hasta',
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
            ].join(' · '),
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
              title: Text(item['source_label'] as String? ?? 'Artículo'),
              trailing: Text('\$${item['price']}'),
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
                  label: const Text('Ya estoy en ubicación'),
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
                        'Aquí aparecerán los pedidos automáticos o manuales.',
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
                    '${order.items.length} artículo(s) · ${order.deliveryLocation ?? 'Entrega por definir'}',
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
                    child: Text('Enviar confirmación'),
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
