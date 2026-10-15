import 'package:flutter/material.dart';

import '../../../../kit/kit.dart';
import '../../application/account_support.dart';

/// Optional "channel" of a payment (UPI, NEFT, ATM …): suggestion chips plus
/// an "Other…" chip that reveals a free-text box. Tapping the selected chip
/// clears it. [onChanged] receives the cleaned value, or null when empty.
/// Validates with [channelError]; [errorText] (e.g. from the server) wins.
class ChannelField extends StatefulWidget {
  const ChannelField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Channel (optional)',
    this.errorText,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String? label;
  final String? errorText;
  final bool enabled;

  @override
  State<ChannelField> createState() => _ChannelFieldState();
}

class _ChannelFieldState extends State<ChannelField> {
  static const _other = '\u0000other';
  final _text = TextEditingController();
  late bool _otherOpen;

  bool _isCustom(String? v) =>
      v != null && v.isNotEmpty && !channelSuggestions.contains(v);

  @override
  void initState() {
    super.initState();
    _otherOpen = _isCustom(widget.value);
    if (_otherOpen) _text.text = widget.value!;
  }

  @override
  void didUpdateWidget(ChannelField old) {
    super.didUpdateWidget(old);
    final v = widget.value;
    if (v != old.value && v != cleanChannel(_text.text)) {
      // Changed from outside.
      _otherOpen = _isCustom(v);
      _text.text = _otherOpen ? v! : '';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick(String v) {
    if (v == _other) {
      setState(() => _otherOpen = true);
      widget.onChanged(cleanChannel(_text.text));
      return;
    }
    setState(() {
      _otherOpen = false;
      _text.clear();
    });
    widget.onChanged(v);
  }

  void _clear() {
    setState(() {
      _otherOpen = false;
      _text.clear();
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final selected = _otherOpen
        ? _other
        : (v != null && channelSuggestions.contains(v) ? v : null);
    final live = _otherOpen ? _text.text : v;
    final error = widget.errorText ?? channelError(live);
    return LedgerField(
      label: widget.label,
      errorText: _otherOpen ? null : error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerChoiceChips<String>(
            enabled: widget.enabled,
            selected: selected,
            onChanged: _pick,
            onCleared: _clear,
            options: [
              for (final s in channelSuggestions)
                LedgerOption(s, s, key: ValueKey('channel-$s')),
              const LedgerOption(
                _other,
                'Other…',
                key: ValueKey('channel-other'),
              ),
            ],
          ),
          if (_otherOpen) ...[
            const SizedBox(height: Sp.sm),
            LedgerTextField(
              controller: _text,
              hint: 'e.g. Wallet, DD',
              errorText: error,
              enabled: widget.enabled,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (t) {
                setState(() {});
                widget.onChanged(cleanChannel(t));
              },
            ),
          ],
        ],
      ),
    );
  }
}
