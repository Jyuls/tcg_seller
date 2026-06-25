import 'dart:io';

import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';

class GalleryService {
  static Future<void> saveImagesToGallery(List<File> images) async {
    if (images.isEmpty) return;

    final hasPermission = await _requestGalleryPermission();

    if (!hasPermission) {
      throw Exception('No se concedió permiso para guardar en galería.');
    }

    for (final image in images) {
      await Gal.putImage(image.path, album: 'TCG Seller');
    }
  }

  static Future<bool> _requestGalleryPermission() async {
    if (Platform.isAndroid) {
      final photosStatus = await Permission.photos.request();

      if (photosStatus.isGranted || photosStatus.isLimited) {
        return true;
      }

      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }

    if (Platform.isIOS) {
      final photosStatus = await Permission.photosAddOnly.request();
      return photosStatus.isGranted || photosStatus.isLimited;
    }

    return true;
  }
}
