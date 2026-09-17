import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class BaseButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isFullWidth;
  final TextStyle? textStyle;
  final bool isOutlined;
  final double? height;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final bool isLoading;

  const BaseButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isFullWidth = true,
    this.textStyle,
    this.isOutlined = false,
    this.height,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? const TextStyle(fontWeight: FontWeight.bold, fontSize: 14);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));

    final spinnerColor = isOutlined
        ? (foregroundColor ?? AppColors.black)
        : (foregroundColor ?? Colors.white);

    final buttonText = isLoading
        ? SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor),
    )
        : Text(
      text,
      style: style,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final effectiveOnPressed = isLoading ? null : onPressed;

    Widget button;

    if (isOutlined) {
      button = OutlinedButton(
        onPressed: effectiveOnPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor ?? AppColors.black,
          side: BorderSide(color: borderColor ?? AppColors.greyBorder),
          padding: const EdgeInsets.symmetric(vertical: 7),
          shape: shape,
        ),
        child: buttonText,
      );
    } else {
      button = ElevatedButton(
        onPressed: effectiveOnPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.primaryYellow,
          foregroundColor: foregroundColor ?? AppColors.black,
          padding: const EdgeInsets.symmetric(vertical: 7),
          shape: shape,
          elevation: 0,
        ),
        child: buttonText,
      );
    }

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: height,
      child: button,
    );
  }
}