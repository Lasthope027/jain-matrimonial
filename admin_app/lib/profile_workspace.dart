import 'dart:typed_data';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'auth_client.dart';

const statusNames = {
  'PENDING_VERIFICATION': 'Pending verification',
  'APPROVED': 'Approved',
  'REJECTED': 'Rejected',
  'INACTIVE': 'Inactive'
};
const genders = {'MALE': 'Male', 'FEMALE': 'Female', 'OTHER': 'Other'};
const maritalChoices = {
  'NEVER_MARRIED': 'Never married',
  'DIVORCED': 'Divorced',
  'WIDOWED': 'Widowed',
  'SEPARATED': 'Separated'
};

class ProfileWorkspace extends StatefulWidget {
  const ProfileWorkspace({super.key, required this.client});
  final AuthClient client;
  @override
  State<ProfileWorkspace> createState() => _ProfileWorkspaceState();
}

class _ProfileWorkspaceState extends State<ProfileWorkspace> {
  List<Map<String, dynamic>> items = [];
  int? next;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final path =
          widget.client.administrator ? '/admin/profiles' : '/profiles';
      final result = await widget.client
          .request('GET', '$path?offset=${more ? next ?? 0 : 0}&limit=30');
      if (mounted)
        setState(() {
          final rows = (result['items'] as List)
              .map((e) => Map<String, dynamic>.from(e));
          items = more ? [...items, ...rows] : rows.toList();
          next = result['next_offset'] as int?;
        });
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open([String? id]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProfileEditor(client: widget.client, profileId: id)));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.client.administrator
                ? 'Profile management'
                : 'My profiles'),
            actions: [
              IconButton(
                  onPressed: busy ? null : () => load(),
                  tooltip: 'Refresh profiles',
                  icon: const Icon(Icons.refresh))
            ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => open(),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Create profile')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    children: [
                      Text(
                          widget.client.administrator
                              ? 'Manage consultancy profiles'
                              : 'Profiles managed by your account',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(widget.client.administrator
                          ? 'Create a profile from office biodata, or open one to review and verify it.'
                          : 'Create a separate profile for each family member. The consultancy reviews every submitted profile.'),
                      if (busy)
                        const Padding(
                            padding: EdgeInsets.all(20),
                            child: LinearProgressIndicator()),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              Text(error!),
                              TextButton(
                                  onPressed: () => load(),
                                  child: const Text('Try again'))
                            ])),
                      if (!busy && error == null && items.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                                'No profiles yet. Use Create profile to get started.')),
                      for (final item in items)
                        Card(
                            child: ListTile(
                                title: Text(item['full_name'] as String),
                                subtitle: Text(
                                    '${genders[item['gender']] ?? ''} · ${item['current_location'] ?? 'Location not specified'}\n${statusNames[item['status']]}'),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => open(item['id'] as String))),
                      if (next != null)
                        TextButton(
                            onPressed: busy ? null : () => load(more: true),
                            child: const Text('Load more')),
                    ]))),
      );
}

class FieldSpec {
  const FieldSpec(this.keyName, this.label,
      {this.number = false,
      this.money = false,
      this.multiline = false,
      this.choices = false});
  final String keyName, label;
  final bool number, money, multiline, choices;
}

