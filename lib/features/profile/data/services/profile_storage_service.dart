import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles picking an image from the device and uploading it to a
/// Supabase Storage bucket for the current user's profile.
class ProfileStorageService {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  /// Picks an image and returns its raw bytes. We use bytes rather than
  /// a dart:io File because File isn't backed by a real filesystem path
  /// on Flutter Web (image_picker gives back a blob: URL there), which
  /// made FileImage/Image.file fail silently or throw.
  Future<Uint8List?> pickImage({required ImageSource source}) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  /// Uploads [bytes] to [bucket] under `<userId>/<fileName>` and returns a
  /// URL that can be stored on the user's profile row.
  ///
  /// Set [public] to false for sensitive documents (e.g. a driver's
  /// license) that live in a private bucket — a signed, time-limited URL
  /// is returned instead of a permanent public one.
  Future<String> uploadUserFile({
    required Uint8List bytes,
    required String bucket,
    required String userId,
    required String fileName,
    bool public = true,
  }) async {
    final path = '$userId/$fileName';

    await _supabase.storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );

    if (public) return _supabase.storage.from(bucket).getPublicUrl(path);
    return path; // store this, not a signed URL
  }

  /// Call this whenever you actually need to show/download a private file.
  Future<String> getSignedUrl({
    required String bucket,
    required String path,
    int expiresInSeconds = 3600,
  }) {
    return _supabase.storage.from(bucket).createSignedUrl(path, expiresInSeconds);
  }
}
