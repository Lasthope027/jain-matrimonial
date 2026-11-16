import 'dart:convert';
import 'package:flutter/material.dart';
import 'auth_client.dart';
import 'profile_workspace.dart';
import 'admin_common.dart';
import 'admin_proposals.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.client});
  final AuthClient client;
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int selected = 0;
  String? profileStatus;
  void destination(int value) => setState(() {
        selected = value;
        if (value != 1) profileStatus = null;
      });
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final panel = switch (selected) {
      0 => OverviewPanel(
          client: widget.client,
          onProfiles: (status) => setState(() {
                profileStatus = status;
                selected = 1;
              }),
          onCustomers: () => destination(2)),
      1 => AdminProfilesPanel(
          key: ValueKey(profileStatus),
          client: widget.client,
          initialStatus: profileStatus),
      2 => CustomersPanel(client: widget.client),
      3 => AdminProposalsPanel(client: widget.client),
      _ => ActivityPanel(client: widget.client),
    };
    return Scaffold(
        appBar: AppBar(title: const Text('Jain Consultancy'), actions: [
          TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('Account'))
        ]),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: destination,
                destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        label: 'Overview'),
                    NavigationDestination(
                        icon: Icon(Icons.people_outline), label: 'Profiles'),
                    NavigationDestination(
                        icon: Icon(Icons.manage_accounts_outlined),
                        label: 'Customers'),
                    NavigationDestination(
                        icon: Icon(Icons.favorite_outline), label: 'Proposals'),
                    NavigationDestination(
                        icon: Icon(Icons.history), label: 'Activity')
                  ]),
        body: Row(children: [
          if (wide)
            NavigationRail(
                extended: MediaQuery.sizeOf(context).width >= 1200,
                selectedIndex: selected,
                onDestinationSelected: destination,
                labelType: MediaQuery.sizeOf(context).width >= 1200
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      label: Text('Overview')),
                  NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      label: Text('Profiles')),
                  NavigationRailDestination(
                      icon: Icon(Icons.manage_accounts_outlined),
                      label: Text('Customers')),
                  NavigationRailDestination(
                      icon: Icon(Icons.favorite_outline),
                      label: Text('Proposals')),
                  NavigationRailDestination(
                      icon: Icon(Icons.history), label: Text('Activity'))
                ]),
          if (wide) const VerticalDivider(width: 1),
          Expanded(child: panel)
        ]));
  }
}

class OverviewPanel extends StatefulWidget {
  const OverviewPanel(
      {super.key,
      required this.client,
      required this.onProfiles,
      required this.onCustomers});
  final AuthClient client;
  final void Function(String?) onProfiles;
  final VoidCallback onCustomers;
  @override
  State<OverviewPanel> createState() => _OverviewPanelState();
}

class _OverviewPanelState extends LiveState<OverviewPanel> {
  Map<String, dynamic>? stats;
  @override
  Future<void> load({bool quiet = false}) => perform(() async {
        final data = await widget.client.request('GET', '/admin/dashboard');
        if (mounted) setState(() => stats = data);
      }, quiet: quiet);
  Widget metric(String key, String label, {VoidCallback? action}) => SizedBox(
      width: 230,
      child: Card(
          child: InkWell(
              onTap: action,
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label),
                        const SizedBox(height: 12),
                        Text('${stats?[key] ?? 0}',
                            style: Theme.of(context).textTheme.headlineLarge)
                      ])))));
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        title('Consultancy overview'),
        const Text('A live view of registrations, verification and proposals.'),
        const SizedBox(height: 20),
        ...feedback(),
        if (stats != null) ...[
          Wrap(spacing: 12, runSpacing: 12, children: [
            metric('total_profiles', 'Total profiles',
                action: () => widget.onProfiles(null)),
            metric('pending_verification', 'Pending verification',
                action: () => widget.onProfiles('PENDING_VERIFICATION')),
            metric('approved_profiles', 'Approved profiles',
                action: () => widget.onProfiles('APPROVED')),
            metric('rejected_profiles', 'Rejected profiles',
                action: () => widget.onProfiles('REJECTED')),
            metric('inactive_profiles', 'Inactive profiles',
                action: () => widget.onProfiles('INACTIVE')),
            metric('total_customers', 'Customer accounts',
                action: widget.onCustomers),
            metric('active_customers', 'Active customer accounts',
                action: widget.onCustomers),
            metric('unassociated_profiles', 'Unlinked profiles'),
            metric('active_proposals', 'Active proposals'),
            metric('pending_responses', 'Pending responses'),
            metric('mutually_accepted_proposals', 'Mutually accepted'),
          ]),
          const SizedBox(height: 20),
          Text('Updated ${timestamp(stats!['generated_at'])}'),
          const SizedBox(height: 8),
          const Text(
              'Active proposals include pending and mutually accepted proposals. Pending responses count replies still awaited on pending proposals.')
        ]
      ]);
}

