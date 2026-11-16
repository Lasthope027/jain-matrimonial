import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'auth_client.dart';
import 'admin_common.dart';
import 'profile_workspace.dart';

const proposalStatusLabels = {
  'PENDING': 'Pending',
  'REJECTED': 'Rejected',
  'MUTUALLY_ACCEPTED': 'Mutually accepted',
  'CANCELLED': 'Closed'
};

class AdminProposalsPanel extends StatefulWidget {
  const AdminProposalsPanel({super.key, required this.client});
  final AuthClient client;
  @override
  State<AdminProposalsPanel> createState() => _AdminProposalsPanelState();
}

class _AdminProposalsPanelState extends LiveState<AdminProposalsPanel> {
  final search = TextEditingController();
  String? status;
  String applied = '';
  String? appliedStatus;
  List<Map<String, dynamic>> rows = [];
  int offset = 0, total = 0;
  int? next;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> fetch() async {
    final query = Uri(queryParameters: {
      'q': applied,
      if (appliedStatus != null) 'status': appliedStatus!,
      'offset': '$offset',
      'limit': '30'
    }).query;
    final result =
        await widget.client.request('GET', '/admin/proposals?$query');
    if (mounted)
      setState(() {
        rows = (result['items'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        total = result['total'] as int;
        next = result['next_offset'] as int?;
      });
  }

  @override
  Future<void> load({bool quiet = false}) => perform(fetch, quiet: quiet);
  void apply() {
    offset = 0;
    applied = search.text.trim();
    appliedStatus = status;
    load();
  }

  Future<void> open(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            AdminProposalDetail(client: widget.client, proposalId: id)));
    if (mounted) await load();
  }

  Future<void> create() async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => ProposalCreateDialog(client: widget.client));
    if (result != null && mounted) await open(result['id'] as String);
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        title('Proposal management'),
        const Text(
            'Select suitable profiles manually, monitor both responses and authorise specific biodata only after mutual acceptance.'),
        const SizedBox(height: 20),
        Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: 300,
                  child: TextField(
                      controller: search,
                      maxLength: 200,
                      decoration: const InputDecoration(
                          labelText: 'Profile name or proposal ID',
                          border: OutlineInputBorder()),
                      onSubmitted: (_) => apply())),
              SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                      initialValue: status,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Proposal status',
                          border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Any status')),
                        for (final entry in proposalStatusLabels.entries)
                          DropdownMenuItem(
                              value: entry.key, child: Text(entry.value))
                      ],
                      onChanged: (value) => setState(() => status = value))),
              FilledButton(
                  onPressed: busy ? null : apply,
                  child: const Text('Apply filters')),
              OutlinedButton.icon(
                  onPressed: busy ? null : create,
                  icon: const Icon(Icons.add),
                  label: const Text('Create proposal'))
            ]),
        ...feedback(),
        if (rows.isEmpty && !busy && error == null)
          const Text('No proposals match this view.'),
        if (rows.isNotEmpty)
          table([
            'Proposal',
            'Profiles',
            'Status',
            'Responses',
            'Sharing',
            ''
          ], [
            for (final row in rows)
              [
                SelectableText(shortId(row['id'])),
                Text((row['profiles'] as List)
                    .map((e) => e['full_name'])
                    .join(' ↔ ')),
                badge(proposalStatusLabels[row['status']]!),
                Text('${(row['responses'] as List).length}/2 responded'),
                Text(
                    '${(row['sharing_records'] as List).where((e) => e['revoked_at'] == null).length} authorised files'),
                TextButton(
                    onPressed: () => open(row['id'] as String),
                    child: const Text('Open'))
              ]
          ]),
        pager(
            offset: offset,
            count: rows.length,
            total: total,
            next: next,
            busy: busy,
            change: (value) {
              offset = value;
              load();
            })
      ]);
}

class ApprovedProfilePicker extends StatefulWidget {
  const ApprovedProfilePicker({super.key, required this.client, this.exclude});
  final AuthClient client;
  final String? exclude;
  @override
  State<ApprovedProfilePicker> createState() => _ApprovedProfilePickerState();
}

