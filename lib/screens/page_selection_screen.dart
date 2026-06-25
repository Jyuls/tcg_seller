import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_state.dart';
import '../app/providers.dart';
import '../models/app_models.dart';
import '../navigation/main_navigation.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_title.dart';

class PageSelectionScreen extends ConsumerStatefulWidget {
  final AppState appState;
  final String? initialError;
  const PageSelectionScreen({
    super.key,
    required this.appState,
    this.initialError,
  });

  @override
  ConsumerState<PageSelectionScreen> createState() =>
      _PageSelectionScreenState();
}

class _PageSelectionScreenState extends ConsumerState<PageSelectionScreen> {
  bool loading = true;
  String? error;
  List<FacebookPage> pages = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = widget.initialError;
    });
    try {
      final result = await ref
          .read(repositoryProvider)
          .getPages(refreshMeta: true);
      if (!mounted) return;
      if (result.length == 1) {
        await choose(result.first);
        return;
      }
      setState(() => pages = result);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> choose(FacebookPage page) async {
    setState(() => loading = true);
    try {
      await ref.read(repositoryProvider).selectPage(page.id);
      ref.invalidate(selectedPageProvider);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MainNavigation(appState: widget.appState),
        ),
        (_) => false,
      );
    } catch (exception) {
      if (mounted) {
        setState(() {
          loading = false;
          error = exception.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => ref.read(repositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionTitle(
            title: 'Elige una página',
            subtitle: 'TCG Seller trabajará como la página seleccionada.',
          ),
          const SizedBox(height: 18),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (pages.isEmpty)
            EmptyState(
              icon: Icons.facebook,
              title: 'No hay páginas disponibles',
              description:
                  error ??
                  'Tu cuenta debe tener acceso completo o por tareas a una página.',
              action: FilledButton.icon(
                onPressed: load,
                icon: const Icon(Icons.refresh),
                label: const Text('Volver a consultar'),
              ),
            )
          else
            ...pages.map(
              (page) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  onTap: () => choose(page),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: page.pictureUrl == null
                            ? null
                            : NetworkImage(page.pictureUrl!),
                        child: page.pictureUrl == null
                            ? const Icon(Icons.flag)
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          page.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          if (error != null && pages.isNotEmpty)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
