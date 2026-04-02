import 'package:flutter/material.dart';
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
          .order('created_at', ascending: false);
      setState(() => _jobs = List<Map<String, dynamic>>.from(data));
    } catch (_) {
      _snack('Failed to load jobs', error: true);
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
        await _db
            .from('job_applications')
            .insert({...result, 'user_id': uid});
      } else {
        await _db
            .from('job_applications')
            .update(result)
            .eq('id', existing['id']);
      }
      _load();
    } catch (_) {
      _snack('Failed to save', error: true);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _db.from('job_applications').delete().eq('id', id);
      _load();
    } catch (_) {
      _snack('Failed to delete', error: true);
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
    return Dismissible(
      key: Key(job['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red[700],
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white),
            Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Job'),
          content:
              Text('Delete "${job['company']} — ${job['role']}"?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete')),
          ],
        ),
      ),
      onDismissed: (_) => _delete(job['id']),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withAlpha(30),
            child: Text(
              (job['company'] as String).isNotEmpty
                  ? (job['company'] as String)[0].toUpperCase()
                  : '?',
              style:
                  TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(job['company'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(job['role'] ?? ''),
          trailing: _statusChip(job['status'] ?? 'applied', color),
          onTap: () => _openDialog(job),
        ),
      ),
    );
  }

  Widget _statusChip(String status, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
  final _notes = TextEditingController();
  String _status = 'applied';

  @override
  void initState() {
    super.initState();
    if (widget.existing case final e?) {
      _company.text = e['company'] ?? '';
      _role.text = e['role'] ?? '';
      _jobUrl.text = e['job_url'] ?? '';
      _notes.text = e['notes'] ?? '';
      _status = e['status'] ?? 'applied';
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _role.dispose();
    _jobUrl.dispose();
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
          _field(_jobUrl, 'Job URL (optional)', Icons.link),
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
