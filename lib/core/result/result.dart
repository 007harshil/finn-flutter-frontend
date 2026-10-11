import 'package:flutter/foundation.dart';

/// Categories of failure that every layer understands. UI maps them to
/// recovery actions; a future API client maps HTTP errors onto them.
enum FailureCode {
  validation,
  notFound,
  conflict,
  staleData,
  insufficientFunds,
  duplicate,
  ambiguous,
  confirmationRequired,
  notPermitted,
  unavailable,
  storage,
  unknown,
}

@immutable
class AppFailure implements Exception {
  const AppFailure(
    this.code,
    this.message, {
    this.fieldErrors = const {},
    this.cause,
    this.retryable = false,
  });

  const AppFailure.validation(String message, {Map<String, String> fields = const {}})
      : this(FailureCode.validation, message, fieldErrors: fields);

  const AppFailure.notFound(String message) : this(FailureCode.notFound, message);

  const AppFailure.conflict(String message) : this(FailureCode.conflict, message);

  const AppFailure.unavailable(String message)
      : this(FailureCode.unavailable, message, retryable: true);

  final FailureCode code;

  /// Human-readable, non-technical explanation suitable for the UI.
  final String message;

  /// Field-level validation messages keyed by input field name.
  final Map<String, String> fieldErrors;

  final Object? cause;

  /// Whether retrying the same request could succeed.
  final bool retryable;

  @override
  String toString() => 'AppFailure($code, $message)';
}

/// Outcome of an operation that can fail in an expected way.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(AppFailure failure) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  AppFailure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };

  R fold<R>(R Function(T value) onOk, R Function(AppFailure failure) onErr) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => Result<R>.ok(transform(value)),
        Err<T>(:final failure) => Result<R>.err(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final AppFailure failure;
}
