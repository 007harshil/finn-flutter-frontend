import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/result/result.dart';
import '../../../kit/kit.dart';
import '../../reports/agent_reports.dart';

/// Opens the sheet that reports an assistant reply.
Future<void> showReportReplySheet(BuildContext context, {required String reply, String? request}) {
  return showFinnSheet<void>(
    context,
    builder: (_) => ReportReplySheet(reply: reply, request: request),
  );
}

/// Pick a reason, add an optional note, send. The report reaches the FiNN
/// team; nothing in the user's records changes.
class ReportReplySheet extends ConsumerStatefulWidget {
  const ReportReplySheet({super.key, required this.reply, this.request});

  final String reply;
  final String? request;

  @override
  ConsumerState<ReportReplySheet> createState() => _ReportReplySheetState();
}

class _ReportReplySheetState extends ConsumerState<ReportReplySheet> {
  final _note = TextEditingController();
  AgentReportReason? _reason;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(agentReportsProvider)
          .report(reason: reason, reply: widget.reply, request: widget.request, note: _note.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      FinnToast.success(context, 'Report sent', subtitle: 'Thanks. The FiNN team will review it.');
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() => _sending = false);
      FinnToast.error(context, 'Could not send the report', subtitle: f.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      FinnToast.error(context, 'Could not send the report', subtitle: 'Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinnSheetScaffold(
      title: 'Report this reply',
      description: 'Tell us what is wrong with this assistant reply. It is sent to the FiNN team for review.',
      footer: LedgerButton(
        key: const ValueKey('send-report'),
        label: 'Send report',
        icon: LucideIcons.flag,
        expand: true,
        loading: _sending,
        onPressed: _reason == null || _sending ? null : _send,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerPanel(
            children: [
              for (final r in AgentReportReason.values)
                LedgerOptionRow(
                  key: ValueKey('report-${r.name}'),
                  title: r.label,
                  selected: _reason == r,
                  onTap: () => setState(() => _reason = r),
                ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          LedgerTextField(
            controller: _note,
            label: 'Details (optional)',
            hint: 'What should it have said?',
            maxLines: 3,
            minLines: 2,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}
