import 'dart:async';

/// Cooperative cancellation flag passed into long-running scans.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Runs [task] over [items] with at most [concurrency] in flight, emitting
/// each result as soon as it completes. Stops scheduling new work once
/// [cancel] is triggered.
Stream<R> pooled<T, R>(
  Iterable<T> items,
  Future<R> Function(T item) task, {
  int concurrency = 64,
  CancelToken? cancel,
}) {
  final controller = StreamController<R>();
  final iterator = items.iterator;
  var active = 0;
  var exhausted = false;

  void pump() {
    while (active < concurrency && !exhausted && !(cancel?.isCancelled ?? false)) {
      if (!iterator.moveNext()) {
        exhausted = true;
        break;
      }
      final item = iterator.current;
      active++;
      task(item).then((r) {
        if (!controller.isClosed) controller.add(r);
      }, onError: (Object e, StackTrace s) {
        if (!controller.isClosed) controller.addError(e, s);
      }).whenComplete(() {
        active--;
        pump();
      });
    }
    final stopped = exhausted || (cancel?.isCancelled ?? false);
    if (stopped && active == 0 && !controller.isClosed) controller.close();
  }

  controller.onListen = pump;
  return controller.stream;
}
