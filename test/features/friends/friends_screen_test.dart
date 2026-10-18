import 'package:finn/features/friends/presentation/friends_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize =
        const Size(400, 1400) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await env.pumpWidget(tester, const FriendsScreen());
    await tester.pumpAndSettle();
  }

  Future<void> find_(WidgetTester tester, String id) async {
    await tester.enterText(find.byKey(const ValueKey('friend-id-input')), id);
    await tester.tap(find.byKey(const ValueKey('friend-find')));
    await tester.pumpAndSettle();
  }

  /// Lets the toast timer finish.
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 6));

  testWidgets('shows my FiNN ID, friends and incoming requests', (
    tester,
  ) async {
    await open(tester);
    final id = env.store.friends.current.me!.finnId!;
    expect(
      find.text('${id.substring(0, 4)}-${id.substring(4)}'),
      findsOneWidget,
    );
    expect(find.text('Your FiNN ID'), findsOneWidget);
    expect(find.byKey(const ValueKey('friend:u_ramesh')), findsOneWidget);
    expect(find.byKey(const ValueKey('friend:u_priya')), findsOneWidget);
    expect(find.textContaining('Wants to be your friend'), findsOneWidget);
  });

  testWidgets('look up a FiNN ID and send a request', (tester) async {
    await open(tester);
    await find_(tester, 'h4tn-8wbe');
    expect(find.byKey(const ValueKey('friend-lookup-result')), findsOneWidget);
    expect(find.text('Ramesh Iyer'), findsOneWidget);
    expect(find.textContaining('H4TN-8WBE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('friend-send')));
    await tester.pumpAndSettle();
    expect(env.store.friends.current.outgoing.single.user.id, 'u_ramesh_iyer');
    // The result now offers to cancel, and the request is listed.
    expect(find.byKey(const ValueKey('friend-send')), findsNothing);
    expect(find.byKey(const ValueKey('friend-cancel')), findsOneWidget);
    expect(find.textContaining('Waiting for them'), findsOneWidget);
    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accept an incoming request', (tester) async {
    await open(tester);
    final request = env.store.friends.current.incoming.single;
    await tester.tap(find.byKey(ValueKey('friend-accept:${request.id}')));
    await tester.pumpAndSettle();
    expect(env.store.friends.current.isFriend('u_rahul'), isTrue);
    expect(find.byKey(const ValueKey('friend:u_rahul')), findsOneWidget);
    expect(find.byKey(ValueKey('incoming:${request.id}')), findsNothing);
    await drain(tester);
  });

  testWidgets('reject an incoming request', (tester) async {
    await open(tester);
    final request = env.store.friends.current.incoming.single;
    await tester.tap(find.byKey(ValueKey('friend-reject:${request.id}')));
    await tester.pumpAndSettle();
    expect(env.store.friends.current.incoming, isEmpty);
    expect(env.store.friends.current.isFriend('u_rahul'), isFalse);
    await drain(tester);
  });

  testWidgets('a lookup of an incoming request offers accept and reject', (
    tester,
  ) async {
    await open(tester);
    await find_(tester, 'R9VK6DHM');
    final panel = find.byKey(const ValueKey('friend-lookup-result'));
    expect(
      find.descendant(of: panel, matching: find.text('Accept')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Reject')),
      findsOneWidget,
    );
  });

  testWidgets('own ID, friend, not found and bad format', (tester) async {
    await open(tester);
    await find_(tester, env.store.friends.current.me!.finnId!);
    expect(find.textContaining('That is you'), findsOneWidget);

    await find_(tester, 'K7Q2M9XD');
    expect(find.textContaining('Already friends'), findsOneWidget);

    await find_(tester, 'ZZZZZZZZ');
    expect(find.text('No FiNN user has that ID.'), findsOneWidget);
    expect(find.byKey(const ValueKey('friend-lookup-result')), findsNothing);

    await find_(tester, 'abc');
    expect(find.text('Enter a valid FiNN ID, like K7Q2-M9XD.'), findsOneWidget);
  });

  testWidgets('removing a friend asks first and explains shared items stay', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Remove Ramesh Kumar'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Items you already share stay as they are'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(env.store.friends.current.isFriend('u_ramesh'), isFalse);
    expect(find.byKey(const ValueKey('friend:u_ramesh')), findsNothing);
    await drain(tester);
  });

  testWidgets('with no friends the list shows an empty state', (tester) async {
    for (final f in List.of(env.store.friends.current.friends)) {
      await env.store.friends.removeFriend(f.user.id);
    }
    await open(tester);
    expect(find.text('No friends yet'), findsOneWidget);
  });
}
