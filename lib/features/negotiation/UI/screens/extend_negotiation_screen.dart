import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/utils/negotiation_error.dart';
import 'package:nak_tumpang/features/negotiation/utils/date_range_rules.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_field_row.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/route_map_header.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/propose_value_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/time_proposal_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/map_screen.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/negotiation_screen.dart';

/// Screen for requesting an extension of an existing (already-paid)
/// subscription.
///
/// Deliberately self-contained: the ONLY thing a caller needs to provide
/// is [subscriptionId]. This mirrors how [NegotiationSummaryCard]'s
/// `onRenew`/`onCancelSubscription` callbacks are already scoped to just
/// a subscription id elsewhere in this module, so wiring the Subscription
/// Module's "Extend" button to this screen should be a one-line change:
///
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => ExtendNegotiationScreen(subscriptionId: subscription.id),
///   ),
/// );
/// ```
///
/// Prefill source: the `tumpang_subscription` row itself, NOT a separate
/// "last negotiation request" lookup. The subscription row is written
/// FROM the last negotiation request's agreed fields at the moment it was
/// finalized (see TumpangSummaryScreen._handlePayDeposit and
/// NegotiationSupabaseService.finalizeExtension) — so it already IS the
/// last negotiation's result, and reading it directly avoids ambiguity
/// about which `tumpang_request` row (there can be several sharing the
/// same subscription_id across an extension chain) counts as "the last
/// one" when there's no reliable timestamp column to sort by.
///
/// The subscription's start date always carries over unchanged (matches
/// NegotiationSupabaseService.createExtensionRequest, which has no
/// start-date override param) — only the end date, and optionally
/// pickup/dropoff/pickup time/fee, can be changed here.
class ExtendNegotiationScreen extends StatefulWidget {
  final String subscriptionId;

  const ExtendNegotiationScreen({super.key, required this.subscriptionId});

  @override
  State<ExtendNegotiationScreen> createState() => _ExtendNegotiationScreenState();
}

