import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class BaseButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isFullWidth;
  final TextStyle? textStyle;
  final bool isOutlined;
  final double? height;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  const BaseButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isFullWidth = true,
    this.textStyle,
    this.isOutlined = false,
    this.height,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? const TextStyle(fontWeight: FontWeight.bold, fontSize: 14);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));

    Widget button;

    if (isOutlined) {
      button = OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor ?? AppColors.black,
          side: BorderSide(color: borderColor ?? AppColors.greyBorder),
          padding: const EdgeInsets.symmetric(vertical: 7),
          shape: shape,
        ),
        child: Text(
          text,
          style: style,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    } else {
      button = ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.primaryYellow,
          foregroundColor: foregroundColor ?? AppColors.black,
          padding: const EdgeInsets.symmetric(vertical: 7),
          shape: shape,
          elevation: 0,
        ),
        child: Text(
          text,
          style: style,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: height,
      child: button,
    );
  }
}