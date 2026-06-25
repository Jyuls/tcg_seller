import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_state.dart';
import '../app/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/section_title.dart';
import 'page_selection_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  final AppState appState;
  const HomeScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publications =
        ref.watch(publicationsProvider).asData?.value ?? const [];
    final orders = ref.watch(ordersProvider).asData?.value ?? const [];
    final alerts = ref.watch(alertsProvider).asData?.value ?? const [];
    final selectedPage = ref.watch(selectedPageProvider).asData?.value;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(publicationsProvider);
        ref.invalidate(ordersProvider);
        ref.invalidate(alertsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.style,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SectionTitle(
                  title: 'TCG Seller',
                  subtitle: selectedPage?.name ?? 'Administración de tu página',
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'settings') {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(appState: appState),
                      ),
                    );
                    return;
                  }
                  if (value == 'page') {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PageSelectionScreen(appState: appState),
                      ),
                    );
                    return;
                  }
                  if (value == 'logout') {
                    await ref.read(repositoryProvider).signOut();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      leading: Icon(Icons.settings),
                      title: Text('Configuración'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'page',
                    child: ListTile(
                      leading: Icon(Icons.flag),
                      title: Text('Cambiar página'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout),
                      title: Text('Cerrar sesión'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resumen de hoy',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _SummaryRow(
                  icon: Icons.gavel,
                  label: 'Subastas activas',
                  value:
                      '${publications.where((item) => item.status.name == 'active').length}',
                ),
                const SizedBox(height: 10),
                _SummaryRow(
                  icon: Icons.inventory_2,
                  label: 'Pedidos por entregar',
                  value:
                      '${orders.where((item) => item.deliveryStatus == 'pending').length}',
                ),
                const SizedBox(height: 10),
                _SummaryRow(
                  icon: Icons.warning_amber,
                  label: 'Alertas pendientes',
                  value: '${alerts.length}',
                ),
              ],
            ),
          ),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Requiere atención',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...alerts
                .take(5)
                .map(
                  (alert) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          alert['severity'] == 'error'
                              ? Icons.error
                              : Icons.info,
                          color: alert['severity'] == 'error'
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                        title: Text(alert['title'] as String),
                        subtitle: Text(alert['body'] as String),
                      ),
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flujo automático',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Publica tus fotografías, recibe pujas, cierra con la hora exacta de Meta y agrupa los artículos ganados en pedidos.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 22),
      const SizedBox(width: 10),
      Expanded(child: Text(label)),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    ],
  );
}
