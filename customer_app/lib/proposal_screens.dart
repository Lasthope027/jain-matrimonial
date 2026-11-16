import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'auth_client.dart';

const proposalStates = {
  'PENDING': 'Pending',
  'REJECTED': 'Rejected',
  'MUTUALLY_ACCEPTED': 'Mutually accepted',
  'CANCELLED': 'Closed'
};
String proposalRef(dynamic id) =>
    id.toString().substring(0, id.toString().length.clamp(0, 8));
String proposalTime(dynamic value) => value == null
    ? '—'
    : DateTime.parse(value as String).toLocal().toString().split('.').first;

abstract class ProposalLive<T extends StatefulWidget> extends State<T> {
  bool busy = false;
  String? error;
  Timer? timer;
  Future<void> load();
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !busy && (ModalRoute.of(context)?.isCurrent ?? true))
        load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted)
        setState(
            () => error = 'Unable to complete the request. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Widget> feedback() => [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)))
      ];
}

class ProposalsScreen extends StatefulWidget {
  const ProposalsScreen({super.key, required this.client});
  final AuthClient client;
  @override
  State<ProposalsScreen> createState() => _ProposalsScreenState();
}

class _ProposalsScreenState extends ProposalLive<ProposalsScreen> {
  int tab = 0, offset = 0, total = 0;
  int? next;
  List<Map<String, dynamic>> rows = [];
  @override
  Future<void> load() => perform(() async {
        final query = Uri(queryParameters: {
          'offset': '$offset',
          'limit': '20',
          if (tab == 0) 'status': 'PENDING',
          if (tab == 1 || tab == 3) 'status': 'MUTUALLY_ACCEPTED',
          if (tab == 3) 'shared_only': 'true'
        }).query;
        final data = await widget.client.request('GET', '/proposals?$query');
        if (mounted)
          setState(() {
            rows = (data['items'] as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            total = data['total'] as int;
            next = data['next_offset'] as int?;
          });
      });
  Future<void> open(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            ProposalDetailScreen(client: widget.client, proposalId: id)));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('My proposals'), actions: [
        IconButton(
            onPressed: busy ? null : load,
            tooltip: 'Refresh proposals',
            icon: const Icon(Icons.refresh))
      ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final entry in {
                    0: 'Pending',
                    1: 'Mutually accepted',
                    2: 'Proposal history',
                    3: 'Shared biodata'
                  }.entries)
                    ChoiceChip(
                        label: Text(entry.value),
                        selected: tab == entry.key,
                        onSelected: busy
                            ? null
                            : (_) {
                                setState(() {
                                  tab = entry.key;
                                  offset = 0;
                                });
                                load();
                              })
                ]),
                const SizedBox(height: 16),
                const Text(
                    'Proposals are selected by your consultancy. Full biodata is available only after both parties accept and the consultancy authorises sharing.'),
                const SizedBox(height: 16),
                ...feedback(),
                if (!busy && rows.isEmpty && error == null)
                  const Text('No proposals in this view.'),
                for (final row in rows)
                  Card(
                      child: ListTile(
                          title: Text('Proposal ${proposalRef(row['id'])}'),
                          subtitle: Text(
                              'For ${(row['own_profile'] as Map)['full_name'] ?? 'your profile'}\n${proposalStates[row['status']]} · ${(row['match'] as Map)['location'] ?? 'Location not specified'}'),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open(row['id'] as String))),
                const SizedBox(height: 12),
                Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('$total proposal${total == 1 ? '' : 's'}'),
                      OutlinedButton(
                          onPressed: busy || offset == 0
                              ? null
                              : () {
                                  offset = (offset - 20).clamp(0, total);
                                  load();
                                },
                          child: const Text('Previous')),
                      OutlinedButton(
                          onPressed: busy || next == null
                              ? null
                              : () {
                                  offset = next!;
                                  load();
                                },
                          child: const Text('Next'))
                    ])
              ]))));
}

class ProposalDetailScreen extends StatefulWidget {
  const ProposalDetailScreen(
      {super.key, required this.client, required this.proposalId});
  final AuthClient client;
  final String proposalId;
  @override
  State<ProposalDetailScreen> createState() => _ProposalDetailScreenState();
}

