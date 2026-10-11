import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/design_system.dart';
import '../domain/auth_session.dart';

/// Six digit boxes (3 – 3) backed by one invisible text field, so typing,
/// paste and SMS / email autofill all work as in a normal input.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.controller,
    this.focusNode,
    this.enabled = true,
    this.hasError = false,
    this.autofocus = true,
    this.onChanged,
    this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool hasError;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  /// Called once all [otpLength] digits are entered.
  final ValueChanged<String>? onCompleted;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _ownFocus?.dispose();
    super.dispose();
  }

  void _changed(String value) {
    widget.onChanged?.call(value);
    if (value.length == otpLength) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = Space.x2;
        const separator = 24.0;
        final boxWidth = math.min(48.0, (constraints.maxWidth - gap * (otpLength - 2) - separator) / otpLength);
        final boxHeight = math.max(48.0, boxWidth * 1.15);
        return SizedBox(
          height: boxHeight,
          child: Stack(
            children: [
              ExcludeSemantics(
                child: ListenableBuilder(
                  listenable: Listenable.merge([widget.controller, _focus]),
                  builder: (context, _) {
                    final text = widget.controller.text;
                    Widget box(int i) => _DigitBox(
                          digit: i < text.length ? text[i] : null,
                          width: boxWidth,
                          height: boxHeight,
                          active: widget.enabled && _focus.hasFocus && i == math.min(text.length, otpLength - 1),
                          hasError: widget.hasError,
                          enabled: widget.enabled,
                        );
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < otpLength; i++) ...[
                          if (i == otpLength ~/ 2)
                            SizedBox(
                              width: separator,
                              child: Center(child: Container(width: 8, height: 2, color: c.borderStrong)),
                            )
                          else if (i > 0)
                            const SizedBox(width: gap),
                          box(i),
                        ],
                      ],
                    );
                  },
                ),
              ),
              Positioned.fill(
                child: TextField(
                  key: const ValueKey('otp-field'),
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(otpLength),
                  ],
                  showCursor: false,
                  style: const TextStyle(color: Colors.transparent, fontSize: 1),
                  decoration: const InputDecoration.collapsed(hintText: null).copyWith(
                    semanticCounterText: '',
                    labelText: 'Verification code',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    labelStyle: const TextStyle(color: Colors.transparent, fontSize: 1),
                  ),
                  onChanged: _changed,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({
    required this.digit,
    required this.width,
    required this.height,
    required this.active,
    required this.hasError,
    required this.enabled,
  });

  final String? digit;
  final double width;
  final double height;
  final bool active;
  final bool hasError;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final Color borderColor;
    if (hasError) {
      borderColor = c.negative;
    } else if (active) {
      borderColor = c.primary;
    } else {
      borderColor = digit == null ? c.border : c.borderStrong;
    }
    return AnimatedContainer(
      duration: context.motion.fast,
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? c.surface : c.surfaceMuted,
        borderRadius: Radii.rLg,
        border: Border.all(color: borderColor, width: active || hasError ? 2 : 1),
      ),
      child: Text(digit ?? '', style: t.title.copyWith(fontSize: 22, fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}
