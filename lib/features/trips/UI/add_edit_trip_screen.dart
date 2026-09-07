import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/components/location_autocomplete_field.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/trips/view_models/add_edit_trip_view_model.dart';
import 'package:nak_tumpang/features/trips/view_models/my_trips_view_model.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

const _weekdayNames = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class AddEditTripScreen extends StatelessWidget {
  final Map<String, dynamic>? existingTrip;

  const AddEditTripScreen({super.key, this.existingTrip});

  @override
  Widget build(BuildContext context) {
    final role = context.read<MyTripsViewModel>().currentUserRole;

    return ChangeNotifierProvider(
      create: (_) => AddEditTripViewModel(role, existingTrip: existingTrip),
      child: const _AddEditTripView(),
    );
  }
}

class _AddEditTripView extends StatelessWidget {
  const _AddEditTripView();

  Future<void> _complete(BuildContext context, AddEditTripViewModel vm) async {
    final savedTrip = await vm.submit();
    if (!context.mounted || savedTrip == null) return;

    // Refresh the My Trips list
    context.read<MyTripsViewModel>().loadMyTrips();

    // --- OPTIMIZED: Update Home Dashboard locally instead of heavy API refetch ---
    context.read<HomeViewModel>().addOrUpdateLocalTrip(savedTrip);

    Navigator.of(context).pop();
  }

  Future<void> _pickTime(BuildContext context, TimeOfDay initial, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AddEditTripViewModel>();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Add New Trip', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.white,
        iconTheme: const IconThemeData(color: AppColors.black),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Trip Name', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: vm.nameController,
                decoration: _fieldDecoration(hintText: 'e.g. Work Commute'),
              ),
              if (vm.nameError != null) _errorText(vm.nameError!),
              const SizedBox(height: 20),

              const Text('I travel from', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              LocationAutocompleteField(
                controller: vm.fromController,
                hintText: 'e.g. KLCC',
                onSelected: vm.setFromPlace,
                onCleared: vm.clearFromPlace,
              ),
              if (vm.fromError != null) _errorText(vm.fromError!),
              const SizedBox(height: 8),

              const Text('to', style: TextStyle(color: AppColors.greyText)),
              const SizedBox(height: 8),
              LocationAutocompleteField(
                controller: vm.toController,
                hintText: 'e.g. TARUMT',
                onSelected: vm.setToPlace,
                onCleared: vm.clearToPlace,
              ),
              if (vm.toError != null) _errorText(vm.toError!),
              const SizedBox(height: 20),

              const Text('Every...', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _DayPicker(
                selectedDay: vm.fromDay,
                onChanged: vm.setFromDay,
              ),
              const SizedBox(height: 8),
              const Text('to', style: TextStyle(color: AppColors.greyText)),
              const SizedBox(height: 8),
              _DayPicker(
                selectedDay: vm.toDay,
                onChanged: vm.setToDay,
              ),
              if (vm.dayError != null) _errorText(vm.dayError!),
              const SizedBox(height: 20),

              const Text('I usually depart at...', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _TimePickerField(
                time: vm.departTime,
                onTap: () => _pickTime(context, vm.departTime, vm.setDepartTime),
              ),
              const SizedBox(height: 20),

              const Text('I usually arrive destination at...', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _TimePickerField(
                time: vm.arriveTime,
                onTap: () => _pickTime(context, vm.arriveTime, vm.setArriveTime),
              ),
              if (vm.timeError != null) _errorText(vm.timeError!),

              if (vm.errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(vm.errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],

              const SizedBox(height: 28),
              BaseButton(
                text: 'Save Trip',
                isLoading: vm.isSubmitting,
                onPressed: () => _complete(context, vm),
                height: 54,
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorText(String error) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Text(error, style: const TextStyle(color: Colors.red, fontSize: 12)),
    );
  }

  InputDecoration _fieldDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: AppColors.greyText),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.greyBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.greyBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primaryYellow, width: 1.5),
      ),
    );
  }
}

// ---------------------------------------------------------
// Reused custom components to match your exact requested UI
// ---------------------------------------------------------

class _DayPicker extends StatelessWidget {
  final int selectedDay;
  final ValueChanged<int> onChanged;

  const _DayPicker({required this.selectedDay, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showModalBottomSheet<int>(
          context: context,
          builder: (_) => ListView(
            shrinkWrap: true,
            children: List.generate(7, (i) => i + 1)
                .map((day) => ListTile(
              title: Text(_weekdayNames[day]),
              onTap: () => Navigator.pop(context, day),
            ))
                .toList(),
          ),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.greyBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(child: Text(_weekdayNames[selectedDay])),
            const Icon(Icons.calendar_today, color: AppColors.primaryYellow, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TimePickerField extends StatelessWidget {
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimePickerField({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.greyBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(child: Text(time.format(context))),
            const Icon(Icons.access_time, color: AppColors.primaryYellow, size: 18),
          ],
        ),
      ),
    );
  }
}