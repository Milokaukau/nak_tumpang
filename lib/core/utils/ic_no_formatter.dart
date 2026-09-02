import 'package:flutter/services.dart';

// format malaysian ic number

/// Formats a Malaysian IC number as the user types: 990101-14-5678.
///
/// Previously this always collapsed the cursor to the end of the field
/// after every edit, which meant you could only ever delete from the
/// very end — backspacing in the middle (or on any segment but the
/// last) silently did nothing useful because the cursor kept jumping
/// back to the end. This version tracks how many *digits* sit before
/// the cursor before formatting, then re-finds that same position
/// after the dashes are re-inserted, so editing/backspacing works
/// anywhere in the field.
class MalaysianICInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final selectionIndex = newValue.selection.end.clamp(0, newValue.text.length);
    final rawBeforeCursor = newValue.text.substring(0, selectionIndex);
    final digitsBeforeCursor =
        rawBeforeCursor.replaceAll(RegExp(r'[^0-9]'), '').length;

    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited =
    digitsOnly.length > 12 ? digitsOnly.substring(0, 12) : digitsOnly;

    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      buffer.write(limited[i]);
      if (i == 5 || i == 7) buffer.write('-');
    }
    final formatted = buffer.toString();

    // Walk the freshly-formatted string until we've passed the same
    // number of digits that used to sit before the cursor.
    var newOffset = formatted.length;
    if (digitsBeforeCursor <= 0) {
      newOffset = 0;
    } else {
      var digitsSeen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != '-') digitsSeen++;
        if (digitsSeen == digitsBeforeCursor) {
          newOffset = i + 1;
          break;
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}