class _ExtendNegotiationScreenState extends State<ExtendNegotiationScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;

  /// The raw subscription row this extension is based on. Null means "no
  /// previous negotiation data found" — handled gracefully below by
  /// falling back to empty/default values, same as a brand new negotiation.
  Map<String, dynamic>? _subscription;

  // Prefilled/editable fields. Values are ORIGINALS from the subscription
  // until the user edits them — used both for display and to detect which
  // fields actually changed (so we only send overrides for those, and so
  // fields that DIDN'T change stay accepted, per createExtensionRequest's
  // existing semantics).
  late String _pickupName;
  late double _pickupLat;
  late double _pickupLng;
  late String _dropoffName;
  late double _dropoffLat;
  late double _dropoffLng;
  late String _pickupTimeDb; // "HH:mm:ss"
  late double _fee;

  String? _originalPickupName;
  double? _originalPickupLat;
  double? _originalPickupLng;
  String? _originalDropoffName;
  double? _originalDropoffLat;
  double? _originalDropoffLng;
  String? _originalPickupTimeDb;
  double? _originalFee;

  DateTime? _subscriptionStartDate; // carries over unchanged, display-only
  DateTime? _oldEndDate; // null if no previous subscription data at all
  late DateTime _newEndDate;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    final controller = context.read<NegotiationViewModel>();
    final sub = await controller.getSubscriptionById(widget.subscriptionId);

    if (!mounted) return;

    setState(() {
      _subscription = sub;

      if (sub != null) {
        _pickupName = sub['pickup_location']?.toString() ?? '';
        _pickupLat = double.tryParse(sub['pickup_lat']?.toString() ?? '') ?? 0.0;
        _pickupLng = double.tryParse(sub['pickup_lng']?.toString() ?? '') ?? 0.0;
        _dropoffName = sub['dropoff_location']?.toString() ?? '';
        _dropoffLat = double.tryParse(sub['dropoff_lat']?.toString() ?? '') ?? 0.0;
        _dropoffLng = double.tryParse(sub['dropoff_lng']?.toString() ?? '') ?? 0.0;
        _pickupTimeDb = sub['pickup_time']?.toString() ?? '09:00:00';
        _fee = double.tryParse(sub['fee']?.toString() ?? '') ?? 0.0;

        _originalPickupName = _pickupName;
        _originalPickupLat = _pickupLat;
        _originalPickupLng = _pickupLng;
        _originalDropoffName = _dropoffName;
        _originalDropoffLat = _dropoffLat;
        _originalDropoffLng = _dropoffLng;
        _originalPickupTimeDb = _pickupTimeDb;
        _originalFee = _fee;

        _subscriptionStartDate = DateTime.tryParse(sub['subscription_start_date']?.toString() ?? '');
        _oldEndDate = DateTime.tryParse(sub['subscription_end_date']?.toString() ?? '');
      } else {
        // No previous negotiation data available — fall back to the same
        // empty/default values a brand new negotiation would start with.
        _pickupName = '';
        _pickupLat = 0.0;
        _pickupLng = 0.0;
        _dropoffName = '';
        _dropoffLat = 0.0;
        _dropoffLng = 0.0;
        _pickupTimeDb = '09:00:00';
        _fee = 0.0;
        _subscriptionStartDate = null;
        _oldEndDate = null;
      }

      final base = _oldEndDate ?? DateTime.now();
      final daysInTargetMonth = DateTime(base.year, base.month + 2, 0).day;
      final day = base.day > daysInTargetMonth ? daysInTargetMonth : base.day;
      _newEndDate = DateTime(base.year, base.month + 1, day);

      _isLoading = false;
    });
  }

  String _formatAmPm(String dbTime) {
    if (dbTime.isEmpty) return dbTime;
    try {
      final parts = dbTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } catch (e) {
      return dbTime;
    }
  }

  String _formatDate(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  void _openLocationPicker({required bool isPickup}) {
    Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          title: isPickup ? 'Pickup Location' : 'Dropoff Location',
          initialName: isPickup ? _pickupName : _dropoffName,
          initialLat: isPickup ? _pickupLat : _dropoffLat,
          initialLng: isPickup ? _pickupLng : _dropoffLng,
        ),
      ),
    ).then((result) {
      if (result == null || !mounted) return;
      setState(() {
        if (isPickup) {
          _pickupName = result['name'];
          _pickupLat = result['lat'];
          _pickupLng = result['lng'];
        } else {
          _dropoffName = result['name'];
          _dropoffLat = result['lat'];
          _dropoffLng = result['lng'];
        }
      });
    });
  }

  void _openPickupTimeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => TimeProposalBottomSheet(initialTime: _pickupTimeDb),
    ).then((result) {
      if (result != null && result is String && mounted) {
        setState(() => _pickupTimeDb = result);
      }
    });
  }

  void _openFeeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ProposeValueBottomSheet(
        title: 'Fee (per day)',
        currentValue: _fee.toStringAsFixed(2),
        onSubmit: (value) async {
          final parsed = double.tryParse(value);
          if (parsed == null) {
            throw NegotiationException('Please enter a valid fee amount.');
          }
          if (mounted) setState(() => _fee = parsed);
        },
      ),
    );
  }

  Future<void> _pickNewEndDate() async {
    final minEnd = (_oldEndDate ?? DateTime.now()).add(const Duration(days: 1));
    final initial = _newEndDate.isBefore(minEnd) ? minEnd : _newEndDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minEnd, // must extend PAST the current end date
      lastDate: minEnd.add(const Duration(days: 730)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryYellow,
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null && mounted) {
      setState(() => _newEndDate = picked);
    }
  }

  String? _validate() {
    if (_pickupName.trim().isEmpty) return 'Please set a pickup location.';
    if (_dropoffName.trim().isEmpty) return 'Please set a dropoff location.';
    if (_fee < 0) return 'Please enter a valid fee.'; // Fix: Rejects negative values only, allows 0.
    if (_oldEndDate != null && !_newEndDate.isAfter(_oldEndDate!)) {
      return 'The new end date must be after the current end date (${_formatDate(_oldEndDate!)}).';
    }
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validate();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError), backgroundColor: Colors.red),
      );
      return;
    }

    if (_subscription == null) {
      // Extending is inherently tied to an existing subscription record —
      // without one there's nothing on the backend to extend. Surface
      // this clearly rather than silently failing inside the service call.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't find this subscription's details. Please go back and try again."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final pickupChanged = _pickupName != _originalPickupName || _pickupLat != _originalPickupLat || _pickupLng != _originalPickupLng;
    final dropoffChanged = _dropoffName != _originalDropoffName || _dropoffLat != _originalDropoffLat || _dropoffLng != _originalDropoffLng;
    final timeChanged = _pickupTimeDb != _originalPickupTimeDb;
    final feeChanged = _fee != _originalFee;
    final anyTermsChanged = pickupChanged || dropoffChanged || timeChanged || feeChanged;

    try {
      final controller = context.read<NegotiationViewModel>();
      final newRequestId = await controller.submitExtensionRequest(
        subscription: _subscription!,
        newEndDate: _newEndDate,
        extensionType: anyTermsChanged ? 'renegotiate' : 'date_only',
        overridePickupName: pickupChanged ? _pickupName : null,
        overridePickupLat: pickupChanged ? _pickupLat : null,
        overridePickupLng: pickupChanged ? _pickupLng : null,
        overrideDropoffName: dropoffChanged ? _dropoffName : null,
        overrideDropoffLat: dropoffChanged ? _dropoffLat : null,
        overrideDropoffLng: dropoffChanged ? _dropoffLng : null,
        overridePickupTime: timeChanged ? _pickupTimeDb : null,
        overrideFee: feeChanged ? _fee : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Extension request sent!'), backgroundColor: Colors.green),
      );
      // Hand off to the existing NegotiationScreen so the driver's
      // acceptance can be tracked the same way as any other request —
      // reuses the screen rather than building a second summary view.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => NegotiationScreen(requestId: newRequestId)),
      );
    } on NegotiationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kDefaultNegotiationErrorMessage), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Extend Subscription', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Clearly marks this as an extension, not a brand new
            // negotiation — reuses the same amber "extend" styling
            // NegotiationSummaryCard already uses for its 7-day extend
            // window banner, for visual consistency.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.autorenew, color: Colors.amber.shade900),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _subscription != null
                          ? 'This extends your existing subscription — anything you don\'t change below stays the same as your last agreement.'
                          : 'Starting a fresh extension request — no previous subscription details were found to prefill.',
                      style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            NegotiationFieldRow(
              title: 'Pickup Location',
              value: _pickupName.isEmpty ? 'Not set' : _pickupName,
              isAccepted: true, // renders the compact "value + Edit" card, no propose/accept state applies pre-submission
              isRequestedByMe: false,
              topWidget: (_pickupLat != 0 || _pickupLng != 0)
                  ? RouteMapHeader(label: _pickupName, lat: _pickupLat, lng: _pickupLng)
                  : null,
              onPropose: () => _openLocationPicker(isPickup: true),
              onAccept: () {},
            ),

            NegotiationFieldRow(
              title: 'Dropoff Location',
              value: _dropoffName.isEmpty ? 'Not set' : _dropoffName,
              isAccepted: true,
              isRequestedByMe: false,
              topWidget: (_dropoffLat != 0 || _dropoffLng != 0)
                  ? RouteMapHeader(label: _dropoffName, lat: _dropoffLat, lng: _dropoffLng)
                  : null,
              onPropose: () => _openLocationPicker(isPickup: false),
              onAccept: () {},
            ),

            NegotiationFieldRow(
              title: 'Pickup Time',
              value: _formatAmPm(_pickupTimeDb),
              isAccepted: true,
              isRequestedByMe: false,
              onPropose: _openPickupTimeSheet,
              onAccept: () {},
            ),

            NegotiationFieldRow(
              title: 'Tumpang Fee',
              value: 'RM ${_fee.toStringAsFixed(2)}/day',
              isAccepted: true,
              isRequestedByMe: false,
              onPropose: _openFeeSheet,
              onAccept: () {},
            ),

            NegotiationFieldRow(
              title: 'Subscription Start (unchanged)',
              value: _subscriptionStartDate != null ? _formatDate(_subscriptionStartDate!) : 'Not available',
              isAccepted: true,
              isRequestedByMe: false,
              isReadOnly: true, // start date always carries over — not editable for an extension
              onPropose: () {},
              onAccept: () {},
            ),

            NegotiationFieldRow(
              title: 'New End Date',
              value: _oldEndDate != null
                  ? '${_formatDate(_oldEndDate!)} \u2192 ${_formatDate(_newEndDate)}'
                  : _formatDate(_newEndDate),
              isAccepted: true,
              isRequestedByMe: false,
              onPropose: _pickNewEndDate,
              onAccept: () {},
            ),

            const SizedBox(height: 12),
            BaseButton(
              text: _isSubmitting ? 'Submitting...' : 'Submit Extension Request',
              onPressed: _isSubmitting ? () {} : _submit,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}