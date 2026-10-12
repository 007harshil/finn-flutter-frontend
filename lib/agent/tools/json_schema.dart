import '../../actions/action.dart';

/// Builds JSON Schema objects for tool parameters.
///
/// Action tools derive their schema from the action's [ActionFieldSpec]s, so
/// the agent and the forms share one source of truth for what an operation
/// accepts. The schema only guides the model; [FinancialAction.decode] and
/// `prepare` remain the authoritative validation.
abstract final class JsonSchema {
  static Map<String, Object?> object(
    Map<String, Map<String, Object?>> properties, {
    List<String> required = const [],
  }) => {'type': 'object', 'properties': properties, if (required.isNotEmpty) 'required': required};

  static Map<String, Object?> string(String description, {List<String>? values, String? pattern, int? maxLength}) => {
    'type': 'string',
    'description': description,
    'enum': ?values,
    'pattern': ?pattern,
    'maxLength': ?maxLength,
  };

  static Map<String, Object?> integer(String description, {int? minimum, int? maximum}) => {
    'type': 'integer',
    'description': description,
    'minimum': ?minimum,
    'maximum': ?maximum,
  };

  static Map<String, Object?> boolean(String description) => {'type': 'boolean', 'description': description};

  // Formats (rupee strings, yyyy-MM-dd, ids from lookups) are stated once in
  // the instructions rather than in every field, to keep requests small.
  static Map<String, Object?> money(String description) => string(description);

  static Map<String, Object?> date(String description) => string(description);

  /// Schema for one field of an action.
  static Map<String, Object?> forField(ActionFieldSpec f) => switch (f.kind) {
    FieldKind.money => money(f.description),
    FieldKind.date => date(f.description),
    FieldKind.integer || FieldKind.rate => integer(f.description),
    FieldKind.boolean => boolean(f.description),
    FieldKind.enumeration => string(f.description, values: f.allowedValues),
    FieldKind.id => string(f.description),
    FieldKind.string => string(f.description),
  };

  /// Parameters schema for an action's descriptor. [overrides] replaces the
  /// schema of individual fields (for fields whose spec is too coarse, such
  /// as lists).
  /// [exclude] removes optional fields the caller must not set.
  static Map<String, Object?> forAction(
    ActionDescriptor d, {
    Map<String, Map<String, Object?>> overrides = const {},
    Set<String> exclude = const {},
  }) {
    final fields = d.fields.where((f) => !exclude.contains(f.name) || f.required);
    return object(
      {for (final f in fields) f.name: overrides[f.name] ?? forField(f)},
      required: [
        for (final f in fields)
          if (f.required) f.name,
      ],
    );
  }

  /// Drops every object property [schema] does not declare, recursively.
  /// Model output is untrusted: undeclared fields must never reach an
  /// action's decoder.
  static Object? prune(Object? value, Map<String, Object?> schema) {
    if (value is Map && schema['type'] == 'object') {
      final props = schema['properties'];
      if (props is! Map) return <String, Object?>{};
      return <String, Object?>{
        for (final e in value.entries)
          if (props[e.key] is Map) e.key.toString(): prune(e.value, Map<String, Object?>.from(props[e.key] as Map)),
      };
    }
    if (value is List && schema['type'] == 'array') {
      final items = schema['items'];
      if (items is! Map) return value;
      return [for (final v in value) prune(v, Map<String, Object?>.from(items))];
    }
    return value;
  }
}
