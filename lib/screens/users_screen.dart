import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../app/providers.dart';
import '../models/app_models.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_title.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _CustomerAvatar extends ConsumerWidget {
  final Customer customer;
  const _CustomerAvatar({required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customer.pictureStoragePath != null) {
      return FutureBuilder<String>(
        future: ref
            .read(repositoryProvider)
            .signedCustomerImageUrl(customer.pictureStoragePath!),
        builder: (context, snapshot) => CircleAvatar(
          backgroundImage: snapshot.hasData
              ? NetworkImage(snapshot.data!)
              : null,
          child: snapshot.hasData
              ? null
              : Text(customer.name.characters.first.toUpperCase()),
        ),
      );
    }
    return CircleAvatar(
      backgroundImage: customer.pictureUrl == null
          ? null
          : NetworkImage(customer.pictureUrl!),
      child: customer.pictureUrl == null
          ? Text(customer.name.characters.first.toUpperCase())
          : null,
    );
  }
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> edit([Customer? customer]) async {
    final page = await ref.read(selectedPageProvider.future);
    if (page == null || !mounted) return;
    final locations = await ref.read(repositoryProvider).getDeliveryLocations();
    if (!mounted) return;
    final name = TextEditingController(text: customer?.name);
    final notes = TextEditingController(text: customer?.notes);
    final deliveryNotes = TextEditingController(
      text: customer?.preferredDeliveryNotes,
    );
    final fixedBooth = TextEditingController(
      text: customer?.preferredFixedBoothName,
    );
    final booth = TextEditingController(
      text: customer?.preferredBoothNumber?.toString(),
    );
    var category = customer?.category ?? 'unclassified';
    String? deliveryLocationId =
        customer?.preferredDeliveryLocationId ??
        (locations.isEmpty ? null : locations.first['id'] as String);
    var deliveryMode = customer?.preferredDeliveryMode ?? 'general';
    int? zone = customer?.preferredDeliveryZone;
    File? picture;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(customer == null ? 'Nuevo cliente' : 'Editar cliente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundImage: picture == null ? null : FileImage(picture!),
                  child: picture == null
                      ? const Icon(Icons.person_outline, size: 34)
                      : null,
                ),
                TextButton.icon(
                  onPressed: () async {
                    final selected = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 88,
                    );
                    if (selected != null) {
                      setDialog(() => picture = File(selected.path));
                    }
                  },
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Elegir fotografía'),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(
                      value: 'unclassified',
                      child: Text('Sin clasificar'),
                    ),
                    DropdownMenuItem(
                      value: 'collector',
                      child: Text('Coleccionista'),
                    ),
                    DropdownMenuItem(
                      value: 'player',
                      child: Text('Jugador TCG'),
                    ),
                    DropdownMenuItem(value: 'both', child: Text('Ambos')),
                  ],
                  onChanged: (value) => setDialog(() => category = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
                if (locations.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: deliveryLocationId,
                    decoration: const InputDecoration(
                      labelText: 'Lugar preferido',
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
                      deliveryLocationId = value;
                      final selected = locations.firstWhere(
                        (location) => location['id'] == value,
                      );
                      deliveryMode =
                          selected['default_delivery_mode'] as String? ??
                          deliveryMode;
                      fixedBooth.text =
                          selected['default_fixed_booth_name'] as String? ??
                          fixedBooth.text;
                    }),
                  ),
                  const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: fixedBooth,
                      decoration: const InputDecoration(
                        labelText: 'Puesto fijo preferido',
                      ),
                    ),
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
                      onChanged: (value) => setDialog(() => zone = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: booth,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Número de puesto opcional',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: deliveryNotes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notas de entrega preferidas',
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
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && name.text.trim().isNotEmpty) {
      await ref
          .read(repositoryProvider)
          .saveCustomer(
            id: customer?.id,
            page: page,
            name: name.text,
            category: category,
            notes: notes.text,
            picture: picture,
            preferredDeliveryLocationId: deliveryLocationId,
            preferredDeliveryMode: deliveryMode,
            preferredFixedBoothName: fixedBooth.text,
            preferredDeliveryZone: zone,
            preferredBoothNumber: int.tryParse(booth.text),
            preferredDeliveryNotes: deliveryNotes.text,
          );
      ref.invalidate(customersProvider);
    }
    name.dispose();
    notes.dispose();
    deliveryNotes.dispose();
    fixedBooth.dispose();
    booth.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(customersProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(customersProvider),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SectionTitle(
              title: 'Clientes',
              subtitle: 'Personas detectadas o registradas manualmente.',
              trailing: IconButton.filled(
                onPressed: () => edit(),
                icon: const Icon(Icons.person_add),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar clientes...',
              ),
            ),
            const SizedBox(height: 14),
            data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off,
                title: 'No se pudieron cargar',
                description: error.toString(),
              ),
              data: (customers) {
                final term = search.text.toLowerCase();
                final filtered = customers
                    .where(
                      (customer) =>
                          customer.name.toLowerCase().contains(term) ||
                          customer.notes.toLowerCase().contains(term),
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    title: 'Sin clientes',
                    description:
                        'Los ganadores aparecerán automáticamente o puedes crear uno.',
                    action: FilledButton.icon(
                      onPressed: () => edit(),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Crear cliente'),
                    ),
                  );
                }
                return Column(
                  children: filtered
                      .map(
                        (customer) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            onTap: () => edit(customer),
                            child: Row(
                              children: [
                                _CustomerAvatar(customer: customer),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(_categoryLabel(customer.category)),
                                      if (customer.notes.isNotEmpty)
                                        Text(
                                          customer.notes,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                if (customer.provisional)
                                  const Chip(label: Text('Provisional')),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => edit(),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _categoryLabel(String value) =>
      {
        'collector': 'Coleccionista',
        'player': 'Jugador TCG',
        'both': 'Coleccionista y jugador',
        'unclassified': 'Sin clasificar',
      }[value] ??
      value;
}