class _ApprovedProfilePickerState extends State<ApprovedProfilePicker> {
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  bool busy = false;
  String? error;
  int offset = 0;
  int? next;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final query = Uri(queryParameters: {
        'status': 'APPROVED',
        'q': search.text.trim(),
        'offset': '$offset',
        'limit': '30'
      }).query;
      final result =
          await widget.client.request('GET', '/admin/profiles?$query');
      if (mounted)
        setState(() {
          rows = (result['items'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .where((e) => e['id'] != widget.exclude)
              .toList();
          next = result['next_offset'] as int?;
        });
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Choose an approved profile'),
          content: SizedBox(
              width: 650,
              height: 440,
              child: Column(children: [
                TextField(
                    controller: search,
                    decoration: const InputDecoration(
                        labelText: 'Search name or profile ID'),
                    onSubmitted: (_) {
                      offset = 0;
                      load();
                    }),
                TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            offset = 0;
                            load();
                          },
                    child: const Text('Search')),
                if (busy) const LinearProgressIndicator(),
                if (error != null) Text(error!),
                Expanded(
                    child: ListView(children: [
                  if (rows.isEmpty && !busy)
                    const Text('No approved profiles found.'),
                  for (final row in rows)
                    ListTile(
                        title: Text(row['full_name'] as String),
                        subtitle: Text(
                            '${row['current_location'] ?? 'Location not specified'} · ${shortId(row['id'])}'),
                        onTap: busy ? null : () => Navigator.pop(context, row))
                ])),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                      onPressed: busy || offset == 0
                          ? null
                          : () {
                              offset = (offset - 30).clamp(0, offset);
                              load();
                            },
                      child: const Text('Previous')),
                  TextButton(
                      onPressed: busy || next == null
                          ? null
                          : () {
                              offset = next!;
                              load();
                            },
                      child: const Text('Next'))
                ])
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'))
          ]);
}

class ProposalCreateDialog extends StatefulWidget {
  const ProposalCreateDialog({super.key, required this.client});
  final AuthClient client;
  @override
  State<ProposalCreateDialog> createState() => _ProposalCreateDialogState();
}

class _ProposalCreateDialogState extends State<ProposalCreateDialog> {
  Map<String, dynamic>? a, b;
  bool busy = false;
  String? error;
  Future<void> choose(bool first) async {
    final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => ApprovedProfilePicker(
            client: widget.client, exclude: (first ? b : a)?['id'] as String?));
    if (selected == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final detail =
          await widget.client.request('GET', '/profiles/${selected['id']}');
      if (detail['account_email'] == null)
        throw const AuthException(
            'Link this profile to a customer account before proposing.');
      if (mounted)
        setState(() {
          if (first) {
            a = detail;
          } else {
            b = detail;
          }
        });
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (a == null || b == null) return;
    if (a!['account_email'] == b!['account_email']) {
      setState(() =>
          error = 'Choose profiles from two different customer accounts.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result =
          await widget.client.request('POST', '/admin/proposals', body: {
        'profile_a_id': a!['id'],
        'profile_b_id': b!['id'],
        'profile_a_version': a!['version'],
        'profile_b_version': b!['version']
      });
      if (mounted) Navigator.pop(context, result);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget choice(String title, Map<String, dynamic>? value, bool first) => Card(
      child: ListTile(
          title: Text(value?['full_name'] as String? ?? title),
          subtitle: Text(value?['account_email'] as String? ??
              'Select an approved profile linked to an active customer.'),
          trailing: TextButton(
              onPressed: busy ? null : () => choose(first),
              child: const Text('Choose'))));
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Create a manual proposal'),
          content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Both customers receive a limited match summary and respond independently. Full biodata remains private until mutual acceptance and your explicit authorisation.'),
                choice('First profile', a, true),
                choice('Second profile', b, false),
                if (busy) const LinearProgressIndicator(),
                if (error != null) Text(error!)
              ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: busy || a == null || b == null ? null : submit,
                child: const Text('Create proposal'))
          ]);
}

class AdminProposalDetail extends StatefulWidget {
  const AdminProposalDetail(
      {super.key, required this.client, required this.proposalId});
  final AuthClient client;
  final String proposalId;
  @override
  State<AdminProposalDetail> createState() => _AdminProposalDetailState();
}

class _AdminProposalDetailState extends LiveState<AdminProposalDetail> {
  Map<String, dynamic>? data;
  Set<String> selected = {};
  Future<void> fetch() async {
    final result =
        await widget.client.request('GET', '/proposals/${widget.proposalId}');
    if (mounted)
      setState(() {
        data = result;
        final available =
            (result['documents'] as List).map((e) => e['id'] as String).toSet();
        final granted = (result['sharing_records'] as List)
            .where((e) => e['revoked_at'] == null)
            .map((e) => e['document_id'] as String)
            .toSet();
        selected.removeWhere(
            (id) => !available.contains(id) || granted.contains(id));
      });
  }

