import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/components/location_autocomplete_field.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/profile/view_models/post_signup_driver_view_model.dart';

const _weekdayNames = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

// Optional post-signup step for drivers — the account itself (users +
// driver_profiles) already exists by the time this screen is reached
// (RegisterViewModel writes it immediately, same as passengers). This
// screen just lets the driver add their first route/schedule into
// driver_trips; skipping it (via "Later" on the get-started dialog)
// leaves a perfectly valid driver account with no trips yet.
class PostSignupDriverScreen extends StatelessWidget {
  final String userId;

  const PostSignupDriverScreen({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PostSignupDriverViewModel(userId: userId),
      child: const _PostSignupDriverView(),
    );
  }
}

class _PostSignupDriverView extends StatelessWidget {
  const _PostSignupDriverView();

  Future<void> _complete(BuildContext context, PostSignupDriverViewModel vm) async {
    final success = await vm.submit();
    if (!context.mounted || !success) return;
    // Home is already the screen underneath (see RegisterScreen — this
    // is only ever pushed on top of it), so pop back to it rather than
    // pushReplacement-ing in a second, brand-new HomeScreen instance.
    Navigator.of(context).pop();
  }

  Future<void> _pickTime(BuildContext context, TimeOfDay initial, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PostSignupDriverViewModel>();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Add your route'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text('I drive from', style: TextStyle(fontWeight: FontWeight.w600)),
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
              const SizedBox(height: 6),
              Text(
                'Active days: ${vm.activeDaysPreview.join(", ")}',
                style: const TextStyle(color: AppColors.greyText, fontSize: 12),
              ),
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
                text: 'Complete',
                isLoading: vm.isSubmitting,
                onPressed: () => _complete(context, vm),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorText(String error) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(error, style: const TextStyle(color: Colors.red, fontSize: 12)),
    );
  }
}

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