import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app/app_state.dart';

class ManualAuctionCameraScreen extends StatefulWidget {
  final AppState appState;
  final String? bottomLine2Override;

  const ManualAuctionCameraScreen({
    super.key,
    required this.appState,
    this.bottomLine2Override,
  });

  @override
  State<ManualAuctionCameraScreen> createState() =>
      _ManualAuctionCameraScreenState();
}

class _ManualAuctionCameraScreenState extends State<ManualAuctionCameraScreen> {
  final GlobalKey previewKey = GlobalKey();
  final ScrollController thumbnailsController = ScrollController();

  CameraController? controller;
  List<CameraDescription> cameras = [];
  List<File> capturedImages = [];

  bool isLoading = true;
  bool isCapturing = false;
  bool isSaving = false;
  String? errorMessage;

  // 2.5 es buen balance entre rapidez/calidad.
  // Si quieres más calidad prueba 3.0.
  // Si se siente pesado baja a 2.0.
  static const double capturePixelRatio = 2.5;

  // Recortes reales al guardar la imagen final.
  // Estos valores quitan la UI de arriba y la UI de abajo.
  static const double topUiHeight = 90;
  static const double bottomUiHeight = 190;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    thumbnailsController.dispose();
    controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          errorMessage = 'No se encontró cámara disponible.';
          isLoading = false;
        });
        return;
      }

      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await cameraController.initialize();

      if (!mounted) return;

      setState(() {
        controller = cameraController;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'No se pudo iniciar la cámara: $error';
        isLoading = false;
      });
    }
  }

  Future<void> _captureImage() async {
    if (isCapturing || isSaving) return;

    final cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    try {
      setState(() => isCapturing = true);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      final file = await _capturePreviewAsImage();

      if (!mounted) return;

      setState(() {
        capturedImages.add(file);
        isCapturing = false;
      });

      _scrollThumbnailsToEnd();
    } catch (error) {
      if (!mounted) return;

      setState(() => isCapturing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al capturar imagen: $error')),
      );
    }
  }

  Future<File> _capturePreviewAsImage() async {
    final boundary =
        previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

    if (boundary == null) {
      throw Exception('No se pudo capturar el preview.');
    }

    final ui.Image fullImage = await boundary.toImage(
      pixelRatio: capturePixelRatio,
    );

    final double cropLeft = 0;
    final double cropTop = topUiHeight * capturePixelRatio;
    final double cropWidth = fullImage.width.toDouble();
    final double cropHeight =
        fullImage.height.toDouble() -
        (topUiHeight * capturePixelRatio) -
        (bottomUiHeight * capturePixelRatio);

    if (cropHeight <= 0) {
      throw Exception('El recorte es inválido.');
    }

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final Rect sourceRect = Rect.fromLTWH(
      cropLeft,
      cropTop,
      cropWidth,
      cropHeight,
    );

    final Rect destinationRect = Rect.fromLTWH(0, 0, cropWidth, cropHeight);

    canvas.drawImageRect(
      fullImage,
      sourceRect,
      destinationRect,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );

    final ui.Picture picture = recorder.endRecording();

    final ui.Image croppedImage = await picture.toImage(
      cropWidth.toInt(),
      cropHeight.toInt(),
    );

    final ByteData? byteData = await croppedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) {
      throw Exception('No se pudo convertir la captura.');
    }

    final Uint8List bytes = byteData.buffer.asUint8List();

    final tempDirectory = Directory.systemTemp;
    final fileName = 'subasta_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${tempDirectory.path}/$fileName');

    await file.writeAsBytes(bytes, flush: false);

    return file;
  }

  void _scrollThumbnailsToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!thumbnailsController.hasClients) return;

      thumbnailsController.animateTo(
        thumbnailsController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _deleteLastImage() {
    if (capturedImages.isEmpty || isSaving) return;

    final lastImage = capturedImages.removeLast();

    if (lastImage.existsSync()) {
      lastImage.deleteSync();
    }

    setState(() {});
    _scrollThumbnailsToEnd();
  }

  Future<void> _finishAndSave() async {
    if (capturedImages.isEmpty || isSaving) return;

    try {
      setState(() => isSaving = true);

      final cameraController = controller;
      controller = null;
      setState(() {});

      await cameraController?.dispose();

      if (!mounted) return;

      setState(() => isSaving = false);

      Navigator.pop(context, capturedImages);
    } catch (error) {
      if (!mounted) return;

      setState(() => isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar imágenes: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cameraController = controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (isLoading) {
              return _CameraLoadingView(
                topText: widget.appState.topImageText,
                bottomLine1: widget.appState.bottomImageTextLine1,
                bottomLine2:
                    widget.bottomLine2Override ??
                    widget.appState.bottomImageTextLine2,
              );
            }

            if (errorMessage != null) {
              return _CameraErrorView(
                message: errorMessage!,
                onRetry: () {
                  setState(() {
                    isLoading = true;
                    errorMessage = null;
                  });
                  _initCamera();
                },
              );
            }

            if (cameraController == null ||
                !cameraController.value.isInitialized) {
              return const _FullScreenLoadingMessage(message: 'Preparando...');
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    key: previewKey,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(cameraController),
                        _AuctionFrameOverlay(
                          topText: widget.appState.topImageText,
                          bottomLine1: widget.appState.bottomImageTextLine1,
                          bottomLine2:
                              widget.bottomLine2Override ??
                              widget.appState.bottomImageTextLine2,
                        ),
                      ],
                    ),
                  ),
                ),

                _TopCameraBar(
                  count: capturedImages.length,
                  isSaving: isSaving,
                  onClose: () => Navigator.pop(context),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _BottomCameraBar(
                    images: capturedImages,
                    thumbnailsController: thumbnailsController,
                    isCapturing: isCapturing,
                    isSaving: isSaving,
                    onDeleteLast: _deleteLastImage,
                    onCapture: _captureImage,
                    onFinish: _finishAndSave,
                  ),
                ),

                if (isCapturing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.24),
                      child: const Center(
                        child: _LoadingPanel(message: 'Capturando foto...'),
                      ),
                    ),
                  ),

                if (isSaving)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.92),
                      child: Center(
                        child: _LoadingPanel(
                          message:
                              'Preparando ${capturedImages.length} imagen(es)...',
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopCameraBar extends StatelessWidget {
  final int count;
  final bool isSaving;
  final VoidCallback onClose;

  const _TopCameraBar({
    required this.count,
    required this.isSaving,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: _ManualAuctionCameraScreenState.topUiHeight,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF16071F).withValues(alpha: 0.96),
              const Color(0xFF32104A).withValues(alpha: 0.78),
              Colors.black.withValues(alpha: 0.12),
            ],
          ),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
        child: Row(
          children: [
            _GlassIconButton(
              icon: Icons.close,
              onPressed: isSaving ? null : onClose,
            ),
            const Spacer(),
            _PhotoCounterBadge(count: count),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _GlassIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: Colors.white, size: 25),
        ),
      ),
    );
  }
}

