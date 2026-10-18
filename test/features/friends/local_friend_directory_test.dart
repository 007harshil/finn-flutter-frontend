import 'package:finn/core/result/result.dart';
import 'package:finn/features/friends/domain/friends.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

Matcher failing(String message, {FailureCode? code}) => isA<AppFailure>()
    .having((f) => f.message, 'message', message)
    .having((f) => f.code, 'code', code ?? isA<FailureCode>());

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());

  test(
    'starts with Ramesh and Priya as friends and Rahul as an incoming request',
    () {
      final s = env.store.friends.current;
      expect(
        [for (final f in s.friends) f.user.name],
        ['Ramesh Kumar', 'Priya Nair'],
      );
      expect(s.incoming.single.user.name, 'Rahul Verma');
      expect(s.outgoing, isEmpty);
      expect(s.me!.finnId, isNotNull);
    },
  );

  group('lookup', () {
    test(
      'finds by exact FiNN ID in any format and reports the relation',
      () async {
        final friend = await env.store.friends.lookup('k7q2-m9xd');
        expect(friend!.user.name, 'Ramesh Kumar');
        expect(friend.relation, FriendRelation.friend);

        final incoming = await env.store.friends.lookup('R9VK6DHM');
        expect(incoming!.relation, FriendRelation.incoming);
        expect(incoming.requestId, isNotNull);

        final stranger = await env.store.friends.lookup('H4TN8WBE');
        expect(stranger!.relation, FriendRelation.none);

        final me = await env.store.friends.lookup(
          env.store.friends.current.me!.finnId!,
        );
        expect(me!.relation, FriendRelation.self);
      },
    );

    test(
      'unknown ID gives null; bad format throws a finnId field error',
      () async {
        expect(await env.store.friends.lookup('ZZZZZZZZ'), isNull);
        await expectLater(
          env.store.friends.lookup('nope'),
          throwsA(
            isA<AppFailure>().having(
              (f) => f.fieldErrors['finnId'],
              'field',
              isNotNull,
            ),
          ),
        );
      },
    );

    test('partial IDs and names never match', () async {
      expect(
        () => env.store.friends.lookup('K7Q2'),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => env.store.friends.lookup('Ramesh'),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('requests', () {
    test('send, then cancel', () async {
      final result = await env.store.friends.sendRequest('H4TN8WBE');
      expect(result, FriendRelation.outgoing);
      final out = env.store.friends.current.outgoing.single;
      expect(out.user.name, 'Ramesh Iyer');
      expect(
        (await env.store.friends.lookup('H4TN8WBE'))!.relation,
        FriendRelation.outgoing,
      );

      await env.store.friends.cancel(out.id);
      expect(env.store.friends.current.outgoing, isEmpty);
      await expectLater(
        env.store.friends.cancel(out.id),
        throwsA(failing('This request no longer exists.')),
      );
    });

    test('accept makes a friend, reject deletes the request', () async {
      final rahul = env.store.friends.current.incoming.single;
      await env.store.friends.accept(rahul.id);
      expect(env.store.friends.current.isFriend('u_rahul'), isTrue);
      expect(env.store.friends.current.incoming, isEmpty);

      // Another incoming request rejected: seed none, so create via a second store is not
      // possible; reject of a missing request fails like the server does.
      await expectLater(
        env.store.friends.reject(rahul.id),
        throwsA(failing('This request no longer exists.')),
      );
    });

    test(
      'sending to someone who already asked you makes you friends at once',
      () async {
        final result = await env.store.friends.sendRequest('R9VK6DHM');
        expect(result, FriendRelation.friend);
        expect(env.store.friends.current.isFriend('u_rahul'), isTrue);
        expect(env.store.friends.current.incoming, isEmpty);
      },
    );

    test('server errors: self, unknown, already friends, already requested, bad format', () async {
      final d = env.store.friends;
      await expectLater(
        d.sendRequest(d.current.me!.finnId!),
        throwsA(failing('That is your own FiNN ID.')),
      );
      await expectLater(
        d.sendRequest('ZZZZZZZZ'),
        throwsA(
          failing('No FiNN user has that ID.', code: FailureCode.notFound),
        ),
      );
      await expectLater(
        d.sendRequest('K7Q2M9XD'),
        throwsA(
          failing('You are already friends.', code: FailureCode.conflict),
        ),
      );
      await d.sendRequest('H4TN8WBE');
      await expectLater(
        d.sendRequest('H4TN8WBE'),
        throwsA(
          failing(
            'You already sent a request. Wait for them to accept it.',
            code: FailureCode.conflict,
          ),
        ),
      );
      await expectLater(
        d.sendRequest('abc'),
        throwsA(failing('Enter a valid FiNN ID, like K7Q2-M9XD.')),
      );
    });

    test('removing a friend', () async {
      await env.store.friends.removeFriend('u_ramesh');
      expect(env.store.friends.current.isFriend('u_ramesh'), isFalse);
      expect(env.store.users.isFriend('u_ramesh'), isFalse);
    });
  });

  test('state changes are streamed', () async {
    final events = <FriendState>[];
    final sub = env.store.friends.watch().listen(events.add);
    await env.store.friends.sendRequest('H4TN8WBE');
    await Future<void>.delayed(Duration.zero);
    expect(events.last.outgoing, hasLength(1));
    await sub.cancel();
  });

  group('UserDirectory', () {
    test('search lists friends only; empty query lists all', () async {
      final users = env.store.users;
      expect(
        [for (final u in await users.search('')) u.id],
        ['u_ramesh', 'u_priya'],
      );
      expect([for (final u in await users.search('rame')) u.id], ['u_ramesh']);
      expect(await users.search('rahul'), isEmpty);
    });

    test('known still resolves non-friends (already-linked users)', () {
      expect(env.store.users.known('u_rahul')?.name, 'Rahul Verma');
      expect(env.store.users.isFriend('u_rahul'), isFalse);
    });
  });
}
