# Friends and FiNN IDs

Shared pending items used to link any FiNN user found by name or handle. A
stranger could add anyone and push a fake "you owe me ₹40,000" into their
account. Now sharing needs a friendship, and people are found only by an
exact FiNN ID.

## Rules

- Every user has a **FiNN ID**: 8 characters from `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`
  (no 0, 1, I, O), random, unique, never changes. Stored uppercase without a dash
  (`K7Q2M9XD`), shown as `K7Q2-M9XD`. Input is normalised: drop spaces and dashes,
  uppercase; anything else that does not match `^[2-9A-HJ-NP-Z]{8}$` is invalid.
- **Global lookup is by exact FiNN ID only.** No name, handle or partial search over
  all users. A lookup shows only the person's name and FiNN ID (no handle, no phone hint).
- Friend request flow: A looks up B's FiNN ID → sends a request → B sees it under
  incoming requests → B accepts (now friends) or rejects (request deleted; A may send a
  new one). A can cancel a pending request. If B already sent A a request, A sending
  one back accepts it at once.
- Either friend can remove the friendship. Existing shared items stay; only new
  shares need a friendship.
- At most 50 outgoing pending requests per user.
- **Sharing a pending item (create, split, update) needs an accepted friendship** with
  the linked user. The person picker in the pending form lists only friends.
- Items shared before this change are kept as they are.

## API (all authenticated, base `/api/v1`)

Responses use the usual envelope (`{ data: … }`, errors `{ error: { code, message, fieldErrors } }`);
the shapes below are the `data` part.

Shapes:

```jsonc
// FriendUser
{ "id": "<uuid>", "name": "Ramesh Kumar", "finnId": "K7Q2M9XD" }
// Friend
{ "user": FriendUser, "since": "2026-10-18T09:00:00.000Z" }
// FriendRequest
{ "id": "<uuid>", "user": FriendUser, "createdAt": "2026-10-18T09:00:00.000Z" }
```

| Method & path | Body / query | Response |
| --- | --- | --- |
| `GET /friends` | | `{ me: FriendUser, friends: Friend[], incoming: FriendRequest[], outgoing: FriendRequest[] }` (friends by name; requests newest first; `user` in a request is the other person) |
| `GET /users/lookup` | `?finnId=K7Q2-M9XD` | `{ user: (FriendUser & { relation, requestId? }) \| null }`; `relation` ∈ `self`, `friend`, `outgoing`, `incoming`, `none`; `requestId` set for `outgoing`/`incoming`. Bad format → 422 `fieldErrors.finnId` |
| `POST /friends/requests` | `{ finnId }` | `{ request: FriendRequest }` (sent) or `{ friend: Friend }` (they had asked you, now friends) |
| `POST /friends/requests/{id}/accept` | | `{ friend: Friend }` (addressee only) |
| `POST /friends/requests/{id}/reject` | | `{ ok: true }` (addressee only; request deleted) |
| `DELETE /friends/requests/{id}` | | `{ ok: true }` (requester only; cancel) |
| `DELETE /friends/{userId}` | | `{ ok: true }` (remove friend) |
| `GET /users/search` | `?q=` | `{ items: [{ id, name, handle, phoneHint, finnId }] }` — **friends only**; empty `q` returns all friends (up to 50) |

Errors on `POST /friends/requests` (body `fieldErrors.finnId` for 422):
- invalid format → 422 "Enter a valid FiNN ID, like K7Q2-M9XD."
- own ID → 422 "That is your own FiNN ID."
- unknown ID → 404 "No FiNN user has that ID."
- already friends → 409 "You are already friends."
- already requested → 409 "You already sent a request. Wait for them to accept it."
- 50 outgoing pending → 422 "You have too many pending requests. Cancel some first."

Accept/reject/cancel of a missing or not-yours request → 404 "This request no longer exists."

`GET /sync` value `me` and `GET /me` `user` gain `finnId`.

Pending actions: `linkedUserId` of a user who is not a friend → 422
`fieldErrors.linkedUserId` = "You can share only with friends. Send them a friend request first."
(`people.N.linkedUserId` for splits). Editing an existing shared item keeps its link
even after the friendship ends.

## Storage

Migration `20261018090000_finn_friends.sql`:
- `public.profiles.finn_id text not null unique` (default `private.new_finn_id()`,
  backfilled for existing users).
- `public.friend_requests (id uuid pk, requester_id, addressee_id, created_at)` — pending only.
- `public.friendships (user_low, user_high, created_at, pk (user_low, user_high))`,
  `user_low < user_high`.
- RLS: a row is visible to its two parties only. Other people's names come from
  security-definer functions that return name + FiNN ID only.
- `private.search_users` is restricted to friends.
