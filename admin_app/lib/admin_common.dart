import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_client.dart';

String timestamp(dynamic value) => value == null
    ? '—'
    : DateTime.parse(value as String).toLocal().toString().split('.').first;
String shortId(dynamic value) => value == null
    ? '—'
    : value.toString().substring(0, value.toString().length.clamp(0, 8));
Widget badge(String label) =>
    Chip(label: Text(label), visualDensity: VisualDensity.compact);

abstract class LiveState<T extends StatefulWidget> extends State<T> {
  bool busy = false;
  String? error;
  Timer? timer;
  Future<void> load({bool quiet = false});
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !busy && (ModalRoute.of(context)?.isCurrent ?? true))
        load(quiet: true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() work,
      {bool quiet = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      if (!quiet) error = null;
    });
    try {
      await work();
      if (mounted) setState(() => error = null);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted)
        setState(
            () => error = 'Unable to load consultancy data. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Widget> feedback() => [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(children: [
                Expanded(
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
                TextButton(
                    onPressed: busy ? null : () => load(),
                    child: const Text('Retry'))
              ]))
      ];
  Widget title(String text) => Row(children: [
        Expanded(
            child:
                Text(text, style: Theme.of(context).textTheme.headlineSmall)),
        IconButton(
            onPressed: busy ? null : () => load(),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh))
      ]);
}

Widget table(List<String> columns, List<List<Widget>> rows) =>
    SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
            columns:
                columns.map((name) => DataColumn(label: Text(name))).toList(),
            rows: rows
                .map((row) =>
                    DataRow(cells: row.map((cell) => DataCell(cell)).toList()))
                .toList()));
Widget pager(
        {required int offset,
        required int count,
        required int total,
        required int? next,
        required bool busy,
        required void Function(int) change}) =>
    Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(total == 0
                  ? 'No results'
                  : '${offset + 1}–${offset + count} of $total'),
              OutlinedButton(
                  onPressed: busy || offset == 0
                      ? null
                      : () => change((offset - 30).clamp(0, total)),
                  child: const Text('Previous')),
              OutlinedButton(
                  onPressed: busy || next == null ? null : () => change(next),
                  child: const Text('Next'))
            ]));
