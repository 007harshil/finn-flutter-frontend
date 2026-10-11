import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/ids/id_generator.dart';
import '../core/money/money.dart';
import '../core/result/result.dart';
import '../core/time/clock.dart';
import '../domain/finance_repositories.dart';
import '../finance/finance_snapshot.dart';

/// How consequential an operation is. Drives confirmation requirements.
enum ActionRisk {
  /// Reversible edits with no cash effect (rename, change a limit).
  low,

  /// Moves or allocates money, settles obligations, records repayments,
  /// or deletes financial records. Always needs explicit confirmation when
  /// initiated by a non-UI channel; UI forms show a review step.
  consequential,
}

/// The channel an operation was initiated from.
enum ActionChannel { ui, agent, voice, import, system }

enum FieldKind { string, money, date, integer, boolean, enumeration, id, rate }

/// Machine-readable description of one input field, so a future agent can
/// discover what an operation needs and build valid input.
@immutable
class ActionFieldSpec {
  const ActionFieldSpec(this.name, this.kind, this.description, {this.required = true, this.allowedValues});
  final String name;
  final FieldKind kind;
  final String description;
  final bool required;
  final List<String>? allowedValues;

  Map<String, Object?> toJson() => {
        'name': name,
        'kind': kind.name,
        'description': description,
        'required': required,
        if (allowedValues != null) 'allowedValues': allowedValues,
      };
}

@immutable
class ActionDescriptor {
  const ActionDescriptor({
    required this.id,
    required this.module,
    required this.title,
    required this.description,
    required this.risk,
    required this.fields,
    this.reversible = true,
    this.movesMoney = false,
  });

  /// Stable identifier, e.g. `transactions.create`.
  final String id;
  final String module;
  final String title;
  final String description;
  final ActionRisk risk;
  final List<ActionFieldSpec> fields;
  final bool reversible;

  /// Whether execution creates or changes a cash movement.
  final bool movesMoney;

  bool get isConsequential => risk == ActionRisk.consequential;

  Map<String, Object?> toJson() => {
        'id': id,
        'module': module,
        'title': title,
        'description': description,
        'risk': risk.name,
        'reversible': reversible,
        'movesMoney': movesMoney,
        'fields': fields.map((f) => f.toJson()).toList(),
      };
}

/// Typed, serialisable input for an action.
abstract class ActionInput {
  const ActionInput();
  Map<String, Object?> toJson();
}

@immutable
class PreviewLine {
  const PreviewLine(this.label, this.value, {this.emphasis = false});
  final String label;
  final String value;
  final bool emphasis;
}

/// Human-readable description of exactly what will happen.
@immutable
class ActionPreview {
  const ActionPreview({
    required this.actionId,
    required this.title,
    required this.summary,
    required this.lines,
    required this.fingerprint,
    required this.requiresConfirmation,
    this.warnings = const [],
  });

  final String actionId;
  final String title;

  /// One sentence, e.g. "Record ₹12,602 EMI for Car loan".
  final String summary;
  final List<PreviewLine> lines;
  final List<String> warnings;

  /// Hash of the action id + input, optionally followed by `.` and a hash
  /// of the state the preview was computed from (see
  /// [FinancialAction.preview]'s `basis`). A confirmation is only valid for
  /// the exact input *and* record state that was previewed, so an approval
  /// cannot be replayed after the input was altered or the target record
  /// changed (stale approval).
  final String fingerprint;
  final bool requiresConfirmation;
}

/// Explicit user approval of a previewed operation.
@immutable
class ActionConfirmation {
  const ActionConfirmation(this.fingerprint, {this.confirmedBy = 'user'});
  final String fingerprint;
  final String confirmedBy;
}

/// Everything an action needs to run, independent of Flutter widgets.
class ActionEnvironment {
  ActionEnvironment({
    required this.repos,
    required this.clock,
    required this.ids,
    required this.loadSnapshot,
  });

  final FinanceRepositories repos;
  final Clock clock;
  final IdGenerator ids;

  /// Loads a fresh, consistent snapshot for validation.
  final Future<FinanceSnapshot> Function() loadSnapshot;
}

/// Prepared action: validated input plus its preview, ready to execute.
@immutable
class Prepared {
  const Prepared(this.preview);
  final ActionPreview preview;
}

/// A financial operation with a typed entry point usable from forms,
/// agents, voice, or imports alike.
abstract class FinancialAction<I extends ActionInput, O> {
  const FinancialAction();

  ActionDescriptor get descriptor;

  /// Decodes untrusted JSON (e.g. from an agent) into typed input.
  /// Throws [AppFailure] (validation) on malformed input.
  I decode(Map<String, Object?> json);

  /// Validates [input] against [snapshot] and describes the effect.
  /// Must not mutate anything.
  Result<ActionPreview> prepare(I input, FinanceSnapshot snapshot, ActionEnvironment env);

  /// Performs the operation. Called only after [prepare] succeeded on a
  /// fresh snapshot.
  Future<Result<O>> execute(I input, FinanceSnapshot snapshot, ActionEnvironment env);

