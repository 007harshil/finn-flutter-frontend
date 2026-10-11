import '../../features/pending/domain/shared_pending.dart';

/// Mock directory of people on FiNN. A backend replaces this with a server
/// search (see docs/BACKEND_INTEGRATION.md).
const mockFinnUsers = <FinnUser>[
  FinnUser(id: 'u_ramesh', name: 'Ramesh Kumar', handle: '@ramesh.k', phoneHint: '•• 4821'),
  FinnUser(id: 'u_ramesh_iyer', name: 'Ramesh Iyer', handle: '@rameshiyer', phoneHint: '•• 1190'),
  FinnUser(id: 'u_priya', name: 'Priya Nair', handle: '@priya.nair', phoneHint: '•• 7702'),
  FinnUser(id: 'u_rahul', name: 'Rahul Verma', handle: '@rahulv', phoneHint: '•• 3315'),
  FinnUser(id: 'u_ananya', name: 'Ananya Iyer', handle: '@ananya.i', phoneHint: '•• 9034'),
  FinnUser(id: 'u_karan', name: 'Karan Mehta', handle: '@karan.m', phoneHint: '•• 5560'),
  FinnUser(id: 'u_sneha', name: 'Sneha Patil', handle: '@snehap', phoneHint: '•• 2047'),
  FinnUser(id: 'u_vikram', name: 'Vikram Rao', handle: '@vikram.rao', phoneHint: '•• 6683'),
];

/// Id of the signed-in user in the mock network.
const mockMyUserId = 'u_me';

/// The signed-in user as others see them.
FinnUser mockMe(String? displayName) {
  final name = (displayName == null || displayName.trim().isEmpty) ? 'You' : displayName.trim();
  return FinnUser(id: mockMyUserId, name: name, handle: '@${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '.')}');
}
