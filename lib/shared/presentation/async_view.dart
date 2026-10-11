import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/data_providers.dart';
import '../../core/result/result.dart';
import '../../design_system/design_system.dart';

/// Standard loading / error / data switch for `AsyncValue`s.
///
/// Keeps previous data visible while refreshing (no flicker), shows the
/// supplied skeleton while loading (matching final layout to avoid shifts),
/// and an [ErrorState] with retry on failure.
class AsyncView<T> extends ConsumerWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.loading,
    this.errorTitle = 'Could not load your data',
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loading;
  final String errorTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (value.hasValue) return builder(context, value.requireValue);
    if (value.hasError) {
      final e = value.error;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.x6),
          child: ErrorState(
            title: errorTitle,
            message: e is AppFailure ? e.message : 'Please check your connection and try again.',
            onRetry: () => refreshFinanceData(ref),
          ),
        ),
      );
    }
    return loading ?? const SkeletonPulse(child: ListSkeleton(count: 6));
  }
}