class _PhotoCounterBadge extends StatelessWidget {
  final int count;

  const _PhotoCounterBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF6D28D9).withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D28D9).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_camera, color: Colors.white, size: 18),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraLoadingView extends StatelessWidget {
  final String topText;
  final String bottomLine1;
  final String bottomLine2;

  const _CameraLoadingView({
    required this.topText,
    required this.bottomLine1,
    required this.bottomLine2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          Positioned(
            top: 118,
            left: 20,
            right: 20,
            child: _BigOverlayText(text: topText, maxFontSize: 74),
          ),
          Positioned(
            bottom: 210,
            left: 20,
            right: 20,
            child: Column(
              children: [
                _BigOverlayText(text: bottomLine1, maxFontSize: 58),
                const SizedBox(height: 8),
                _BigOverlayText(text: bottomLine2, maxFontSize: 68),
              ],
            ),
          ),
          const Center(child: _LoadingPanel(message: 'Preparando cámara...')),
        ],
      ),
    );
  }
}

class _FullScreenLoadingMessage extends StatelessWidget {
  final String message;

  const _FullScreenLoadingMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(child: _LoadingPanel(message: message)),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  final String message;

  const _LoadingPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF151019),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Esto puede tardar unos segundos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _AuctionFrameOverlay extends StatelessWidget {
  final String topText;
  final String bottomLine1;
  final String bottomLine2;

  const _AuctionFrameOverlay({
    required this.topText,
    required this.bottomLine1,
    required this.bottomLine2,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;

          // SUBASTA debajo de la barra superior.
          final topPosition =
              _ManualAuctionCameraScreenState.topUiHeight + (height * 0.025);

          // Texto inferior por encima del carrusel/botones.
          final bottomPosition = height * 0.225;

          return Stack(
            children: [
              Positioned(
                top: topPosition,
                left: 12,
                right: 12,
                child: _BigOverlayText(text: topText, maxFontSize: 74),
              ),
              Positioned(
                bottom: bottomPosition,
                left: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BigOverlayText(text: bottomLine1, maxFontSize: 58),
                    const SizedBox(height: 8),
                    _BigOverlayText(text: bottomLine2, maxFontSize: 68),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BigOverlayText extends StatelessWidget {
  final String text;
  final double maxFontSize;

  const _BigOverlayText({required this.text, required this.maxFontSize});

  @override
  Widget build(BuildContext context) {
    final displayText = text.trim().isEmpty ? ' ' : text.trim();

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              displayText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: maxFontSize,
                height: 0.9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 7
                  ..color = Colors.black,
              ),
            ),
            Text(
              displayText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: maxFontSize,
                height: 0.9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomCameraBar extends StatelessWidget {
  final List<File> images;
  final ScrollController thumbnailsController;
  final bool isCapturing;
  final bool isSaving;
  final VoidCallback onDeleteLast;
  final VoidCallback onCapture;
  final VoidCallback onFinish;

  const _BottomCameraBar({
    required this.images,
    required this.thumbnailsController,
    required this.isCapturing,
    required this.isSaving,
    required this.onDeleteLast,
    required this.onCapture,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasImages = images.isNotEmpty;

    return Container(
      color: const Color(0xFF100617).withValues(alpha: 0.98),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 62,
            child: images.isEmpty
                ? Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: const Text(
                      'Sin fotos todavía',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : ListView.separated(
                    controller: thumbnailsController,
                    scrollDirection: Axis.horizontal,
                    itemCount: images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final isLast = index == images.length - 1;

                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isLast
                                ? const Color(0xFFC084FC)
                                : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: isLast
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF9333EA,
                                    ).withValues(alpha: 0.42),
                                    blurRadius: 14,
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            images[index],
                            width: 52,
                            height: 62,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: IconButton.filledTonal(
                  onPressed: !hasImages || isSaving || isCapturing
                      ? null
                      : onDeleteLast,
                  icon: const Icon(Icons.delete),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: isCapturing || isSaving ? null : onCapture,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: isCapturing || isSaving ? 0.55 : 1,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFFFFF), Color(0xFFE9D5FF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFA855F7,
                            ).withValues(alpha: 0.45),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFF100617),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFC084FC),
                              width: 3,
                            ),
                          ),
                          child: isCapturing
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 28,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: IconButton.filled(
                  onPressed: !hasImages || isSaving || isCapturing
                      ? null
                      : onFinish,
                  icon: const Icon(Icons.check),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CameraErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
                size: 60,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
