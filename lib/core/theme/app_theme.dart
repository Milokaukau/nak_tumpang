import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryYellow),
      scaffoldBackgroundColor: AppColors.white,
      // full poppins
      textTheme: GoogleFonts.poppinsTextTheme(),
      useMaterial3: true,
      // every top bar is yellow
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primaryYellow,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.white),
        actionsIconTheme: const IconThemeData(color: AppColors.white),
        titleTextStyle: GoogleFonts.poppins(
          color: AppColors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}