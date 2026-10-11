/// Generic repository contract shared by every collection of entities.
abstract interface class CrudRepository<T> {
  /// Emits the current list immediately, then on every change.
  Stream<List<T>> watchAll();
  Future<List<T>> getAll();
  Future<T?> getById(String id);
  Future<void> save(T item);
  Future<void> saveAll(Iterable<T> items);
  Future<void> delete(String id);
}