class _ProposalDetailScreenState extends ProposalLive<ProposalDetailScreen> {
  Map<String, dynamic>? data;
  @override
  Future<void> load() => perform(() async {
        final result = await widget.client
            .request('GET', '/proposals/${widget.proposalId}');
        if (mounted) setState(() => data = result);
      });
  Future<void> respond(String response) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(response == 'ACCEPTED'
                    ? 'Accept this proposal?'
                    : 'Reject this proposal?'),
                content: const Text(
                    'Your response will be recorded and cannot be changed. Accepting does not release biodata until the other party accepts and the consultancy authorises it.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Confirm'))
                ]));
    if (confirmed != true || !mounted) return;
    await perform(() async {
      final result = await widget.client.request(
          'POST', '/proposals/${widget.proposalId}/responses', body: {
        'profile_id': (data!['own_profile'] as Map)['id'],
        'response': response
      });
      if (mounted) setState(() => data = result);
    });
  }

  Future<void> download(Map document) => perform(() async {
        final bytes = await widget.client
            .downloadShared(widget.proposalId, document['id'] as String);
        await FilePicker.saveFile(
            dialogTitle: 'Save shared biodata',
            fileName: document['original_name'] as String,
            bytes: bytes);
      });
  Widget line(String title, dynamic value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text('$title: ${value ?? 'Not specified'}'));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text('Proposal ${proposalRef(widget.proposalId)}'),
          actions: [
            IconButton(
                onPressed: busy ? null : load,
                tooltip: 'Refresh proposal',
                icon: const Icon(Icons.refresh))
          ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                ...feedback(),
                if (data != null) ...[
                  Text(
                      'For ${(data!['own_profile'] as Map)['full_name'] ?? 'your profile'}',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerLeft,
                      child:
                          Chip(label: Text(proposalStates[data!['status']]!))),
                  Text('Proposed ${proposalTime(data!['created_at'])}'),
                  const SizedBox(height: 16),
                  Text('Match summary',
                      style: Theme.of(context).textTheme.titleLarge),
                  line('Age when proposed', (data!['match'] as Map)['age']),
                  line('Height (cm)', (data!['match'] as Map)['height_cm']),
                  line('Community', (data!['match'] as Map)['community']),
                  line('Location', (data!['match'] as Map)['location']),
                  line('Education', (data!['match'] as Map)['education']),
                  line('Profession', (data!['match'] as Map)['profession']),
                  const SizedBox(height: 16),
                  line('Your response',
                      data!['own_response'] ?? 'Not yet responded'),
                  line('Other party',
                      data!['other_response'] ?? 'Awaiting response'),
                  if (data!['can_respond'] == true)
                    Wrap(spacing: 12, children: [
                      FilledButton(
                          onPressed: busy ? null : () => respond('ACCEPTED'),
                          child: const Text('Accept proposal')),
                      OutlinedButton(
                          onPressed: busy ? null : () => respond('REJECTED'),
                          child: const Text('Reject proposal'))
                    ]),
                  if (data!['closure_reason'] != null)
                    Text(data!['closure_reason'] as String),
                  const SizedBox(height: 24),
                  Text('Shared biodata',
                      style: Theme.of(context).textTheme.titleLarge),
                  if ((data!['shared_documents'] as List).isEmpty)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(data!['status'] == 'MUTUALLY_ACCEPTED'
                            ? 'Both parties accepted. Biodata awaits consultancy authorisation.'
                            : 'Biodata is private until mutual acceptance and consultancy authorisation.')),
                  for (final document in data!['shared_documents'] as List)
                    Card(
                        child: ListTile(
                            title: Text(document['original_name'] as String),
                            subtitle: Text(
                                'Authorised ${proposalTime(document['authorised_at'])}'),
                            trailing: IconButton(
                                onPressed: busy
                                    ? null
                                    : () => download(document as Map),
                                tooltip: 'Save shared biodata',
                                icon: const Icon(Icons.download)))),
                ]
              ]))));
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.client});
  final AuthClient client;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ProposalLive<NotificationsScreen> {
  List<Map<String, dynamic>> rows = [];
  int offset = 0, unread = 0;
  int? next;
  bool onlyUnread = false;
  @override
  Future<void> load() => perform(() async {
        final query = Uri(queryParameters: {
          'offset': '$offset',
          'limit': '30',
          'unread': '$onlyUnread'
        }).query;
        final result =
            await widget.client.request('GET', '/notifications?$query');
        if (mounted)
          setState(() {
            rows = (result['items'] as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            unread = result['unread_count'] as int;
            next = result['next_offset'] as int?;
          });
      });
  Future<void> read(Map<String, dynamic> notice, {bool open = false}) async {
    await perform(() async {
      await widget.client.request('PUT', '/notifications/${notice['id']}/read');
    });
    if (!mounted) return;
    if (open && error == null && notice['proposal_id'] != null)
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProposalDetailScreen(
              client: widget.client,
              proposalId: notice['proposal_id'] as String)));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [
        IconButton(
            onPressed: busy ? null : load,
            tooltip: 'Refresh notifications',
            icon: const Icon(Icons.refresh))
      ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Text('$unread unread'),
                SwitchListTile(
                    title: const Text('Unread only'),
                    value: onlyUnread,
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(() {
                              onlyUnread = value;
                              offset = 0;
                            });
                            load();
                          }),
                ...feedback(),
                if (rows.isEmpty && !busy && error == null)
                  const Text('No notifications in this view.'),
                for (final notice in rows)
                  Card(
                      child: ListTile(
                          title: Text((notice['event'] as String)
                              .replaceAll('_', ' ')
                              .toLowerCase()),
                          subtitle: Text(
                              '${notice['message']}\n${proposalTime(notice['created_at'])}'),
                          isThreeLine: true,
                          onTap: busy ? null : () => read(notice, open: true),
                          trailing: notice['read_at'] == null
                              ? IconButton(
                                  onPressed: busy ? null : () => read(notice),
                                  tooltip: 'Mark as read',
                                  icon: const Icon(
                                      Icons.mark_email_read_outlined))
                              : const Icon(Icons.done))),
                Wrap(spacing: 12, children: [
                  OutlinedButton(
                      onPressed: busy || offset == 0
                          ? null
                          : () {
                              offset = (offset - 30).clamp(0, offset);
                              load();
                            },
                      child: const Text('Previous')),
                  OutlinedButton(
                      onPressed: busy || next == null
                          ? null
                          : () {
                              offset = next!;
                              load();
                            },
                      child: const Text('Next'))
                ])
              ]))));
}
