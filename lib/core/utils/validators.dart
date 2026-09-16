// shared form field for register and profile
class Validators {
  Validators._();

  static final RegExp phoneRegex = RegExp(r'^1[0-46-9][0-9]{6,8}$');
  static final RegExp emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? name(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    if (v.trim().length < 2) return 'Name is too short';
    if (RegExp(r'[0-9]').hasMatch(v)) return 'Name cannot contain numbers';
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

  // Malaysian car plate validation: letters, numbers, and spaces only (NO DASHES)
  static final RegExp carPlateRegex = RegExp(r'^[A-Za-z0-9\s]+$');

  static String? carPlateNumber(String? v) {
    final trimmed = v?.trim() ?? '';
    if (trimmed.isEmpty) return 'Car plate number is required';
    if (trimmed.contains('-')) return 'Dashes are not allowed (e.g. W1234A)';
    if (trimmed.length < 2) return 'Please enter a valid car plate number';
    if (!carPlateRegex.hasMatch(trimmed)) {
      return 'Letters, numbers, and spaces only (no dashes or special characters)';
    }
    if (!RegExp(r'[0-9]').hasMatch(trimmed)) {
      return 'Car plate number must include at least one digit';
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
      return 'Include a lowercase letter, an uppercase letter, a number, and a special character (e.g. ! @ # \$ % & *)';
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