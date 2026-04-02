import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();
  final _githubCtrl = TextEditingController();
  final _portfolioCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _skillsCtrl = TextEditingController();
  final _educationCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  final _achievementsCtrl = TextEditingController();
  final _certificationsCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _profileId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _phoneCtrl, _linkedinCtrl, _githubCtrl, _portfolioCtrl,
      _summaryCtrl, _skillsCtrl, _educationCtrl, _experienceCtrl,
      _achievementsCtrl, _certificationsCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final uid = _db.auth.currentUser!.id;
      final data = await _db.from('user_profiles').select().eq('user_id', uid).maybeSingle();
      if (data != null) {
        _profileId = data['id'];
        _nameCtrl.text = data['full_name'] ?? '';
        _phoneCtrl.text = data['phone'] ?? '';
        _linkedinCtrl.text = data['linkedin_url'] ?? '';
        _githubCtrl.text = data['github_url'] ?? '';
        _portfolioCtrl.text = data['portfolio_url'] ?? '';
        _summaryCtrl.text = data['summary'] ?? '';
        _achievementsCtrl.text = data['achievements'] ?? '';
        final skills = data['skills'];
        if (skills is List) { _skillsCtrl.text = skills.join(', '); }
        final education = data['education'];
        if (education is List) { _educationCtrl.text = education.join('\n'); }
        else if (education is String) { _educationCtrl.text = education; }
        final experience = data['experience'];
        if (experience is List) { _experienceCtrl.text = experience.join('\n'); }
        else if (experience is String) { _experienceCtrl.text = experience; }
        final certs = data['certifications'];
        if (certs is List) { _certificationsCtrl.text = certs.join('\n'); }
        else if (certs is String) { _certificationsCtrl.text = certs; }
      } else {
        final meta = _db.auth.currentUser?.userMetadata;
        if (meta?['full_name'] != null) _nameCtrl.text = meta!['full_name'];
      }
    } catch (_) {
      _snack('Failed to load profile', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final uid = _db.auth.currentUser!.id;
      final skillsList = _skillsCtrl.text
          .split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final certsList = _certificationsCtrl.text
          .split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

      final payload = {
        'user_id': uid,
        'email': _db.auth.currentUser?.email ?? '',
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'linkedin_url': _linkedinCtrl.text.trim().isEmpty ? null : _linkedinCtrl.text.trim(),
        'github_url': _githubCtrl.text.trim().isEmpty ? null : _githubCtrl.text.trim(),
        'portfolio_url': _portfolioCtrl.text.trim().isEmpty ? null : _portfolioCtrl.text.trim(),
        'summary': _summaryCtrl.text.trim().isEmpty ? null : _summaryCtrl.text.trim(),
        'skills': skillsList,
        'education': _educationCtrl.text.trim().isEmpty ? null : _educationCtrl.text.trim(),
        'experience': _experienceCtrl.text.trim().isEmpty ? null : _experienceCtrl.text.trim(),
        'achievements': _achievementsCtrl.text.trim().isEmpty ? null : _achievementsCtrl.text.trim(),
        'certifications': certsList,
      };

      if (_profileId != null) {
        await _db.from('user_profiles').update(payload).eq('id', _profileId!);
      } else {
        final res = await _db.from('user_profiles').insert(payload).select().single();
        _profileId = res['id'];
      }
      _snack('Profile saved!');
    } catch (e) {
      _snack('Failed to save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirm == true) {
      await _db.auth.signOut();
      if (mounted) context.go('/login');
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red[700] : Colors.green[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _db.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign Out'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Center(child: Column(children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(Icons.person, size: 40,
                            color: theme.colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 8),
                      Text(email, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    ])),
                    const SizedBox(height: 24),

                    _section('Basic Info'),
                    _field(_nameCtrl, 'Full Name *', Icons.person_outline, required: true),
                    const SizedBox(height: 12),
                    _field(_phoneCtrl, 'Phone Number', Icons.phone_outlined,
                        keyboard: TextInputType.phone),
                    const SizedBox(height: 20),

                    _section('Social Links'),
                    _field(_linkedinCtrl, 'LinkedIn URL', Icons.link),
                    const SizedBox(height: 12),
                    _field(_githubCtrl, 'GitHub URL', Icons.code,
                        keyboard: TextInputType.url),
                    const SizedBox(height: 12),
                    _field(_portfolioCtrl, 'Portfolio / Website URL', Icons.web,
                        keyboard: TextInputType.url),
                    const SizedBox(height: 20),

                    _section('Professional Summary'),
                    _multiline(_summaryCtrl, 'Brief professional summary...', 3),
                    const SizedBox(height: 20),

                    _section('Skills'),
                    _field(_skillsCtrl, 'e.g. Python, Flutter, SQL', Icons.psychology_outlined),
                    Text('Separate with commas', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 20),

                    _section('Education'),
                    _multiline(_educationCtrl,
                        'e.g. B.Tech Computer Science, XYZ University, 2022', 3),
                    Text('One entry per line', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 20),

                    _section('Work Experience'),
                    _multiline(_experienceCtrl,
                        'e.g. Software Engineer at ABC Corp, Jan 2023 – Present\n• Built X feature\n• Improved Y by 30%', 5),
                    Text('One role per paragraph', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 20),

                    _section('Achievements'),
                    _multiline(_achievementsCtrl,
                        'e.g. Won XYZ Hackathon 2024\nPublished paper on ABC\nRanked top 5% on Leetcode', 4),
                    Text('One achievement per line', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 20),

                    _section('Certifications'),
                    _multiline(_certificationsCtrl,
                        'e.g. AWS Solutions Architect – Amazon, 2024\nGoogle Data Analytics – Coursera, 2023', 4),
                    Text('One certification per line: Name – Issuer, Year',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'Saving...' : 'Save Profile',
                            style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: Colors.grey[300])),
    ]),
  );

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {bool required = false, TextInputType keyboard = TextInputType.text}) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
      );

  Widget _multiline(TextEditingController ctrl, String hint, int lines) =>
      TextField(
        controller: ctrl,
        maxLines: lines,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      );
}
