import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of [ProfileStorageService.validateImage] — a lightweight,
/// fully-offline sanity check run before any upload. This is NOT
/// authenticity verification (it can't tell a real license from a photo
/// of someone else's license) — it only catches the cheap, common
/// failure cases: not actually an image, corrupted, or too small/low-res
/// to be legible at all.
class ImageCheckResult {
  final bool isValid;
  final String? error;
  const ImageCheckResult._(this.isValid, this.error);
  const ImageCheckResult.ok() : this._(true, null);
  const ImageCheckResult.invalid(String error) : this._(false, error);
}

// handles user selecting image to set as profile picture
class ProfileStorageService {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();


  static const int _minBytes = 5 * 1024; // 5 KB
  static const int _maxBytes = 8 * 1024 * 1024; // 8 MB - catches raw/HEIC passthrough
  static const int _minDimension = 400;

  Future<Uint8List?> pickImage({required ImageSource source}) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  /// Client-side sanity check run before a picked image is accepted:
  /// size within a sane range, and actually decodable as an image with
  /// enough resolution to be legible. Catches "picked the wrong file" /
  /// corrupted-file cases immediately, without a round trip to storage.
  Future<ImageCheckResult> validateImage(Uint8List bytes) async {
    if (bytes.lengthInBytes < _minBytes) {
      return const ImageCheckResult.invalid('This image looks empty or corrupted. Please choose another.');
    }
    if (bytes.lengthInBytes > _maxBytes) {
      return const ImageCheckResult.invalid('This image is too large. Please choose a smaller photo.');
    }
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final bool tooSmall;
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        tooSmall = image.width < _minDimension || image.height < _minDimension;
        image.dispose();
      } finally {
        // Codec.dispose() releases native decoder resources that aren't
        // guaranteed to be freed just because the decoded image was —
        // matters here since this runs on every photo pick, not just once.
        codec.dispose();
      }
      if (tooSmall) {
        return const ImageCheckResult.invalid('This image is too low-resolution to be readable. Please choose a clearer photo.');
      }
      return const ImageCheckResult.ok();
    } catch (_) {
      return const ImageCheckResult.invalid('This file doesn\'t look like a valid image. Please choose another.');
    }
  }

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

  Future<String> getSignedUrl({
    required String bucket,
    required String path,
    int expiresInSeconds = 3600,
  }) {
    return _supabase.storage.from(bucket).createSignedUrl(path, expiresInSeconds);
  }

  /// Best-effort cleanup for a file that was just uploaded but never got
  /// committed to by the corresponding DB write (see [uploadUserFile] —
  /// callers use a unique filename per upload specifically so this can
  /// remove *only* the failed attempt, never a file another write is
  /// still relying on). Failures here don't rethrow or surface to the
  /// user — worst case is one unreferenced file left in storage, which
  /// is harmless, and the whole point is to not let a cleanup error mask
  /// the original failure. They're still logged, though, so an orphaned
  /// file has *some* trace a developer can search for instead of vanishing
  /// silently.
  Future<void> deleteUserFile({required String bucket, required String path}) async {
    try {
      await _supabase.storage.from(bucket).remove([path]);
    } catch (e) {
      debugPrint('ProfileStorageService: failed to clean up orphaned file "$path" in bucket "$bucket": $e');
    }
  }
}