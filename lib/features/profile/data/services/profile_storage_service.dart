import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// handles user selecting image to set as profile picture
class ProfileStorageService {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  Future<Uint8List?> pickImage({required ImageSource source}) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
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
}
