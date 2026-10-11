import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../actions/action.dart';
import '../../actions/action_plan.dart';
import '../../actions/action_registry.dart';
import '../../actions/audit_log.dart';
import '../../actions/dispatcher.dart';
import 'action_catalog.dart';
import 'core_providers.dart';

final auditLogProvider = Provider<AuditLog>((ref) => AuditLog());

final actionEnvironmentProvider = Provider<ActionEnvironment>((ref) {
  final repos = ref.watch(financeRepositoriesProvider);
  final clock = ref.watch(clockProvider);
  return ActionEnvironment(
    repos: repos,
    clock: clock,
    ids: ref.watch(idGeneratorProvider),
    loadSnapshot: () => repos.loadSnapshot(clock, monthStartDay: ref.read(settingsProvider).monthStartDay),
  );
});

/// The single entry point for every financial operation.
final actionDispatcherProvider = Provider<OperationDispatcher>((ref) => OperationDispatcher(
      environment: ref.watch(actionEnvironmentProvider),
      audit: ref.watch(auditLogProvider),
    ));

/// Discoverable catalogue of operations for future channels (agent, voice).
final actionRegistryProvider = Provider<ActionRegistry>((ref) => ActionRegistry(allActions));

final planExecutorProvider = Provider<PlanExecutor>((ref) => PlanExecutor(
      registry: ref.watch(actionRegistryProvider),
      dispatcher: ref.watch(actionDispatcherProvider),
    ));

final auditEntriesProvider = StreamProvider<List<AuditEntry>>((ref) => ref.watch(auditLogProvider).watch());