class AdminProfilesPanel extends StatefulWidget {
  const AdminProfilesPanel(
      {super.key, required this.client, this.initialStatus});
  final AuthClient client;
  final String? initialStatus;
  @override
  State<AdminProfilesPanel> createState() => _AdminProfilesPanelState();
}

class _AdminProfilesPanelState extends LiveState<AdminProfilesPanel> {
  final q = TextEditingController(),
      location = TextEditingController(),
      community = TextEditingController(),
      minAge = TextEditingController(),
      maxAge = TextEditingController();
  String? gender, status;
  bool unlinked = false;
  Map<String, String> applied = {};
  List<Map<String, dynamic>> rows = [];
  int offset = 0, total = 0;
  int? next;
  @override
  void initState() {
    status = widget.initialStatus;
    if (status != null) applied = {'status': status!};
    super.initState();
  }

  @override
  void dispose() {
    for (final controller in [q, location, community, minAge, maxAge]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> fetch() async {
    final query =
        Uri(queryParameters: {...applied, 'offset': '$offset', 'limit': '30'})
            .query;
    final data = await widget.client.request('GET', '/admin/profiles?$query');
    if (mounted)
      setState(() {
        rows = (data['items'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        total = data['total'] as int;
        next = data['next_offset'] as int?;
      });
  }

  @override
  Future<void> load({bool quiet = false}) => perform(fetch, quiet: quiet);
  void apply() {
    final low = int.tryParse(minAge.text.trim()),
        high = int.tryParse(maxAge.text.trim());
    if ((minAge.text.isNotEmpty && (low == null || low < 18 || low > 100)) ||
        (maxAge.text.isNotEmpty && (high == null || high < 18 || high > 100)) ||
        (low != null && high != null && low > high)) {
      setState(() => error =
          'Use ages from 18 to 100, with minimum no greater than maximum.');
      return;
    }
    applied = {
      if (q.text.trim().isNotEmpty) 'q': q.text.trim(),
      if (location.text.trim().isNotEmpty) 'location': location.text.trim(),
      if (community.text.trim().isNotEmpty) 'community': community.text.trim(),
      if (low != null) 'age_min': '$low',
      if (high != null) 'age_max': '$high',
      if (gender != null) 'gender': gender!,
      if (status != null) 'status': status!,
      if (unlinked) 'unassociated_only': 'true'
    };
    offset = 0;
    load();
  }

  Future<void> open([String? id]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProfileEditor(client: widget.client, profileId: id)));
    if (mounted) await load();
  }

  Widget input(TextEditingController controller, String label,
          {double width = 200, bool number = false}) =>
      SizedBox(
          width: width,
          child: TextField(
              controller: controller,
              keyboardType: number ? TextInputType.number : TextInputType.text,
              onSubmitted: (_) => apply(),
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder())));
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        title('Profile database'),
        Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
                onPressed: () => open(),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Create profile'))),
        const SizedBox(height: 20),
        Wrap(
            spacing: 12,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              input(q, 'Name or profile ID', width: 280),
              input(location, 'Location'),
              input(community, 'Community'),
              input(minAge, 'Minimum age', width: 140, number: true),
              input(maxAge, 'Maximum age', width: 140, number: true),
              SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                      key: ValueKey('gender-$gender'),
                      isExpanded: true,
                      initialValue: gender,
                      decoration: const InputDecoration(
                          labelText: 'Gender', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Any gender')),
                        for (final e in genders.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value))
                      ],
                      onChanged: (v) => setState(() => gender = v))),
              SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                      key: ValueKey('status-$status'),
                      isExpanded: true,
                      initialValue: status,
                      decoration: const InputDecoration(
                          labelText: 'Verification status',
                          border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Any status')),
                        for (final e in statusNames.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value))
                      ],
                      onChanged: (v) => setState(() => status = v))),
              FilterChip(
                  label: const Text('Unlinked profiles only'),
                  selected: unlinked,
                  onSelected: (v) => setState(() => unlinked = v)),
              FilledButton(
                  onPressed: busy ? null : apply,
                  child: const Text('Apply filters')),
              TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          for (final c in [
                            q,
                            location,
                            community,
                            minAge,
                            maxAge
                          ]) {
                            c.clear();
                          }
                          setState(() {
                            gender = null;
                            status = null;
                            unlinked = false;
                          });
                          apply();
                        },
                  child: const Text('Clear filters')),
            ]),
        const SizedBox(height: 20),
        ...feedback(),
        if (rows.isEmpty && !busy && error == null)
          const Text('No profiles match these filters.'),
        if (rows.isNotEmpty)
          table([
            'Name',
            'Profile ID',
            'Gender',
            'Location',
            'Community',
            'Status',
            ''
          ], [
            for (final row in rows)
              [
                Text(row['full_name'] as String),
                SelectableText(shortId(row['id'])),
                Text(genders[row['gender']] ?? ''),
                Text(row['current_location'] as String? ?? '—'),
                Text(row['community'] as String? ?? '—'),
                badge(statusNames[row['status']] ?? ''),
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

class CustomersPanel extends StatefulWidget {
  const CustomersPanel({super.key, required this.client});
  final AuthClient client;
  @override
  State<CustomersPanel> createState() => _CustomersPanelState();
}

class _CustomersPanelState extends LiveState<CustomersPanel> {
  final search = TextEditingController();
  String active = 'all';
  Map<String, String> applied = {};
  List<Map<String, dynamic>> rows = [];
  int offset = 0, total = 0;
  int? next;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> fetch() async {
    final query =
        Uri(queryParameters: {...applied, 'offset': '$offset', 'limit': '30'})
            .query;
    final data = await widget.client.request('GET', '/admin/customers?$query');
    if (mounted)
      setState(() {
        rows = (data['items'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        total = data['total'] as int;
        next = data['next_offset'] as int?;
      });
  }

  @override
  Future<void> load({bool quiet = false}) => perform(fetch, quiet: quiet);
  void apply() {
    offset = 0;
    applied = {
      if (search.text.trim().isNotEmpty) 'q': search.text.trim(),
      if (active != 'all') 'active': active
    };
    load();
  }

  Future<void> create() async {
    var email = '';
    final form = GlobalKey<FormState>();
    final selected = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Create customer account'),
                content: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'The customer verifies their email with a sign-in code. No password is set.'),
                      const SizedBox(height: 16),
                      TextFormField(
                          autofocus: true,
                          onChanged: (value) => email = value.trim(),
                          keyboardType: TextInputType.emailAddress,
                          maxLength: 254,
                          decoration: const InputDecoration(
                              labelText: 'Customer email'),
                          validator: (value) =>
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(value?.trim() ?? '')
                                  ? null
                                  : 'Enter a valid email address')
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
                      child: const Text('Create account'))
                ]));
    if (selected != true || !mounted) return;
    await perform(() async {
      await widget.client
          .request('POST', '/admin/customers', body: {'email': email});
      await fetch();
    });
  }

  Future<void> open(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CustomerDetail(client: widget.client, customerId: id)));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        title('Customer accounts'),
        Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: 300,
                  child: TextField(
                      controller: search,
                      onSubmitted: (_) => apply(),
                      decoration: const InputDecoration(
                          labelText: 'Search customer email',
                          border: OutlineInputBorder()))),
              SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                      initialValue: active,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Account status',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: 'all', child: Text('Any status')),
                        DropdownMenuItem(value: 'true', child: Text('Active')),
                        DropdownMenuItem(
                            value: 'false', child: Text('Inactive'))
                      ],
                      onChanged: (value) => setState(() => active = value!))),
              FilledButton(
                  onPressed: busy ? null : apply,
                  child: const Text('Apply filters')),
              OutlinedButton.icon(
                  onPressed: busy ? null : create,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Create customer'))
            ]),
        const SizedBox(height: 20),
        ...feedback(),
        if (rows.isEmpty && !busy && error == null)
          const Text('No customer accounts match these filters.'),
        if (rows.isNotEmpty)
          table([
            'Email',
            'Email verification',
            'Account',
            'Profiles',
            'Created',
            ''
          ], [
            for (final row in rows)
              [
                Text(row['email'] as String),
                Text(row['email_verified_at'] == null
                    ? 'Not yet verified'
                    : 'Verified'),
                badge(row['active'] == true ? 'Active' : 'Inactive'),
                Text('${row['profile_count']}'),
                Text(timestamp(row['created_at'])),
                TextButton(
                    onPressed: () => open(row['id'] as String),
                    child: const Text('Manage'))
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

class CustomerDetail extends StatefulWidget {
  const CustomerDetail(
      {super.key, required this.client, required this.customerId});
  final AuthClient client;
  final String customerId;
  @override
  State<CustomerDetail> createState() => _CustomerDetailState();
}

class _CustomerDetailState extends LiveState<CustomerDetail> {
  Map<String, dynamic>? account;
  Future<void> fetch() async {
    final result = await widget.client
        .request('GET', '/admin/customers/${widget.customerId}');
    if (mounted) setState(() => account = result);
  }

  @override
  Future<void> load({bool quiet = false}) => perform(fetch, quiet: quiet);
  Future<void> activation() async {
    final active = account!['active'] != true;
    final version = account!['version'];
    final selected = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(active
                    ? 'Activate customer account?'
                    : 'Deactivate customer account?'),
                content: Text(active
                    ? 'The customer can sign in again using a fresh email code.'
                    : 'This immediately signs the customer out on all devices. Linked profiles remain in the consultancy database.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Confirm'))
                ]));
    if (selected != true || !mounted) return;
    await perform(() async {
      final result = await widget.client.request(
          'PUT', '/admin/customers/${widget.customerId}/activation',
          body: {'version': version, 'active': active});
      if (mounted) setState(() => account = result);
    });
  }

  Future<void> link() async {
    final chosen = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => UnlinkedProfilePicker(client: widget.client));
    if (chosen == null || !mounted) return;
    await perform(() async {
      await widget.client.request(
          'PUT', '/admin/profiles/${chosen['id']}/account',
          body: {'version': chosen['version'], 'email': account!['email']});
      await fetch();
    });
  }

  Future<void> open(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProfileEditor(client: widget.client, profileId: id)));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Customer account')),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                ...feedback(),
                if (account != null) ...[
                  Text(account!['email'] as String,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: badge(
                          account!['active'] == true ? 'Active' : 'Inactive')),
                  Text(account!['email_verified_at'] == null
                      ? 'Email not yet verified'
                      : 'Email verified ${timestamp(account!['email_verified_at'])}'),
                  const SizedBox(height: 8),
                  Text('Created ${timestamp(account!['created_at'])}'),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    OutlinedButton(
                        onPressed: busy ? null : activation,
                        child: Text(account!['active'] == true
                            ? 'Deactivate account'
                            : 'Activate account')),
                    FilledButton.icon(
                        onPressed:
                            busy || account!['active'] != true ? null : link,
                        icon: const Icon(Icons.link),
                        label: const Text('Link existing profile'))
                  ]),
                  const SizedBox(height: 24),
                  Text('Associated profiles',
                      style: Theme.of(context).textTheme.titleLarge),
                  if ((account!['profiles'] as List).isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No profiles linked to this account.')),
                  for (final profile in account!['profiles'] as List)
                    Card(
                        child: ListTile(
                            title: Text(profile['full_name'] as String),
                            subtitle:
                                Text(statusNames[profile['status']] ?? ''),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => open(profile['id'] as String))),
                ]
              ]))));
}

