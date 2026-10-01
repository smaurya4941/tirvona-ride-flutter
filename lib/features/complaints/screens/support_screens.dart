import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/session_controller.dart';
import '../../rides/domain/ride_formatters.dart';
import '../models/complaint_models.dart';
import '../repository/complaint_repository.dart';

bool _isDriver(WidgetRef ref) =>
    ref.read(sessionControllerProvider).user?.role == UserRole.driver;

String _date(DateTime at) => '${RideFormat.date(at)} · ${RideFormat.time(at)}';

/// Help & support: the user's complaints and their status.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDriver = _isDriver(ref);
    final pageAsync = ref.watch(complaintsProvider);
    final page = pageAsync.value;

    final Widget body;
    if (page == null) {
      body = pageAsync.hasError
          ? LoadErrorView(
              error: pageAsync.error!,
              onRetry: () => ref.invalidate(complaintsProvider),
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: () => ref.refresh(complaintsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Card(
              color: AppColors.bhagwaLight,
              child: ListTile(
                leading: const Icon(
                  Icons.support_agent,
                  color: AppColors.bhagwa,
                ),
                title: const Text('Need help with a ride?'),
                subtitle: Text(
                  isDriver
                      ? 'Open the ride from Rides and tap "Report an issue", or '
                            'report a general problem below.'
                      : 'Open the ride from Your rides and tap "Report an '
                            'issue", or report a general problem below.',
                ),
              ),
            ),
            if (page.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 48,
                      color: AppColors.outlineVariant,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No reported issues',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              )
            else ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text(
                  'Your reports',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              for (final complaint in page.items)
                Card(
                  child: ListTile(
                    leading: Icon(
                      complaint.category.icon,
                      color: AppColors.midnightBlue,
                    ),
                    title: Text(
                      complaint.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${complaint.ticketCode}'
                      '${complaint.rideCode == null ? '' : ' · Ride ${complaint.rideCode}'}'
                      '\n${_date(complaint.createdAt)}',
                    ),
                    isThreeLine: true,
                    trailing: ComplaintStatusChip(status: complaint.status),
                    onTap: () => context.push(
                      AppRoutes.complaintFor(isDriver, complaint.id),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(AppRoutes.newComplaintFor(isDriver));
          ref.invalidate(complaintsProvider);
        },
        icon: const Icon(Icons.edit_note),
        label: const Text('Report an issue'),
      ),
    );
  }
}

class ComplaintStatusChip extends StatelessWidget {
  const ComplaintStatusChip({super.key, required this.status});

  final ComplaintStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = status.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colors.foreground,
        ),
      ),
    );
  }
}

/// Report an issue, optionally about one ride (from the ride's details).
class ComplaintFormScreen extends ConsumerStatefulWidget {
  const ComplaintFormScreen({super.key, this.rideId});

  final String? rideId;

  @override
  ConsumerState<ComplaintFormScreen> createState() =>
      _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends ConsumerState<ComplaintFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  ComplaintCategory? _category;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_category == null) {
      setState(() => _error = 'Choose what the issue is about.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final complaint = await ref
          .read(complaintRepositoryProvider)
          .create(
            category: _category!,
            subject: _subject.text.trim().isEmpty
                ? _category!.label
                : _subject.text.trim(),
            description: _description.text.trim(),
            rideId: widget.rideId,
          );
      ref.invalidate(complaintsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reported · ${complaint.ticketCode}. We will update you here.',
          ),
        ),
      );
      context.pushReplacement(
        AppRoutes.complaintFor(_isDriver(ref), complaint.id),
      );
    } on ApiException catch (error) {
      final existing = (error.data as Map<String, dynamic>?)?['id'] as String?;
      if (error.code == 'COMPLAINT_ALREADY_OPEN' &&
          existing != null &&
          mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        context.pushReplacement(
          AppRoutes.complaintFor(_isDriver(ref), existing),
        );
        return;
      }
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = _isDriver(ref);
    final hasRide = widget.rideId != null;
    final categories = ComplaintCategory.values
        .where((category) => category.availableTo(isDriver: isDriver))
        .where((category) => hasRide || !category.needsRide)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Report an issue')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (hasRide)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.local_taxi_outlined),
                    title: Text('About this ride'),
                    subtitle: Text(
                      'The ride details are attached for our team.',
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'What is it about?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in categories)
                    ChoiceChip(
                      avatar: Icon(category.icon, size: 18),
                      label: Text(category.label),
                      selected: _category == category,
                      onSelected: (_) => setState(() {
                        _category = category;
                        _error = null;
                      }),
                    ),
                ],
              ),
              if (!hasRide)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'For a problem with a specific trip, report it from that '
                    'ride\'s details so we can see what happened.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              if (_category == ComplaintCategory.safety)
                const Card(
                  color: Color(0xFFFEE2E2),
                  margin: EdgeInsets.only(top: 12),
                  child: ListTile(
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    title: Text('In danger right now?'),
                    subtitle: Text('Call 112, or use SOS on the ride screen.'),
                  ),
                ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _subject,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Short summary (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _description,
                maxLength: 2000,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Describe what happened',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 10
                    ? 'Please add a few more details (at least 10 characters)'
                    : null,
              ),
              const SizedBox(height: 8),
              ErrorBanner(message: _error),
              LoadingFilledButton(
                label: 'Submit',
                icon: Icons.send,
                isLoading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One complaint: status, what was reported, and the team's resolution.
class ComplaintDetailScreen extends ConsumerWidget {
  const ComplaintDetailScreen({super.key, required this.complaintId});

  final String complaintId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complaintAsync = ref.watch(complaintProvider(complaintId));
    final complaint = complaintAsync.value;

    return Scaffold(
      appBar: AppBar(title: Text(complaint?.ticketCode ?? 'Complaint')),
      body: complaint == null
          ? complaintAsync.hasError
                ? LoadErrorView(
                    error: complaintAsync.error!,
                    onRetry: () =>
                        ref.invalidate(complaintProvider(complaintId)),
                  )
                : const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(complaintProvider(complaintId).future),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                complaint.category.icon,
                                color: AppColors.midnightBlue,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  complaint.category.label,
                                  style: const TextStyle(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              ComplaintStatusChip(status: complaint.status),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            complaint.subject,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(complaint.description),
                          const SizedBox(height: 12),
                          Text(
                            [
                              'Reported ${_date(complaint.createdAt)}',
                              if (complaint.rideCode != null)
                                'Ride ${complaint.rideCode}',
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (complaint.resolution != null)
                    Card(
                      color: const Color(0xFFDCFCE7),
                      child: ListTile(
                        leading: const Icon(
                          Icons.support_agent,
                          color: Color(0xFF166534),
                        ),
                        title: const Text('Response from Tirvona support'),
                        subtitle: Text(complaint.resolution!),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      'Progress',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final step in complaint.timeline)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.radio_button_checked,
                        size: 18,
                        color: AppColors.bhagwa,
                      ),
                      title: Text(step.status.label),
                      subtitle: Text(_date(step.at)),
                    ),
                ],
              ),
            ),
    );
  }
}
