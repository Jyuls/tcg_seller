import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_state.dart';
import '../app/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/section_title.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final AppState appState;
  const SettingsScreen({super.key, required this.appState});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController top, bottom1, bottom2, postTemplate;
  bool loading = true;
  bool disconnecting = false;
  List<Map<String, dynamic>> messageTemplates = [];
  List<Map<String, dynamic>> locations = [];
  static const templateLabels = {
    'auction_reminder': 'Recordatorio con puja',
    'auction_reminder_no_bids': 'Recordatorio sin pujas',
    'winner_unlinked': 'Ganador de subasta',
    'manual_order_confirmation': 'Confirmación de pedido',
    'bulk_delivery_reminder': 'Recordatorio de entrega',
    'bulk_arrival_notice': 'Llegada a Mundo Divertido',
    'order_delivered': 'Pedido entregado',
  };
  static const defaults = {
    'auction_reminder':
        'Esta subasta termina a las {horaCierre}. Puja mas alta: {pujaActual}.',
    'auction_reminder_no_bids':
        'Esta subasta termina a las {horaCierre}. Aún sin pujas.',
    'winner_unlinked':
        'Ganaste esta subasta. Enviame mensaje para confirmar tu pedido.',
    'manual_order_confirmation':
        'Confirmo tu pedido para este Domingo en Mundo Divertido, el total serian {precio}.',
    'bulk_delivery_reminder':
        'Hola {cliente}, te recuerdo que este domingo te entrego tu pedido en Mundo Divertido, en el puesto Tokyo Morningstore. Total: {total}.',
    'bulk_arrival_notice':
        'Ya estoy en el puesto Tokyo Morningstore, este puesto NO TIENE NUMERO, se encuentra enfrente del puesto #138, Zona 1.\n\nMe encuentras sentado en una mesa, al entrar tambien puedes preguntar por mi.\n\nVoy vestido asi: {descripcion}. Estare hasta {horaLimite}.',
    'order_delivered': 'Pedido Entregado',
  };

  Future<void> disconnectMeta() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesiÃ³n y desconectar Meta'),
        content: const Text(
          'Se revocarÃ¡ el acceso a Facebook y se eliminarÃ¡n las credenciales. '
          'Tus publicaciones, clientes y pedidos se conservarÃ¡n.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => disconnecting = true);
    try {
      await ref.read(repositoryProvider).disconnectMeta();
      ref.invalidate(pagesProvider);
      ref.invalidate(selectedPageProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo desconectar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => disconnecting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    top = TextEditingController(text: widget.appState.topImageText);
    bottom1 = TextEditingController(text: widget.appState.bottomImageTextLine1);
    bottom2 = TextEditingController(text: widget.appState.bottomImageTextLine2);
    postTemplate = TextEditingController(
      text: widget.appState.auctionPostTemplate,
    );
    load();
  }

  Future<void> load() async {
    final repo = ref.read(repositoryProvider);
    final results = await Future.wait([
      repo.getMessageTemplates(),
      repo.getDeliveryLocations(),
    ]);
    if (mounted) {
      setState(() {
        messageTemplates = results[0];
        locations = results[1];
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    top.dispose();
    bottom1.dispose();
    bottom2.dispose();
    postTemplate.dispose();
    super.dispose();
  }

  Future<void> saveGeneral() async {
    widget.appState.updateImageTexts(
      top: top.text,
      bottom1: bottom1.text,
      bottom2: bottom2.text,
    );
    widget.appState.updateAuctionTemplate(postTemplate.text);
    await ref.read(repositoryProvider).saveSettings({
      'theme_mode': widget.appState.themeMode == ThemeMode.dark
          ? 'dark'
          : 'light',
      'image_top_text': top.text,
      'image_bottom_line_1': bottom1.text,
      'image_bottom_line_2': bottom2.text,
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ConfiguraciÃ³n guardada')));
    }
  }

  Future<void> editMessage(String kind) async {
    final current = messageTemplates
        .where((row) => row['kind'] == kind)
        .firstOrNull;
    final controller = TextEditingController(
      text: current?['body'] as String? ?? defaults[kind],
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(templateLabels[kind]!),
        content: TextField(
          controller: controller,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            labelText: 'Mensaje',
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
    );
    if (save == true) {
      await ref
          .read(repositoryProvider)
          .saveMessageTemplate(kind, controller.text);
      await load();
    }
    controller.dispose();
  }

  Future<void> editLocation([Map<String, dynamic>? location]) async {
    final controller = TextEditingController(
      text: location?['name'] as String?,
    );
    var booth = location?['requires_booth'] as bool? ?? false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(location == null ? 'Nuevo lugar' : 'Editar lugar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Solicitar zona y puesto'),
                value: booth,
                onChanged: (value) => setDialog(() => booth = value),
              ),
            ],
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
    if (save == true && controller.text.trim().isNotEmpty) {
      await ref
          .read(repositoryProvider)
          .saveDeliveryLocation(
            id: location?['id'] as String?,
            name: controller.text,
            requiresBooth: booth,
          );
      await load();
    }
    controller.dispose();
  }

  Future<void> testMessengerCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Probar cÃ³digo de Messenger'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'CÃ³digo de 6 caracteres',
            helperText: 'Ejemplo: ABC123',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Probar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;
    try {
      final result = await ref
          .read(repositoryProvider)
          .testMessengerCode(code.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CÃ³digo reconocido. ConversaciÃ³n: ${result['conversation_id']}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo probar el cÃ³digo: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.appState.themeMode == ThemeMode.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('ConfiguraciÃ³n')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const SectionTitle(
                  title: 'ConfiguraciÃ³n',
                  subtitle: 'Personaliza subastas, entregas y mensajes.',
                ),
                const SizedBox(height: 16),
                ref
                    .watch(selectedPageProvider)
                    .when(
                      loading: () => const AppCard(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, _) => AppCard(
                        child: Text('No se pudo leer la cuenta: $error'),
                      ),
                      data: (page) => AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cuenta',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundImage: page?.pictureUrl == null
                                    ? null
                                    : NetworkImage(page!.pictureUrl!),
                                child: page?.pictureUrl == null
                                    ? const Icon(Icons.facebook)
                                    : null,
                              ),
                              title: Text(page?.name ?? 'Sin pÃ¡gina conectada'),
                              subtitle: const Text('PÃ¡gina de Facebook activa'),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                onPressed: disconnecting
                                    ? null
                                    : disconnectMeta,
                                icon: disconnecting
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.logout),
                                label: const Text(
                                  'Cerrar sesiÃ³n y desconectar Meta',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 12),
                AppCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tema oscuro'),
                    value: dark,
                    onChanged: widget.appState.toggleTheme,
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Texto de las imÃ¡genes',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: top,
                        decoration: const InputDecoration(
                          labelText: 'Texto superior',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: bottom1,
                        decoration: const InputDecoration(
                          labelText: 'Texto inferior 1',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: bottom2,
                        decoration: const InputDecoration(
                          labelText: 'Texto inferior 2',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: postTemplate,
                        minLines: 8,
                        maxLines: 16,
                        decoration: const InputDecoration(
                          labelText: 'Plantilla de publicaciÃ³n',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: saveGeneral,
                        icon: const Icon(Icons.save),
                        label: const Text('Guardar'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pruebas Messenger',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Usa esto sÃ³lo en desarrollo: simula que un cliente mandÃ³ un inbox con cÃ³digo de subasta.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: testMessengerCode,
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Probar cÃ³digo'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plantillas de mensajes',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Variables: {cliente}, {precio}, {total}, {cantidadArticulos}, {fechaEntrega}, {lugarEntrega}, {codigoConfirmacion}, {horaLimite}',
                      ),
                      const SizedBox(height: 8),
                      ...templateLabels.entries.map(
                        (entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.value),
                          trailing: const Icon(Icons.edit),
                          onTap: () => editMessage(entry.key),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Lugares de entrega',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed: () => editLocation(),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      ...locations.map(
                        (location) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(location['name'] as String),
                          subtitle: Text(
                            location['requires_booth'] == true
                                ? 'Solicita zona y puesto'
                                : 'Entrega directa',
                          ),
                          trailing: const Icon(Icons.edit),
                          onTap: () => editLocation(location),
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

