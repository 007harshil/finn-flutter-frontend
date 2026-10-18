import 'package:flutter/foundation.dart';

import '../../pending/domain/shared_pending.dart';

/// How another person relates to me, as shown after a FiNN ID lookup.
enum FriendRelation { self, friend, outgoing, incoming, none }

@immutable
class Friend {
  const Friend({required this.user, required this.since});

  final FinnUser user;
  final DateTime since;
}

/// A pending request. [user] is the other person.
@immutable
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.user,
    required this.createdAt,
  });

  final String id;
  final FinnUser user;
  final DateTime createdAt;
}

/// Everything the Friends screen shows.
@immutable
class FriendState {
  const FriendState({
    this.me,
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.loaded = false,
  });

  /// The signed-in user, including their FiNN ID. Null until first loaded
  /// (remote only).
  final FinnUser? me;
  final List<Friend> friends;
  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;

  /// False until the first successful load.
  final bool loaded;

  bool isFriend(String userId) => friends.any((f) => f.user.id == userId);
}

/// Result of looking someone up by FiNN ID.
@immutable
class FriendLookup {
  const FriendLookup({
    required this.user,
    required this.relation,
    this.requestId,
  });

  final FinnUser user;
  final FriendRelation relation;

  /// Set for [FriendRelation.outgoing] and [FriendRelation.incoming].
  final String? requestId;
}
