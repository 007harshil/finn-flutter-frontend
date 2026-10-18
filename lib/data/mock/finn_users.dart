import '../../features/pending/domain/shared_pending.dart';

/// Mock directory of people on FiNN. A backend replaces this with a server
/// search (see docs/BACKEND_INTEGRATION.md).
const mockFinnUsers = <FinnUser>[
  FinnUser(id: 'u_ramesh', name: 'Ramesh Kumar', handle: '@ramesh.k', phoneHint: '•• 4821', finnId: 'K7Q2M9XD'),
  FinnUser(id: 'u_ramesh_iyer', name: 'Ramesh Iyer', handle: '@rameshiyer', phoneHint: '•• 1190', finnId: 'H4TN8WBE'),
  FinnUser(id: 'u_priya', name: 'Priya Nair', handle: '@priya.nair', phoneHint: '•• 7702', finnId: 'P5RC3YJA'),
  FinnUser(id: 'u_rahul', name: 'Rahul Verma', handle: '@rahulv', phoneHint: '•• 3315', finnId: 'R9VK6DHM'),
  FinnUser(id: 'u_ananya', name: 'Ananya Iyer', handle: '@ananya.i', phoneHint: '•• 9034', finnId: 'A7XQ2FNT'),
  FinnUser(id: 'u_karan', name: 'Karan Mehta', handle: '@karan.m', phoneHint: '•• 5560', finnId: 'K3MZ8PLC'),
  FinnUser(id: 'u_sneha', name: 'Sneha Patil', handle: '@snehap', phoneHint: '•• 2047', finnId: 'S6WD4GHE'),
  FinnUser(id: 'u_vikram', name: 'Vikram Rao', handle: '@vikram.rao', phoneHint: '•• 6683', finnId: 'V2NB9QRT'),
];

/// Id of the signed-in user in the mock network.
const mockMyUserId = 'u_me';

/// The signed-in user as others see them.
FinnUser mockMe(String? displayName) {
  final name = (displayName == null || displayName.trim().isEmpty) ? 'You' : displayName.trim();
  return FinnUser(id: mockMyUserId, name: name, handle: '@${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '.')}', finnId: mockMyFinnId);
}

/// FiNN ID of the signed-in user in the mock network.
const mockMyFinnId = 'M3QA7KZ2';

/// Friends in a fresh local network: Ramesh Kumar and Priya Nair. Rahul
/// Verma has asked to be a friend.
const mockFriendIds = ['u_ramesh', 'u_priya'];
const mockIncomingRequestIds = ['u_rahul'];