const personalFields = [
  FieldSpec('full_name', 'Full name'),
  FieldSpec('height_cm', 'Height (cm)', number: true),
  FieldSpec('sub_community', 'Sub-community'),
  FieldSpec('mother_tongue', 'Mother tongue'),
  FieldSpec('current_location', 'Current location'),
  FieldSpec('native_place', 'Native place')
];
const educationFields = [
  FieldSpec('education.qualification', 'Highest qualification'),
  FieldSpec('education.college', 'College / university'),
  FieldSpec('education.profession', 'Profession'),
  FieldSpec('education.company', 'Company / organisation'),
  FieldSpec('education.employment_location', 'Employment location'),
  FieldSpec('education.annual_income', 'Annual income (₹, optional)',
      money: true)
];
const familyFields = [
  FieldSpec('family.father_name', "Father’s name"),
  FieldSpec('family.father_occupation', "Father’s occupation"),
  FieldSpec('family.mother_name', "Mother’s name"),
  FieldSpec('family.mother_occupation', "Mother’s occupation"),
  FieldSpec('family.siblings', 'Number of siblings', number: true),
  FieldSpec('family.family_location', 'Family location'),
  FieldSpec('family.additional_information', 'Additional family information',
      multiline: true)
];
const preferenceFields = [
  FieldSpec('preferences.age_min', 'Preferred minimum age', number: true),
  FieldSpec('preferences.age_max', 'Preferred maximum age', number: true),
  FieldSpec('preferences.height_min_cm', 'Preferred minimum height (cm)',
      number: true),
  FieldSpec('preferences.height_max_cm', 'Preferred maximum height (cm)',
      number: true),
  FieldSpec('preferences.locations', 'Preferred locations', choices: true),
  FieldSpec('preferences.education', 'Education preferences', choices: true),
  FieldSpec('preferences.professions', 'Profession preferences', choices: true),
  FieldSpec('preferences.additional_expectations', 'Additional expectations',
      multiline: true)
];
const allFields = [
  ...personalFields,
  ...educationFields,
  ...familyFields,
  ...preferenceFields
];

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.client, this.profileId});
  final AuthClient client;
  final String? profileId;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final form = GlobalKey<FormState>();
  final controllers = {
    for (final field in allFields) field.keyName: TextEditingController()
  };
  final accountEmail = TextEditingController();
  String? id, gender, marital, community, error, notice;
  DateTime? birth;
  int version = 1;
  String? savedPayload;
  String status = 'PENDING_VERIFICATION';
  String? verificationNote;
  Set<String> communities = {}, maritalPreferences = {};
  List<Map<String, dynamic>> documents = [];
  bool busy = false;
  bool get admin => widget.client.administrator;
  bool get canEdit => admin || status != 'INACTIVE';

  @override
  void initState() {
    super.initState();
    id = widget.profileId;
    if (id != null) reload();
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    accountEmail.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() work) async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
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

  void populate(Map<String, dynamic> data) {
    id = data['id'] as String;
    version = data['version'] as int;
    status = data['status'] as String;
    verificationNote = data['verification_note'] as String?;
    gender = data['gender'] as String?;
    marital = data['marital_status'] as String?;
    community = data['community'] as String?;
    birth = DateTime.parse(data['date_of_birth'] as String);
    accountEmail.text = data['account_email'] as String? ?? '';
    for (final field in allFields) {
      final path = field.keyName.split('.');
      final value =
          path.length == 1 ? data[path[0]] : (data[path[0]] as Map?)?[path[1]];
      controllers[field.keyName]!.text =
          value is List ? value.join(', ') : value?.toString() ?? '';
    }
    final preferences = data['preferences'] as Map? ?? {};
    communities = Set<String>.from(preferences['communities'] as List? ?? []);
    maritalPreferences =
        Set<String>.from(preferences['marital_statuses'] as List? ?? []);
    savedPayload = jsonEncode(payload());
  }

  Future<void> read() async {
    final data = await widget.client.request('GET', '/profiles/$id');
    final files = await widget.client.request('GET', '/profiles/$id/documents');
    if (mounted)
      setState(() {
        populate(data);
        documents = (files['items'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
  }

  bool hasChanges() {
    if (savedPayload == null) return false;
    try {
      return savedPayload != jsonEncode(payload());
    } catch (_) {
      return true;
    }
  }

  bool requireSaved() {
    if (!hasChanges()) return true;
    setState(() => error =
        'Save profile changes before managing documents, accounts or verification.');
    return false;
  }

  Future<void> reload() async {
    if (hasChanges() &&
        !await confirm('Discard unsaved changes?',
            'Reload the saved profile and discard your changes?')) return;
    if (mounted) await perform(read);
  }

  Map<String, dynamic> payload() {
    final result = <String, dynamic>{
      'gender': gender,
      'date_of_birth': birth!.toIso8601String().split('T').first,
      'marital_status': marital,
      'community': community,
      'education': <String, dynamic>{},
      'family': <String, dynamic>{},
      'preferences': <String, dynamic>{}
    };
    for (final field in allFields) {
      final value = controllers[field.keyName]!.text.trim();
      final dynamic converted = field.choices
          ? value
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : value.isEmpty
              ? null
              : field.number
                  ? int.parse(value)
                  : value;
      final path = field.keyName.split('.');
      if (path.length == 1) {
        result[path[0]] = converted;
      } else {
        (result[path[0]] as Map<String, dynamic>)[path[1]] = converted;
      }
    }
    (result['preferences'] as Map<String, dynamic>).addAll(<String, dynamic>{
      'communities': communities.toList(),
      'marital_statuses': maritalPreferences.toList()
    });
    if (id != null) {
      result['version'] = version;
    } else if (admin && accountEmail.text.trim().isNotEmpty) {
      result['account_email'] = accountEmail.text.trim();
    }
    return result;
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (birth == null) {
      setState(() => error = 'Choose the date of birth.');
      return;
    }
    await perform(() async {
      final wasNew = id == null;
      final result = await widget.client.request(wasNew ? 'POST' : 'PUT',
          wasNew ? (admin ? '/admin/profiles' : '/profiles') : '/profiles/$id',
          body: payload());
      if (mounted)
        setState(() {
          populate(result);
          notice = 'Profile saved. ${statusNames[status]}.';
        });
    });
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (dialogContext) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Confirm'))
              ])) ??
      false;

  Future<void> changeStatus(String value) async {
    if (!requireSaved()) return;
    var note = verificationNote ?? '';
    final selected = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text('Mark as ${statusNames[value]!.toLowerCase()}?'),
                content: TextFormField(
                    initialValue: note,
                    onChanged: (value) => note = value,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: InputDecoration(
                        labelText: value == 'REJECTED'
                            ? 'Reason (required)'
                            : 'Note (optional)')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Confirm'))
                ]));
    final reason = note.trim();
    if (selected != true || !mounted) return;
    if (value == 'REJECTED' && reason.isEmpty) {
      setState(() => error = 'Enter a reason for rejection.');
      return;
    }
    await perform(() async {
      final result = await widget.client.request(
          'PUT', '/admin/profiles/$id/verification', body: {
        'version': version,
        'status': value,
        'note': reason.isEmpty ? null : reason
      });
      if (mounted) setState(() => populate(result));
    });
  }

  Future<void> associate({bool unlink = false}) async {
    if (!requireSaved()) return;
    String? email;
    if (unlink) {
      if (!await confirm('Remove account link?',
          'The customer will lose access to this profile and its documents.'))
        return;
    } else {
      var input = accountEmail.text;
      final selected = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: const Text('Link a registered customer'),
                  content: TextFormField(
                      initialValue: input,
                      onChanged: (value) => input = value,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Registered customer email')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Link account'))
                  ]));
      email = input.trim();
      if (selected != true || !mounted) return;
      if (email.isEmpty) {
        setState(() => error = 'Enter the registered customer email.');
        return;
      }
    }
    if (!mounted) return;
    await perform(() async {
      final result = await widget.client.request(
          'PUT', '/admin/profiles/$id/account',
          body: {'version': version, 'email': email});
      if (mounted) setState(() => populate(result));
    });
  }

  Future<void> upload(String kind) async {
    if (!requireSaved()) return;
    final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: kind == 'PHOTO'
            ? ['jpg', 'jpeg', 'png']
            : ['pdf', 'jpg', 'jpeg', 'png']);
    if (file == null || !mounted) return;
    await perform(() async {
      final length = await file.length();
      if (length != null && length > 10 * 1024 * 1024)
        throw const AuthException('Maximum file size is 10 MiB.');
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (builder.length + chunk.length > 10 * 1024 * 1024)
          throw const AuthException('Maximum file size is 10 MiB.');
        builder.add(chunk);
      }
      await widget.client
          .upload(id!, version, file.name, kind, builder.takeBytes());
      await read();
      if (mounted)
        setState(() => notice = 'Document uploaded. ${statusNames[status]}.');
    });
  }

  Future<void> download(Map<String, dynamic> document) => perform(() async {
        final bytes = await widget.client.download(document['id'] as String);
        final destination = await FilePicker.saveFile(
            dialogTitle: 'Save private document',
            fileName: document['original_name'] as String,
            bytes: bytes);
        if (mounted && destination != null)
          setState(() => notice = 'Document saved to your chosen location.');
      });

  Future<void> remove(Map<String, dynamic> document) async {
    if (!requireSaved()) return;
    if (!await confirm('Remove document?',
        'Remove ${document['original_name']} from this profile?')) return;
    if (!mounted) return;
    await perform(() async {
      await widget.client
          .request('DELETE', '/documents/${document['id']}?version=$version');
      await read();
    });
  }

  Widget field(FieldSpec specification) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
          controller: controllers[specification.keyName],
          enabled: !busy && canEdit,
          decoration: InputDecoration(
              labelText: specification.label,
              border: const OutlineInputBorder(),
              helperText: specification.choices
                  ? 'Separate choices with commas'
                  : null),
          keyboardType: specification.number || specification.money
              ? const TextInputType.numberWithOptions(decimal: true)
              : specification.multiline
                  ? TextInputType.multiline
                  : TextInputType.text,
          maxLength: specification.choices
              ? 6000
              : specification.multiline
                  ? 4000
                  : specification.keyName == 'sub_community'
                      ? 100
                      : specification.keyName == 'mother_tongue'
                          ? 80
                          : 200,
          maxLines: specification.multiline ? 3 : 1,
          validator: (value) {
            final text = (value ?? '').trim();
            if (specification.keyName == 'full_name' && text.isEmpty)
              return 'Enter the full name';
            if (text.isEmpty) return null;
            if (specification.choices) {
              final choices = text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (choices.length > 30 || choices.any((e) => e.length > 200))
                return 'Use up to 30 choices, each up to 200 characters';
            }
            if (specification.number && int.tryParse(text) == null)
              return 'Enter a whole number';
            if (specification.money &&
                !RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(text))
              return 'Enter a positive amount with at most two decimal places';
            if (specification.number) {
              final n = int.parse(text);
              if (specification.keyName.contains('height') &&
                  (n < 50 || n > 300)) return 'Use a height from 50 to 300 cm';
              if (specification.keyName.contains('age_') && (n < 18 || n > 100))
                return 'Use an age from 18 to 100';
              if (specification.keyName.endsWith('siblings') &&
                  (n < 0 || n > 30)) return 'Use a number from 0 to 30';
              final minimumKey = specification.keyName == 'preferences.age_max'
                  ? 'preferences.age_min'
                  : specification.keyName == 'preferences.height_max_cm'
                      ? 'preferences.height_min_cm'
                      : null;
              if (minimumKey != null) {
                final minimum =
                    int.tryParse(controllers[minimumKey]!.text.trim());
                if (minimum != null && n < minimum)
                  return 'Maximum must be at least the minimum';
              }
            }
            return null;
          }));

  Widget heading(String title) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge));
  Widget dropdown(String label, String? value, Map<String, String> options,
          void Function(String?) select, {bool required = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<String>(
              key: ValueKey('$label-$value'),
              initialValue: value,
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder()),
              items: options.entries
                  .map((entry) => DropdownMenuItem(
                      value: entry.key, child: Text(entry.value)))
                  .toList(),
              onChanged: busy || !canEdit ? null : select,
              validator: (value) =>
                  required && value == null ? 'Choose $label' : null));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(id == null ? 'Create profile' : 'Profile details'),
            actions: [
              if (id != null)
                IconButton(
                    onPressed: busy ? null : reload,
                    tooltip: 'Reload profile',
                    icon: const Icon(Icons.refresh))
            ]),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                    onPressed: busy || !canEdit ? null : save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(busy ? 'Please wait…' : 'Save profile')))),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Form(
                    key: form,
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (busy) const LinearProgressIndicator(),
                              if (error != null)
                                Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Semantics(
                                        liveRegion: true,
                                        child: Text(error!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error)))),
                              if (notice != null)
                                Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(notice!)),
                              if (id != null) ...[
                                Text(statusNames[status]!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                if (verificationNote != null)
                                  Text('Consultancy note: $verificationNote')
                              ],
                              if (!canEdit)
                                const Text(
                                    'This profile is inactive. Contact the consultancy to make changes.'),
                              heading('Personal information'),
                              field(personalFields.first),
                              dropdown('Gender', gender, genders,
                                  (value) => setState(() => gender = value),
                                  required: true),
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: OutlinedButton.icon(
                                      onPressed: busy || !canEdit
                                          ? null
                                          : () async {
                                              final today = DateTime.now();
                                              final selected =
                                                  await showDatePicker(
                                                      context: context,
                                                      initialDate:
                                                          birth ??
                                                              DateTime(
                                                                  today.year -
                                                                      25,
                                                                  1,
                                                                  1),
                                                      firstDate: DateTime(
                                                          today.year - 101,
                                                          today.month,
                                                          today.day + 1),
                                                      lastDate: DateTime(
                                                          today.year - 18,
                                                          today.month,
                                                          today.day));
                                              if (selected != null && mounted)
                                                setState(
                                                    () => birth = selected);
                                            },
                                      icon: const Icon(Icons.calendar_month),
                                      label: Text(birth == null
                                          ? 'Choose date of birth'
                                          : 'Date of birth: ${birth!.toIso8601String().split('T').first}'))),
                              dropdown(
                                  'Marital status',
                                  marital,
                                  maritalChoices,
                                  (value) => setState(() => marital = value)),
                              dropdown(
                                  'Jain community',
                                  community,
                                  {
                                    for (final name in {
                                      'Digambar',
                                      'Shwetambar',
                                      'Other',
                                      if (community != null) community!
                                    })
                                      name: name
                                  },
                                  (value) => setState(() => community = value)),
                              for (final specification
                                  in personalFields.skip(1))
                                field(specification),
                              heading('Education and career'),
                              for (final specification in educationFields)
                                field(specification),
                              heading('Family information'),
                              for (final specification in familyFields)
                                field(specification),
                              heading('Partner preferences'),
                              for (final specification in preferenceFields)
                                field(specification),
                              const Text('Community preferences'),
                              Wrap(spacing: 8, children: [
                                for (final name in {
                                  'Digambar',
                                  'Shwetambar',
                                  'Other',
                                  ...communities
                                })
                                  FilterChip(
                                      label: Text(name),
                                      selected: communities.contains(name),
                                      onSelected: busy || !canEdit
                                          ? null
                                          : (selected) => setState(() {
                                                selected
                                                    ? communities.add(name)
                                                    : communities.remove(name);
                                              }))
                              ]),
                              const SizedBox(height: 16),
                              const Text('Marital status preferences'),
                              Wrap(spacing: 8, children: [
                                for (final entry in maritalChoices.entries)
                                  FilterChip(
                                      label: Text(entry.value),
                                      selected: maritalPreferences
                                          .contains(entry.key),
                                      onSelected: busy || !canEdit
                                          ? null
                                          : (selected) => setState(() {
                                                selected
                                                    ? maritalPreferences
                                                        .add(entry.key)
                                                    : maritalPreferences
                                                        .remove(entry.key);
                                              }))
                              ]),
                              if (admin) ...[
                                heading('Customer account'),
                                if (id == null)
                                  TextFormField(
                                      controller: accountEmail,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Registered customer email (optional)',
                                          helperText:
                                              'Leave blank for an office-created profile without an account.'))
                                else ...[
                                  Text(accountEmail.text.isEmpty
                                      ? 'No customer account linked'
                                      : accountEmail.text),
                                  Wrap(spacing: 12, children: [
                                    OutlinedButton(
                                        onPressed:
                                            busy ? null : () => associate(),
                                        child: const Text(
                                            'Link customer account')),
                                    if (accountEmail.text.isNotEmpty)
                                      TextButton(
                                          onPressed: busy
                                              ? null
                                              : () => associate(unlink: true),
                                          child:
                                              const Text('Remove account link'))
                                  ])
                                ]
                              ],
                              heading('Photographs and biodata'),
                              if (id == null)
                                const Text(
                                    'Save the profile to add photographs and biodata.')
                              else ...[
                                const Text(
                                    'PDF, JPG, JPEG or PNG · up to 10 MiB per file'),
                                Wrap(spacing: 12, children: [
                                  OutlinedButton.icon(
                                      onPressed: busy || !canEdit
                                          ? null
                                          : () => upload('PHOTO'),
                                      icon: const Icon(
                                          Icons.add_photo_alternate_outlined),
                                      label: const Text('Add photograph')),
                                  OutlinedButton.icon(
                                      onPressed: busy || !canEdit
                                          ? null
                                          : () => upload('BIODATA'),
                                      icon: const Icon(Icons.upload_file),
                                      label: const Text('Add biodata'))
                                ]),
                                for (final document in documents)
                                  ListTile(
                                      title: Text(
                                          document['original_name'] as String),
                                      subtitle: Text(document['kind'] == 'PHOTO'
                                          ? 'Photograph'
                                          : 'Biodata'),
                                      trailing: Wrap(children: [
                                        IconButton(
                                            onPressed: busy
                                                ? null
                                                : () => download(document),
                                            tooltip: 'Save document',
                                            icon: const Icon(Icons.download)),
                                        IconButton(
                                            onPressed: busy || !canEdit
                                                ? null
                                                : () => remove(document),
                                            tooltip: 'Remove document',
                                            icon: const Icon(
                                                Icons.delete_outline))
                                      ]))
                              ],
                              if (admin && id != null) ...[
                                heading('Verification'),
                                Wrap(spacing: 12, runSpacing: 8, children: [
                                  for (final value in [
                                    'APPROVED',
                                    'REJECTED',
                                    'PENDING_VERIFICATION',
                                    'INACTIVE'
                                  ])
                                    OutlinedButton(
                                        onPressed: busy
                                            ? null
                                            : () => changeStatus(value),
                                        child: Text(statusNames[value]!))
                                ])
                              ],
                              const SizedBox(height: 24),
                              const Text(
                                  'Changes to approved biodata or documents require consultancy verification again.'),
                            ]))))),
      );
}