class UnlinkedProfilePicker extends StatefulWidget {
  const UnlinkedProfilePicker({super.key, required this.client});
  final AuthClient client;
  @override
  State<UnlinkedProfilePicker> createState() => _UnlinkedProfilePickerState();
}

class _UnlinkedProfilePickerState extends State<UnlinkedProfilePicker> {
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
        'unassociated_only': 'true',
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
          title: const Text('Choose an unlinked profile'),
          content: SizedBox(
              width: 600,
              height: 440,
              child: Column(children: [
                TextField(
                    controller: search,
                    decoration: const InputDecoration(
                        labelText: 'Search by name or profile ID'),
                    onSubmitted: (_) {
                      offset = 0;
                      load();
                    }),
                Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                offset = 0;
                                load();
                              },
                        child: const Text('Search'))),
                if (busy) const LinearProgressIndicator(),
                if (error != null) Text(error!),
                Expanded(
                    child: ListView(children: [
                  if (rows.isEmpty && !busy)
                    const Text('No unlinked profiles found.'),
                  for (final row in rows)
                    ListTile(
                        title: Text(row['full_name'] as String),
                        subtitle: Text(
                            '${shortId(row['id'])} · ${statusNames[row['status']]}'),
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

class ActivityPanel extends StatefulWidget {
  const ActivityPanel({super.key, required this.client});
  final AuthClient client;
  @override
  State<ActivityPanel> createState() => _ActivityPanelState();
}

class _ActivityPanelState extends LiveState<ActivityPanel> {
  final search = TextEditingController();
  String applied = '';
  List<Map<String, dynamic>> rows = [];
  int offset = 0, total = 0;
  int? next;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> fetch() async {
    final query =
        Uri(queryParameters: {'q': applied, 'offset': '$offset', 'limit': '30'})
            .query;
    final result =
        await widget.client.request('GET', '/admin/audit-logs?$query');
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
  Future<void> load({bool quiet = false}) {
    if (quiet && offset > 0) return Future.value();
    return perform(fetch, quiet: quiet);
  }

  void apply() {
    offset = 0;
    applied = search.text.trim();
    load();
  }

  Future<void> details(Map<String, dynamic> row) => showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
              title: Text(row['action'] as String),
              content: SingleChildScrollView(
                  child: SelectableText(
                      'Time: ${timestamp(row['created_at'])}\nActor: ${row['actor_email'] ?? 'System'}\nEntity: ${row['entity_type']}\nReference: ${row['entity_id'] ?? '—'}\n\n${const JsonEncoder.withIndent('  ').convert(row['details'] ?? {})}')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'))
              ]));
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        title('System activity'),
        Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: 360,
                  child: TextField(
                      controller: search,
                      maxLength: 100,
                      decoration: const InputDecoration(
                          labelText: 'Search action, entity or actor email',
                          border: OutlineInputBorder()),
                      onSubmitted: (_) => apply())),
              FilledButton(
                  onPressed: busy ? null : apply, child: const Text('Search'))
            ]),
        ...feedback(),
        if (rows.isEmpty && !busy && error == null)
          const Text('No activity matches this search.'),
        if (rows.isNotEmpty)
          table([
            'When',
            'Actor',
            'Action',
            'Entity',
            ''
          ], [
            for (final row in rows)
              [
                Text(timestamp(row['created_at'])),
                Text(row['actor_email'] as String? ?? 'System'),
                Text(row['action'] as String),
                Text('${row['entity_type']} ${shortId(row['entity_id'])}'),
                TextButton(
                    onPressed: () => details(row), child: const Text('Details'))
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
