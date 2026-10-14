import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/data_providers.dart';
import '../../core/result/result.dart';
import '../../design_system/design_system.dart';
import '../../design_system/luxe/luxe.dart';

/// Luxe loading / error / data switch for `AsyncValue`s: keeps previous
/// data while refreshing, cross-fades from the skeleton to the content,
/// and offers a retry on failure.
class LuxeAsync<T> extends ConsumerWidget {
  const LuxeAsync({
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
    final Widget child;
    if (value.hasValue) {
      child = KeyedSubtree(key: const ValueKey('data'), child: builder(context, value.requireValue));
    } else if (value.hasError) {
      final e = value.error;
      child = Center(
        key: const ValueKey('error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LuxeError(
            title: errorTitle,
            message: e is AppFailure ? e.message : null,
            onRetry: () => refreshFinanceData(ref),
          ),
        ),
      );
    } else {
      child = KeyedSubtree(key: const ValueKey('loading'), child: loading ?? const LuxePageSkeleton());
    }
    return AnimatedSwitcher(
      duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
      switchInCurve: LuxeCurves.arrive,
      switchOutCurve: LuxeCurves.leave,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      child: child,
    );
  }
}
