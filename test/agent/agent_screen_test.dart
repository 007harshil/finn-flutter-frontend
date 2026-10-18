import 'dart:async';

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
  Map<String, Object?> lunch() => {'op': 'expense', 'amount': 450, 'category': 'Food & Dining', 'note': 'lunch', 'account': 'Cash'};

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
      final provider = ScriptedProvider([plan([lunch()])]);
      final container = ProviderContainer(
        overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)],
      );
      addTearDown(container.dispose);
      final controller = container.read(agentControllerProvider.notifier);
      final before = (await env.snapshot()).transactions.length;

      final turn = controller.send('Spent 450 on lunch in cash');
      await controller.send('Spent 450 on lunch in cash'); // duplicate tap
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
      expect(reply.text, '₹450 on Food & Dining added as an expense.');
      expect(reply.actions.single.status, ActionResultStatus.completed);
      expect((await env.snapshot()).transactions.length, before + 1);
      expect(provider.requests, hasLength(1));
    });

    test('stop while waiting for approval writes nothing and ends idle', () async {
      final env = await TestEnv.create();
      final provider = ScriptedProvider([plan([lunch()])]);
      final container = ProviderContainer(
        overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)],
      );
      addTearDown(container.dispose);
      final controller = container.read(agentControllerProvider.notifier);
      final before = (await env.snapshot()).transactions.length;

      final turn = controller.send('Spent 450 on lunch in cash');
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
      final container = ProviderContainer(
        overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)],
      );
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
      final provider = ScriptedProvider([plan([lunch()])]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)],
          child: MaterialApp(
            theme: FinnTheme.light(),
            home: const MotionScope(reduceMotion: true, child: AgentScreen()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Tell FiNN what happened'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Spent 450 on lunch in cash');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Review this change'), findsOneWidget);
      expect(find.text('Transactions · New'), findsOneWidget);
      expect(find.textContaining('450'), findsWidgets);
      expect(find.byTooltip('Stop'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The card stays with its outcome; no second summary card repeats it.
      expect(find.text('Change saved'), findsOneWidget);
      expect(find.text('Transactions · New'), findsOneWidget);
      expect(find.text('₹450 on Food & Dining added as an expense.'), findsNothing);
      expect(find.text('Saved'), findsOneWidget);
      // The saved record links to its detail screen.
      expect(find.text('View'), findsOneWidget);
      expect(find.byTooltip('Send'), findsOneWidget);
    });

    testWidgets('a declined card stays labelled; Retry regenerates it in place as Try 2', (tester) async {
      final env = await TestEnv.create();
      final provider = ScriptedProvider([
        plan([lunch()]),
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Groceries', 'note': 'lunch', 'account': 'Cash'},
        ]),
      ]);
      await pumpAgent(tester, env, provider);
      await tester.enterText(find.byType(TextField), 'Spent 450 on lunch in cash');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Decline'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Declined'), findsOneWidget, reason: 'the card stays, labelled');
      expect(find.text('Transactions · New'), findsOneWidget);
      expect(find.text('No changes made'), findsNothing, reason: 'no separate outcome card');
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Try 2'), findsOneWidget);
      expect(find.text('Review this change'), findsOneWidget);
      expect(provider.requests.last.messages.first.content, contains('Redo: the user declined'));

      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Change saved'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Try 2'), findsOneWidget, reason: 'still marked as a retry');
      final saved = (await env.snapshot()).transactions.where((t) => t.note == 'lunch').single;
      expect(saved.categoryId, 'cat_groceries');
    });

    testWidgets('several changes: a carousel with per-card decisions and Approve rest', (tester) async {
      tester.view.physicalSize = const Size(800, 1200) * tester.view.devicePixelRatio;
      addTearDown(tester.view.reset);
      final env = await TestEnv.create();
      final provider = ScriptedProvider([
        plan([
          lunch(),
          {'op': 'expense', 'amount': 60, 'category': 'Food & Dining', 'note': 'chai', 'account': 'Cash'},
          {'op': 'expense', 'amount': 120, 'category': 'Transport', 'note': 'auto', 'account': 'Cash'},
        ]),
      ]);
      final container = await pumpAgent(tester, env, provider);
      final before = (await env.snapshot()).transactions.length;
      await tester.enterText(find.byType(TextField), 'lunch 450, chai 60 and auto 120 in cash');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Review 3 changes'), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('Approve all'), findsOneWidget);

      // Decline the first: the deck moves on to the next one.
      await tester.tap(find.text('Decline').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('Approve rest (2)'), findsOneWidget);

      await tester.tap(find.text('Approve rest (2)'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('2 of 3 changes saved'), findsOneWidget);
      final deck = container.read(agentControllerProvider).decks.values.single;
      expect([for (final s in deck.slots) s.current.record!.status],
          [ActionResultStatus.declined, ActionResultStatus.completed, ActionResultStatus.completed]);
      expect((await env.snapshot()).transactions.length, before + 2);
    });

    testWidgets('while the agent works, a quiet line says what is happening (full motion)', (tester) async {
      final env = await TestEnv.create();
      final reply = Completer<LlmResponse>();
      final provider = ScriptedProvider(const []);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...env.overrides, llmProviderProvider.overrideWithValue(_DelayedProvider(provider, reply.future))],
          child: MaterialApp(theme: FinnTheme.light(), home: const MotionScope(reduceMotion: false, child: AgentScreen())),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Spent 450 on lunch in cash');
      await tester.tap(find.byTooltip('Send'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Understanding your request…'), findsOneWidget);

      reply.complete(plan([lunch()]));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Understanding your request…'), findsNothing);
      await tester.tap(find.text('Approve'));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Change saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('history lists what was asked and what was saved, filters it and clears it', (tester) async {
      final env = await TestEnv.create();
      final provider = ScriptedProvider([plan([lunch()])]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)],
          child: MaterialApp(
            theme: FinnTheme.light(),
            home: const MotionScope(reduceMotion: true, child: AgentScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Spent 450 on lunch in cash');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byTooltip('History'));
      await tester.pumpAndSettle();
      expect(find.text('Agent history'), findsOneWidget);
      expect(find.text('"Spent 450 on lunch in cash"'), findsOneWidget);
      expect(find.textContaining('1 change saved'), findsOneWidget);

      await tester.tap(find.text('"Spent 450 on lunch in cash"'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsWidgets);

      await tester.tap(find.text('Declined'));
      await tester.pumpAndSettle();
      expect(find.text('No declined requests'), findsOneWidget);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history').last);
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsOneWidget);
      // One model call for the request; history needed none.
      expect(provider.requests, hasLength(1));
    });
  });
}

Future<ProviderContainer> pumpAgent(WidgetTester tester, TestEnv env, ScriptedProvider provider) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...env.overrides, llmProviderProvider.overrideWithValue(provider)],
      child: MaterialApp(
        theme: FinnTheme.light(),
        home: const MotionScope(reduceMotion: true, child: AgentScreen()),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(AgentScreen)));
}

/// Answers the first request only once [gate] completes (later ones at once).
class _DelayedProvider implements LlmProvider {
  _DelayedProvider(this.inner, this.gate);
  final ScriptedProvider inner;
  final Future<LlmResponse> gate;
  bool _first = true;

  @override
  String get name => 'delayed';

  @override
  Future<LlmResponse> complete(LlmRequest request, {CancellationToken? cancel}) {
    if (!_first) return inner.complete(request, cancel: cancel);
    _first = false;
    return gate;
  }
}
