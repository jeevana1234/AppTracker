import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  final Map<String, bool> _autoApplying = {};
  static const _backendUrl = 'http://localhost:8000';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _db.auth.currentUser!.id;
      final data = await _db
          .from('job_applications')
          .select()
          .eq('user_id', uid)
          .order('updated_at', ascending: false);
      setState(() => _jobs = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDialog([Map<String, dynamic>? existing]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _JobDialog(existing: existing),
    );
    if (result == null) return;
    try {
      final uid = _db.auth.currentUser!.id;
      if (existing == null) {
        await _db.from('job_applications').insert({...result, 'user_id': uid});
      } else {
        await _db
            .from('job_applications')
            .update(result)
            .eq('id', existing['id']);
      }
      _load();
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _delete(String id) async {
    if (id.isEmpty) return;
    try {
      await _db.from('job_applications').delete().eq('id', id);
      if (mounted) _load();
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> job) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Job'),
        content: Text('Delete "${job['company']} — ${job['role']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _delete(job['id']?.toString() ?? '');
  }

  Future<void> _autoApply(Map<String, dynamic> job) async {
    setState(() => _autoApplying[job['id']] = true);
    try {
      final uid = _db.auth.currentUser!.id;
      final resp = await http
          .post(
            Uri.parse('$_backendUrl/monitor/direct-apply'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': uid,
              'job_application_id': job['id'],
            }),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        _snack('✅ ${data['message']}');
        _load();
      } else {
        _snack('Auto-apply: ${data['message'] ?? data['detail']}',
            error: true);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _autoApplying.remove(job['id']));
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red[700] : null,
    ));
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'interview':
        return Colors.orange;
      case 'offer':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Applications'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _jobs.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _jobs.length,
                    itemBuilder: (_, i) => _jobCard(_jobs[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Job'),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.work_off_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No job applications yet',
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add First Job'),
            ),
          ],
        ),
      );

  Widget _jobCard(Map<String, dynamic> job) {
    final color = _statusColor(job['status']);
    final hasUrl = (job['job_url'] as String? ?? '').isNotEmpty;
    final isApplying = _autoApplying[job['id']] == true;
    final autoApplied = job['auto_applied_at'] != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: avatar + company/role + status chip
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withAlpha(30),
                  child: Text(
                    ((job['company'] as String?) ?? '').isNotEmpty
                        ? ((job['company'] as String?) ?? '')[0].toUpperCase()
                        : '?',
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job['company'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(job['role'] ?? '',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ),
                _statusChip(job['status'] ?? 'applied', color),
              ],
            ),
            // Auto-applied badge
            if (autoApplied) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(width: 48),
                  Icon(Icons.check_circle_outline,
                      size: 13, color: Colors.green[700]),
                  const SizedBox(width: 4),
                  Text('Auto-applied',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
            const SizedBox(height: 4),
            // Action buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Auto Apply button (only if job URL exists)
                if (hasUrl) ...[
                  if (isApplying)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => _autoApply(job),
                      icon: const Icon(Icons.rocket_launch_outlined, size: 15),
                      label: const Text('Auto Apply',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.green[700],
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact),
                    ),
                ],
                // Edit button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _openDialog(job),
                  tooltip: 'Edit',
                  color: Colors.blue[700],
                  visualDensity: VisualDensity.compact,
                ),
                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _confirmDelete(job),
                  tooltip: 'Delete',
                  color: Colors.red[700],
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(status,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w500)),
      );
}

// ──────────────────────────────────────────────
// Add / Edit dialog
// ──────────────────────────────────────────────
class _JobDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _JobDialog({this.existing});

  @override
  State<_JobDialog> createState() => _JobDialogState();
}

class _JobDialogState extends State<_JobDialog> {
  final _company = TextEditingController();
  final _role = TextEditingController();
  final _jobUrl = TextEditingController();
  final _portalUsername = TextEditingController();
  final _portalPassword = TextEditingController();
  final _notes = TextEditingController();
  String _status = 'applied';
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing case final e?) {
      _company.text = e['company'] ?? '';
      _role.text = e['role'] ?? '';
      _jobUrl.text = e['job_url'] ?? '';
      _portalUsername.text = e['portal_username'] ?? '';
      _portalPassword.text = e['portal_password'] ?? '';
      _notes.text = e['notes'] ?? '';
      _status = e['status'] ?? 'applied';
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _role.dispose();
    _jobUrl.dispose();
    _portalUsername.dispose();
    _portalPassword.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.existing == null ? 'Add Job Application' : 'Edit Job'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(_company, 'Company *', Icons.business),
          const SizedBox(height: 12),
          _field(_role, 'Job Role *', Icons.work_outline),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(
                labelText: 'Status', border: OutlineInputBorder()),
            items: ['applied', 'interview', 'offer', 'rejected']
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _status = v!),
          ),
          const SizedBox(height: 12),
          _field(_jobUrl, 'Job URL (for Auto Apply)', Icons.link),
          const SizedBox(height: 10),
          // Portal login credentials section
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withAlpha(60)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.lock_outline, size: 14, color: Colors.blue[700]),
                  const SizedBox(width: 6),
                  Text('Portal Login (optional)',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                Text(
                    'If provided, Auto Apply will log in to the portal for you',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 10),
                _field(_portalUsername, 'Username / Email',
                    Icons.person_outline),
                const SizedBox(height: 10),
                TextField(
                  controller: _portalPassword,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
              alignLabelWithHint: true,
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_company.text.trim().isEmpty || _role.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(context, {
              'company': _company.text.trim(),
              'role': _role.text.trim(),
              'status': _status,
              if (_jobUrl.text.trim().isNotEmpty)
                'job_url': _jobUrl.text.trim(),
              if (_portalUsername.text.trim().isNotEmpty)
                'portal_username': _portalUsername.text.trim(),
              if (_portalPassword.text.trim().isNotEmpty)
                'portal_password': _portalPassword.text.trim(),
              if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) =>
      TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
      );
}