  /// Helper for subclasses to build a preview with the right fingerprint.
  ///
  /// [basis] is a small JSON-able description of the record state the
  /// preview depends on (e.g. version and outstanding amount of the record
  /// being settled). When it changes between approval and execution the
  /// fingerprint changes too, and the dispatcher asks for confirmation
  /// again instead of executing a stale approval.
  ActionPreview preview(
    I input, {
    required String title,
    required String summary,
    List<PreviewLine> lines = const [],
    List<String> warnings = const [],
    bool? requiresConfirmation,
    Object? basis,
  }) =>
      ActionPreview(
        actionId: descriptor.id,
        title: title,
        summary: summary,
        lines: lines,
        warnings: warnings,
        fingerprint: previewFingerprintOf(descriptor.id, input, basis: basis),
        requiresConfirmation: requiresConfirmation ?? descriptor.isConsequential,
      );
}

/// Stable FNV-1a hash of the action id and canonical JSON input. Identifies
/// the *request* (used for idempotency).
String fingerprintOf(String actionId, ActionInput input) =>
    fnv1a64(jsonEncode(_canonical({'action': actionId, 'input': input.toJson()})));

/// Fingerprint of a preview: the request fingerprint, plus `.<hash>` of the
/// record state ([basis]) when the preview depends on one.
String previewFingerprintOf(String actionId, ActionInput input, {Object? basis}) {
  final request = fingerprintOf(actionId, input);
  if (basis == null) return request;
  return '$request.${fnv1a64(jsonEncode(_canonical(basis)))}';
}

/// Whether [previewFingerprint] was produced for the request [requestFingerprint]
/// (regardless of the record state it was computed from).
bool fingerprintMatchesRequest(String previewFingerprint, String requestFingerprint) =>
    previewFingerprint == requestFingerprint || previewFingerprint.startsWith('$requestFingerprint.');

/// 64-bit FNV-1a as lowercase hex (no leading zeros).
///
/// Kept as two 32-bit halves with plain arithmetic so every intermediate stays
/// below 2^53: web ints are JS doubles and cannot hold 64-bit values, and
/// fingerprints must be identical on every platform.
String fnv1a64(String canonical) {
  const word = 0x100000000;
  // Offset basis 0xcbf29ce484222325.
  var hi = 0xcbf29ce4;
  var lo = 0x84222325;
  for (final unit in utf8.encode(canonical)) {
    final low8 = lo % 256;
    lo = lo - low8 + (low8 ^ unit);
    // hash * 0x100000001b3 == hash * 0x1b3 + (hash << 40)  (mod 2^64)
    final loProduct = lo * 0x1b3;
    final newHi = (hi * 0x1b3 + loProduct ~/ word + (lo % 0x1000000) * 256) % word;
    lo = loProduct % word;
    hi = newHi;
  }
  if (hi == 0) return lo.toRadixString(16);
  return '${hi.toRadixString(16)}${lo.toRadixString(16).padLeft(8, '0')}';
}

Object? _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canonical(v[k])};
  }
  if (v is List) return v.map(_canonical).toList();
  return v;
}

/// Helpers for decoding agent-provided JSON with clear validation errors.
abstract final class In {
  static Never _bad(String field, String expected) =>
      throw AppFailure.validation('Invalid "$field": expected $expected.', fields: {field: 'Expected $expected'});

  static String str(Map<String, Object?> j, String f) {
    final v = j[f];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    _bad(f, 'a non-empty string');
  }

  static String? strOpt(Map<String, Object?> j, String f) {
    final v = j[f];
    if (v == null) return null;
    if (v is String) return v.trim().isEmpty ? null : v.trim();
    _bad(f, 'a string');
  }

  static int integer(Map<String, Object?> j, String f) {
    final v = j[f];
    if (v is num && v == v.roundToDouble()) return v.toInt();
    _bad(f, 'an integer');
  }

  static int? intOpt(Map<String, Object?> j, String f) => j[f] == null ? null : integer(j, f);

  static bool boolean(Map<String, Object?> j, String f, {bool? fallback}) {
    final v = j[f];
    if (v is bool) return v;
    if (v == null && fallback != null) return fallback;
    _bad(f, 'true or false');
  }

  static T enumeration<T extends Enum>(Map<String, Object?> j, String f, List<T> values) {
    final v = j[f];
    for (final e in values) {
      if (e.name == v) return e;
    }
    _bad(f, 'one of ${values.map((e) => e.name).join(', ')}');
  }

  static T? enumOpt<T extends Enum>(Map<String, Object?> j, String f, List<T> values) =>
      j[f] == null ? null : enumeration(j, f, values);

  /// Money as rupees: a number (`1250.5`) or a string (`"1,250.50"`).
  static Money money(Map<String, Object?> j, String f) {
    final v = j[f];
    final parsed = v is num ? Money.tryParse(v.toString()) : (v is String ? Money.tryParse(v) : null);
    if (parsed == null) _bad(f, 'an amount in rupees with at most 2 decimals');
    return parsed;
  }

  static Money? moneyOpt(Map<String, Object?> j, String f) => j[f] == null ? null : money(j, f);

  /// Calendar date as `yyyy-MM-dd`.
  static DateTime date(Map<String, Object?> j, String f) {
    final v = j[f];
    if (v is String) {
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
      if (m != null) {
        final d = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
        if (d.month == int.parse(m.group(2)!)) return d;
      }
    }
    _bad(f, 'a date formatted yyyy-MM-dd');
  }

  static DateTime? dateOpt(Map<String, Object?> j, String f) => j[f] == null ? null : date(j, f);
}

/// Encoding helpers for [ActionInput.toJson].
abstract final class Out {
  static String money(Money m) => m.toDecimalString();
  static String? moneyOpt(Money? m) => m?.toDecimalString();
  static String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String? dateOpt(DateTime? d) => d == null ? null : date(d);
}
