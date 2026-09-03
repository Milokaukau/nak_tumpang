/// Shared form-field validation, used by both the Register and Profile
/// screens so their rules can't drift apart. Register screen is the
/// source of truth for these rules.
class Validators {
  Validators._();

  // Malaysian mobile, local format without the leading '0': 1 + [0,2-9] +
  // 6-8 digits. The leading '0' is dropped because the field always sits
  // right next to a fixed '+60' prefix, so re-typing the '0' is redundant.
  // Expects the '+60' country code to already be stripped off (see
  // [localDigitsFromStored]) — the field only ever holds the local part.
  static final RegExp phoneRegex = RegExp(r'^1[0-46-9][0-9]{6,8}$');
  static final RegExp emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? name(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    if (v.trim().length < 2) return 'Name is too short';
    return null;
  }

  /// [v] is the local digits-only phone text (e.g. "123456789", no leading
  /// '0') as typed into the field next to the fixed '+60' prefix.
  static String? phoneLocal(String? v) {
    if (v == null || v.trim().isEmpty) return 'Phone number is required';
    final cleaned = v.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (!phoneRegex.hasMatch(cleaned)) {
      return 'Enter a valid number, e.g. 123456789';
    }
    return null;
  }

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
    return null;
  }

  /// Set [optional] to true for fields like Profile's "change password"
  /// where leaving it blank means "keep the current password".
  static String? password(String? v, {bool optional = false}) {
    if (v == null || v.isEmpty) {
      return optional ? null : 'Password is required';
    }
    if (v.length < 6) return 'At least 6 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  /// [original] is the current value of the password field being
  /// confirmed. Set [optional] to true when an empty [original] means no
  /// password change was requested (Profile screen).
  static String? confirmPassword(String? v, String original,
      {bool optional = false}) {
    if (original.isEmpty) return optional ? null : 'Please confirm your password';
    if (v == null || v.isEmpty) return 'Please confirm your password';
    if (v != original) return 'Passwords do not match';
    return null;
  }

  /// Strips spaces/dashes and any '+60'/'60' country-code prefix from a
  /// stored phone number, leaving the bare local digits with no leading
  /// '0' (e.g. "+60123456789" -> "123456789"). Used to bring an
  /// already-saved phone back into the form the phone field edits.
  static String localDigitsFromStored(String? stored) {
    if (stored == null) return '';
    var cleaned = stored.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.startsWith('+60')) {
      cleaned = cleaned.substring(3);
    } else if (cleaned.startsWith('60')) {
      cleaned = cleaned.substring(2);
    } else if (cleaned.startsWith('0')) {
      // Handles data saved before the leading '0' was dropped from the
      // stored format.
      cleaned = cleaned.substring(1);
    }
    return cleaned;
  }

  /// Turns local digits with no leading '0' (e.g. "123456789") into the
  /// '+60...' form saved to the database.
  static String toStoredPhone(String localDigits) {
    final cleaned = localDigits.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) return cleaned;
    return '+60$cleaned';
  }
}