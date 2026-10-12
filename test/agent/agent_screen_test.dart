import 'package:finn/agent/agent.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'agent_fakes.dart';

void main() {
  Map<String, Object?> lunch() => {
        'type': 'expense',
        'amount': '450',
        'categoryId': 'cat_food',
        'date': '2026-10-10',
        'paymentMethod': 'upi',
      };

  group('AgentController', () {
    test('is unavailable without a provider (local mode)', () async {
      final env = await TestEnv.create();
      final container = env.container();
      addTearDown(container.dispose);
      expect(container.read(agentControllerProvider).available, isFalse);
      await container.read(agentControllerProvider.notifier).send('hi');
      expect(container.read(agentControllerProvider).entries, isEmpty);
    });

    test('ignores a second submission while a turn is running and returns to idle', () async {
      final env = await TestEnv.create();
      final provider = ScriptedProvider([
        callsTools([toolCall('record_transaction', lunch())]),
        says('I will record ₹450 for lunch.'),
      ]);
      final container = ProviderContainer(overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)]);
      addTearDown(container.dispose);
      final controller = container.read(agentControllerProvider.notifier);
      final before = (await env.snapshot()).transactions.length;

      final turn = controller.send('Spent 450 on lunch');
      await controller.send('Spent 450 on lunch'); // duplicate tap
      await pumpEventQueue();
      final waiting = container.read(agentControllerProvider);
      expect(waiting.status, AgentStatus.awaitingApproval);
      expect(waiting.proposals, hasLength(1));

      controller.approve({waiting.proposals.single.id});
      controller.approve({waiting.proposals.single.id}); // double tap on Approve
      await turn;

      final done = container.read(agentControllerProvider);
      expect(done.status, AgentStatus.idle);
      expect(done.entries.whereType<UserChatEntry>(), hasLength(1));
      final reply = done.entries.last as AgentChatEntry;
      expect(reply.text, 'Done: Spent ₹450.');
      expect(reply.actions.single.status, ActionResultStatus.completed);
      expect((await env.snapshot()).transactions.length, before + 1);
      expect(provider.requests, hasLength(2));
    });

    test('stop while waiting for approval writes nothing and ends idle', () async {
      final env = await TestEnv.create();
      final provider = ScriptedProvider([
        callsTools([toolCall('record_transaction', lunch())]),
        says('I will record ₹450 for lunch.'),
      ]);
      final container = ProviderContainer(overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)]);
      addTearDown(container.dispose);
      final controller = container.read(agentControllerProvider.notifier);
      final before = (await env.snapshot()).transactions.length;

      final turn = controller.send('Spent 450 on lunch');
      await pumpEventQueue();
      controller.stop();
      await turn;

      final state = container.read(agentControllerProvider);
      expect(state.status, AgentStatus.idle);
      expect((state.entries.last as AgentChatEntry).end, AgentTurnEnd.cancelled);
      expect((await env.snapshot()).transactions.length, before);
    });

    test('a failed turn offers a retry and start over clears the chat', () async {
      final env = await TestEnv.create();
      final provider = ScriptedProvider([
        const LlmException(LlmErrorKind.rejected, 'The assistant could not process this request.'),
      ]);
      final container = ProviderContainer(overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)]);
      addTearDown(container.dispose);
      final controller = container.read(agentControllerProvider.notifier);
      await controller.send('hello');
      final failed = container.read(agentControllerProvider).entries.last as AgentChatEntry;
      expect(failed.end, AgentTurnEnd.failed);
      expect(failed.retryText, isNull, reason: 'non-retryable errors offer no retry');
      controller.startOver();
      expect(container.read(agentControllerProvider).entries, isEmpty);
    });
  });

  group('AgentScreen', () {
    testWidgets('shows the unavailable state in local mode', (tester) async {
      final env = await TestEnv.create();
      await env.pumpWidget(tester, const AgentScreen());
      expect(find.textContaining(RegExp('assistant unavailable', caseSensitive: false)), findsOneWidget);
    });

    testWidgets('send → review card → approve → saved outcome', (tester) async {
      final env = await TestEnv.create();
      final provider = ScriptedProvider([
        callsTools([toolCall('record_transaction', lunch())]),
        says('I will record ₹450 for lunch.'),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)],
        child: MaterialApp(
          theme: FinnTheme.light(),
          home: const MotionScope(reduceMotion: true, child: AgentScreen()),
        ),
      ));
      await tester.pump();
      expect(find.text('Tell FiNN what happened'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Spent 450 on lunch');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Review this change'), findsOneWidget);
      expect(find.text('TRANSACTIONS · NEW'), findsOneWidget);
      expect(find.text('I will record ₹450 for lunch.'), findsOneWidget);
      expect(find.textContaining('450'), findsWidgets);
      expect(find.byTooltip('Stop'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Done: Spent ₹450.'), findsOneWidget);
      expect(find.text('Change saved'), findsOneWidget);
      expect(find.text('SAVED'), findsOneWidget);
      expect(find.byTooltip('Send'), findsOneWidget);
    });
  });
}
