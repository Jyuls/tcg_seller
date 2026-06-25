import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app/app_state.dart';
import '../app/providers.dart';
import '../models/app_models.dart';
import '../services/app_repository.dart';
import '../widgets/app_card.dart';
import 'manual_auction_camera_screen.dart';

class AuctionEditorScreen extends ConsumerStatefulWidget {
  final AppState appState;
  final FacebookPage page;
  const AuctionEditorScreen({
    super.key,
    required this.appState,
    required this.page,
  });

  @override
  ConsumerState<AuctionEditorScreen> createState() =>
      _AuctionEditorScreenState();
}

class _AuctionEditorScreenState extends ConsumerState<AuctionEditorScreen> {
  final bodyController = TextEditingController();
  final startingController = TextEditingController(text: '5');
  final minimumController = TextEditingController(text: '5');
  final images = <File>[];
  late DateTime startsAt;
  late DateTime endsAt;
  int step = 0;
  bool saving = false;
  bool completed = false;
  String? publicationId;
  int uploaded = 0;
  int uploadTotal = 0;
  int? capturedMinimum;

  static const stepTitles = [
    'Fecha de la subasta',
    'Pujas',
    'Instrucciones extra',
    'Fotografías',
    'Vista previa',
  ];

  @override
  void initState() {
    super.initState();
    final now = tz.TZDateTime.now(tz.local);
    startsAt = now;
    endsAt = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, 21);
    bodyController.text = widget.appState.auctionPostTemplate;
  }

  @override
  void dispose() {
    bodyController.dispose();
    startingController.dispose();
    minimumController.dispose();
    super.dispose();
  }

  Future<DateTime?> pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  Future<void> chooseStart() async {
    final selected = await pickDateTime(startsAt);
    if (selected == null) return;
    setState(() {
      startsAt = selected;
      endsAt = tz.TZDateTime(
        tz.local,
        selected.year,
        selected.month,
        selected.day + 1,
        21,
      );
    });
  }

  Future<void> openCamera() async {
    final minimum = int.tryParse(minimumController.text) ?? 5;
    final result = await Navigator.of(context).push<List<File>>(
      MaterialPageRoute(
        builder: (_) => ManualAuctionCameraScreen(
          appState: widget.appState,
          bottomLine2Override: '\$$minimum PESOS',
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        images.addAll(result.take(30 - images.length));
        capturedMinimum = minimum;
      });
    }
  }

  bool validateStep() {
    if (step == 0 && !endsAt.isAfter(startsAt)) {
      showError('La finalización debe ser posterior al inicio.');
      return false;
    }
    if (step == 1) {
      final initial = int.tryParse(startingController.text);
      final minimum = int.tryParse(minimumController.text);
      if (initial == null || initial < 0 || minimum == null || minimum <= 0) {
        showError('Revisa la puja inicial y la puja mínima.');
        return false;
      }
      if (images.isNotEmpty && capturedMinimum != minimum) {
        setState(() {
          images.clear();
          capturedMinimum = null;
        });
        showError('Cambió la puja mínima; toma nuevamente las fotografías.');
      }
    }
    if (step == 2 && bodyController.text.trim().isEmpty) {
      showError('Agrega las instrucciones de la publicación.');
      return false;
    }
    if (step == 3 && images.isEmpty) {
      showError('Toma al menos una fotografía.');
      return false;
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

  String renderedBody() {
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return bodyController.text
        .replaceAll('{diaHoy}', startsAt.day.toString())
        .replaceAll('{mesHoy}', months[startsAt.month - 1])
        .replaceAll('{diaManana}', endsAt.day.toString())
        .replaceAll('{mesManana}', months[endsAt.month - 1]);
  }

  bool get isScheduled =>
      startsAt.isAfter(DateTime.now().add(const Duration(minutes: 1)));

  Future<void> createPublication() async {
    if (!validateStep()) return;
    setState(() {
      saving = true;
      completed = false;
      uploaded = 0;
      uploadTotal = images.length;
    });
    try {
      publicationId = await ref
          .read(repositoryProvider)
          .createAuction(
            publicationId: publicationId,
            page: widget.page,
            images: images,
            body: renderedBody(),
            startsAt: startsAt,
            endsAt: endsAt,
            startingBid: int.parse(startingController.text),
            bidIncrement: int.parse(minimumController.text),
            mode: isScheduled
                ? AuctionSaveMode.scheduled
                : AuctionSaveMode.publishNow,
            onProgress: (value, total) {
              if (mounted) {
                setState(() {
                  uploaded = value;
                  uploadTotal = total;
                });
              }
            },
          );
      if (!mounted) return;
      setState(() => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.pop(context, true);
    } on AuctionSaveException catch (error) {
      publicationId = error.publicationId;
      if (mounted) {
        setState(() => saving = false);
        showError('La carga se conservó. Toca Reintentar: ${error.cause}');
      }
    } catch (error) {
      if (mounted) {
        setState(() => saving = false);
        showError('No se pudo crear la publicación: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (saving) return _buildLoading();
    return PopScope(
      canPop: true,
      child: Scaffold(
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
                    Text(stepTitles[step]),
                  ],
                ),
              ),
              Expanded(child: _buildStep()),
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
                            ? createPublication
                            : next,
                        icon: Icon(
                          step == stepTitles.length - 1
                              ? (isScheduled ? Icons.schedule : Icons.publish)
                              : Icons.arrow_forward,
                        ),
                        label: Text(
                          step == stepTitles.length - 1
                              ? (publicationId == null
                                    ? 'Crear publicación'
                                    : 'Reintentar')
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
      ),
    );
  }

  Widget _buildStep() => switch (step) {
    0 => _dateStep(),
    1 => _bidStep(),
    2 => _instructionsStep(),
    3 => _photosStep(),
    _ => _previewStep(),
  };

  Widget _page(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(18), children: children);

  Widget _dateStep() {
    final format = DateFormat('EEEE d MMMM y · h:mm a', 'es');
    return _page([
      const Text('Elige cuándo inicia y termina la subasta.'),
      const SizedBox(height: 16),
      AppCard(
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_arrow),
              title: const Text('Fecha de inicio'),
              subtitle: Text(format.format(startsAt)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: chooseStart,
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag),
              title: const Text('Fecha de finalización'),
              subtitle: Text(format.format(endsAt)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final value = await pickDateTime(endsAt);
                if (value != null) setState(() => endsAt = value);
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        isScheduled
            ? 'Se publicará automáticamente en la fecha de inicio.'
            : 'Se publicará inmediatamente al finalizar estos pasos.',
      ),
    ]);
  }

  Widget _bidStep() => _page([
    const Text('Estos valores se cargarán en la publicación y en las fotos.'),
    const SizedBox(height: 16),
    AppCard(
      child: Column(
        children: [
          TextField(
            controller: startingController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Puja inicial',
              prefixText: '\$',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: minimumController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Puja mínima',
              prefixText: '\$',
              helperText: 'Cantidad mínima válida para aumentar una puja.',
            ),
          ),
        ],
      ),
    ),
  ]);

  Widget _instructionsStep() => _page([
    const Text('Revisa o edita las instrucciones cargadas por defecto.'),
    const SizedBox(height: 16),
    AppCard(
      child: TextField(
        controller: bodyController,
        minLines: 12,
        maxLines: 20,
        decoration: const InputDecoration(
          labelText: 'Instrucciones extra',
          alignLabelWithHint: true,
        ),
      ),
    ),
  ]);

  Widget _photosStep() => _page([
    Text('La cámara mostrará PUJA MÍNIMA \$${minimumController.text} PESOS.'),
    const SizedBox(height: 16),
    AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Fotografías',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              Text('${images.length}/30'),
            ],
          ),
          const SizedBox(height: 12),
          if (images.isNotEmpty)
            SizedBox(
              height: 120,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  setState(
                    () => images.insert(newIndex, images.removeAt(oldIndex)),
                  );
                },
                itemBuilder: (context, index) => Padding(
                  key: ValueKey(images[index].path),
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(
                          images[index],
                          width: 92,
                          height: 116,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: IconButton.filledTonal(
                          iconSize: 16,
                          onPressed: () =>
                              setState(() => images.removeAt(index)),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: images.length >= 30 ? null : openCamera,
              icon: const Icon(Icons.camera_alt),
              label: Text(
                images.isEmpty ? 'Abrir cámara' : 'Agregar fotografías',
              ),
            ),
          ),
        ],
      ),
    ),
  ]);

  Widget _previewStep() {
    final format = DateFormat('d MMM y · h:mm a', 'es');
    return _page([
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (images.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  images.first,
                  height: 210,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 14),
            Text(
              isScheduled ? 'PUBLICACIÓN PROGRAMADA' : 'PUBLICAR AHORA',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text('Inicio: ${format.format(startsAt)}'),
            Text('Finaliza: ${format.format(endsAt)}'),
            Text('Puja inicial: \$${startingController.text}'),
            Text('Puja mínima: \$${minimumController.text}'),
            Text('${images.length} artículo(s)'),
            const Divider(height: 28),
            Text(renderedBody()),
          ],
        ),
      ),
    ]);
  }

  Widget _buildLoading() => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  completed ? Icons.check_circle : Icons.cloud_upload_outlined,
                  size: 78,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 22),
                Text(
                  completed
                      ? (isScheduled
                            ? 'Publicación programada'
                            : 'Publicación creada')
                      : (isScheduled
                            ? 'Programando publicación…'
                            : 'Creando publicación…'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: uploadTotal == 0 ? null : uploaded / uploadTotal,
                ),
                const SizedBox(height: 10),
                Text(
                  completed
                      ? 'Todo listo'
                      : 'Cargando foto $uploaded de $uploadTotal',
                ),
                const SizedBox(height: 8),
                const Text(
                  'No cierres esta pantalla.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
