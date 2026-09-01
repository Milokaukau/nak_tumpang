/// Shared form-field validation, used by both the Register and Profile
/// screens so their rules can't drift apart. Register screen is the
/// source of truth for these rules.
class Validators {
  Validators._();

  // Malaysian mobile, local format: 01 + [0,2-9] + 6-8 digits.
  // Expects the '+60' country code to already be stripped off (see
  // [localDigitsFromStored]) — the field only ever holds the local part.
  static final RegExp phoneRegex = RegExp(r'^01[0-46-9][0-9]{6,8}$');
  static final RegExp emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? name(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    if (v.trim().length < 2) return 'Name is too short';
    return null;
  }

  static String? ic(String? v) {
    if (v == null || v.trim().isEmpty) return 'IC number is required';
    final digitsOnly = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length != 12) return 'Enter a valid 12-digit IC number';
    return null;
  }

  /// [v] is the local digits-only phone text (e.g. "0123456789") as typed
  /// into the field next to the fixed '+60' prefix.
  static String? phoneLocal(String? v) {
    if (v == null || v.trim().isEmpty) return 'Phone number is required';
    final cleaned = v.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (!phoneRegex.hasMatch(cleaned)) {
      return 'Enter a valid number, e.g. 0123456789';
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
  /// stored phone number, leaving the local digits starting with '0'
  /// (e.g. "+60123456789" -> "0123456789"). Used to bring an
  /// already-saved phone back into the form the phone field edits.
  static String localDigitsFromStored(String? stored) {
    if (stored == null) return '';
    var cleaned = stored.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.startsWith('+60')) {
      cleaned = '0${cleaned.substring(3)}';
    } else if (cleaned.startsWith('60')) {
      cleaned = '0${cleaned.substring(2)}';
    }
    return cleaned;
  }

  /// Turns local digits (e.g. "0123456789") into the '+60...' form saved
  /// to the database, matching how Register stores new numbers.
  static String toStoredPhone(String localDigits) {
    final cleaned = localDigits.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) return cleaned;
    return '+60${cleaned.substring(1)}';
  }

  /// Formats a 12-digit IC number as "YYMMDD-PB-###G" for display,
  /// matching the live-typing format used on the register screen.
  /// Returns the input unchanged if it isn't exactly 12 digits.
  static String formatICForDisplay(String? digitsOnly) {
    if (digitsOnly == null) return '';
    final digits = digitsOnly.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 12) return digitsOnly;
    return '${digits.substring(0, 6)}-${digits.substring(6, 8)}-${digits.substring(8, 12)}';
  }
}
