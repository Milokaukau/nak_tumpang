// shared form field for register and profile
class Validators {
  Validators._();

  static final RegExp phoneRegex = RegExp(r'^1[0-46-9][0-9]{6,8}$');
  static final RegExp emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? name(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    if (v.trim().length < 2) return 'Name is too short';
    return null;
  }

  // validate phone number
  // non-zero starting
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

  // malaysian bank account numbers check
  static final RegExp bankAccNoRegex = RegExp(r'^[0-9]{8,17}$');

  static String? bankAccountNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Account number is required';
    final cleaned = v.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (!bankAccNoRegex.hasMatch(cleaned)) {
      return 'Enter a valid account number (8-17 digits)';
    }
    return null;
  }

  static String? bankName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Select a bank';
    return null;
  }

  // Driving license numbers don't follow one official public format the
  // way the IC does, so this is a light sanity check rather than a
  // strict pattern: letters, digits, spaces and dashes only, no
  // emoji/junk paste, at least 4 characters, and — since every real
  // license number Malaysia issues contains digits — at least one digit,
  // so a value like "AAAA" (all letters, clearly not a real number) no
  // longer sails through just for being non-empty and long enough.
  static final RegExp licenseNumberRegex = RegExp(r'^[A-Z0-9](?:[A-Z0-9\s-]*[A-Z0-9])?$');

  static String? licenseNumber(String? v) {
    final trimmed = v?.trim() ?? '';
    if (trimmed.isEmpty) return 'Driving license number is required';
    if (trimmed.length < 4) return 'Please enter a valid driver license number';
    if (!licenseNumberRegex.hasMatch(trimmed)) {
      return 'Letters, numbers, spaces and dashes only';
    }
    if (!RegExp(r'[0-9]').hasMatch(trimmed)) {
      return 'License number must include at least one digit';
    }
    return null;
  }

  static final RegExp _specialCharRegex = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\[\]/\\+=~`]');

  static String? password(String? v, {bool optional = false}) {
    if (v == null || v.isEmpty) {
      return optional ? null : 'Password is required';
    }
    if (v.length < 6) return 'At least 6 characters';
    if (!RegExp(r'[a-z]').hasMatch(v) ||
        !RegExp(r'[A-Z]').hasMatch(v) ||
        !RegExp(r'[0-9]').hasMatch(v) ||
        !_specialCharRegex.hasMatch(v)) {
      return 'Include a lowercase letter, an uppercase letter, a number, and a special character';
    }
    return null;
  }

  static String? confirmPassword(String? v, String original,
      {bool optional = false}) {
    if (original.isEmpty) return optional ? null : 'Please confirm your password';
    if (v == null || v.isEmpty) return 'Please confirm your password';
    if (v != original) return 'Passwords do not match';
    return null;
  }

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

  static String toStoredPhone(String localDigits) {
    final cleaned = localDigits.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) return cleaned;
    return '+60$cleaned';
  }
}