  @override
  Future<void> load({bool quiet = false}) => perform(fetch, quiet: quiet);
  Future<void> sharing() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Authorise selected biodata?'),
                content: Text(
                    'Release ${selected.length} selected file(s) to the opposite parties. Both parties must already have accepted. This authorisation is audited.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Authorise sharing'))
                ]));
    if (confirmed != true || !mounted) return;
    await perform(() async {
      await widget.client.request(
          'POST', '/admin/proposals/${widget.proposalId}/sharing', body: {
        'version': data!['version'],
        'document_ids': selected.toList()
      });
      await fetch();
    });
  }

  Future<void> close() async {
    var reason = '';
    final form = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Close proposal and revoke access?'),
                content: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'This ends future shared-file access and requires a fresh proposal for new consent.'),
                      TextFormField(
                          onChanged: (value) => reason = value.trim(),
                          maxLength: 500,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText: 'Internal reason (required)'),
                          validator: (value) => value?.trim().isNotEmpty == true
                              ? null
                              : 'Enter a reason')
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate())
                          Navigator.pop(dialogContext, true);
                      },
                      child: const Text('Close proposal'))
                ]));
    if (confirmed != true || !mounted) return;
    await perform(() async {
      await widget.client.request(
          'POST', '/admin/proposals/${widget.proposalId}/cancel',
          body: {'version': data!['version'], 'reason': reason});
      await fetch();
    });
  }

  Future<void> download(Map document) => perform(() async {
        final bytes = await widget.client.download(document['id'] as String);
        await FilePicker.saveFile(
            fileName: document['original_name'] as String, bytes: bytes);
      });
  Future<void> openProfile(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProfileEditor(client: widget.client, profileId: id)));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final active = data != null &&
        ['PENDING', 'MUTUALLY_ACCEPTED'].contains(data!['status']);
    final canShare =
        data?['status'] == 'MUTUALLY_ACCEPTED' && data?['eligible'] == true;
    final grants = (data?['sharing_records'] as List? ?? [])
        .where((e) => e['revoked_at'] == null)
        .map((e) => e['document_id'])
        .toSet();
    return Scaffold(
        appBar: AppBar(
            title: Text('Proposal ${shortId(widget.proposalId)}'),
            actions: [
              IconButton(
                  onPressed: busy ? null : () => load(),
                  tooltip: 'Refresh proposal',
                  icon: const Icon(Icons.refresh))
            ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  ...feedback(),
                  if (data != null) ...[
                    Align(
                        alignment: Alignment.centerLeft,
                        child: badge(proposalStatusLabels[data!['status']]!)),
                    Text('Created ${timestamp(data!['created_at'])}'),
                    if (data!['closure_reason'] != null)
                      Text(
                          'Internal closure reason: ${data!['closure_reason']}'),
                    for (final p in data!['profiles'] as List)
                      Card(
                          child: ListTile(
                              title: Text(p['full_name'] as String),
                              subtitle: Text(
                                  '${p['account_email'] ?? 'No current customer account'}\n${statusNames[p['status']]} · Response: ${(data!['responses'] as List).where((e) => e['profile_id'] == p['id']).map((e) => e['response']).firstOrNull ?? 'Awaiting response'}'),
                              isThreeLine: true,
                              trailing: TextButton(
                                  onPressed: () =>
                                      openProfile(p['id'] as String),
                                  child: const Text('Open profile')))),
                    const SizedBox(height: 20),
                    Text('Biodata authorisation',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Text(
                        'For the first release, select at least one biodata document from each profile. Only selected files are released to the opposite parties.'),
                    if (!canShare)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              'Sharing is unavailable until both parties accept and both profiles remain eligible.')),
                    for (final d in data!['documents'] as List)
                      CheckboxListTile(
                          value: grants.contains(d['id']) ||
                              selected.contains(d['id']),
                          onChanged:
                              busy || !canShare || grants.contains(d['id'])
                                  ? null
                                  : (value) => setState(() {
                                        value == true
                                            ? selected.add(d['id'] as String)
                                            : selected.remove(d['id']);
                                      }),
                          title: Text(d['original_name'] as String),
                          subtitle: Text(
                              '${d['kind']} · ${(data!['profiles'] as List).firstWhere((p) => p['id'] == d['profile_id'])['full_name']}${grants.contains(d['id']) ? ' · Already authorised' : ''}'),
                          secondary: IconButton(
                              onPressed: busy ? null : () => download(d as Map),
                              tooltip: 'Review document',
                              icon: const Icon(Icons.download))),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      FilledButton(
                          onPressed: busy || !canShare || selected.isEmpty
                              ? null
                              : sharing,
                          child: const Text('Authorise selected files')),
                      if (active)
                        OutlinedButton(
                            onPressed: busy ? null : close,
                            child: const Text('Close proposal / revoke access'))
                    ]),
                    const SizedBox(height: 24),
                    Text('Sharing audit',
                        style: Theme.of(context).textTheme.titleLarge),
                    if ((data!['sharing_records'] as List).isEmpty)
                      const Text('No biodata has been authorised.'),
                    for (final r in data!['sharing_records'] as List)
                      ListTile(
                          title: Text(r['original_name'] as String? ??
                              'Document ${shortId(r['document_id'])}'),
                          subtitle: Text(
                              'Authorised ${timestamp(r['created_at'])} by ${r['authoriser_email'] ?? shortId(r['authorised_by'])}\n${r['revoked_at'] == null ? 'Access active' : 'Revoked ${timestamp(r['revoked_at'])}'}')),
                  ]
                ]))));
  }
}
