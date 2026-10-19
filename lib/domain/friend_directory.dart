import '../features/friends/domain/friends.dart';

/// Friends and friend requests. Failures are thrown as `AppFailure` with a
/// message ready to show (and `fieldErrors['finnId']` for ID problems).
abstract interface class FriendDirectory {
  FriendState get current;

  /// Emits whenever [current] changes.
  Stream<FriendState> watch();

  Future<void> refresh();

  /// The person with [finnId] (any format; normalised here), or null when no
  /// one has it. Throws a validation failure for a malformed ID.
  Future<FriendLookup?> lookup(String finnId);

  /// Sends a request. Returns [FriendRelation.outgoing], or
  /// [FriendRelation.friend] when they had already asked and you are now
  /// friends.
  Future<FriendRelation> sendRequest(String finnId);

  Future<void> accept(String requestId);
  Future<void> reject(String requestId);
  Future<void> cancel(String requestId);
  Future<void> removeFriend(String userId);

  /// Blocks someone I am connected to (friend, request or shared item):
  /// ends the friendship, drops open requests and stops new ones both ways.
  Future<void> block(String userId);
  Future<void> unblock(String userId);
}
