import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UniversitiesScreen extends StatefulWidget {
  const UniversitiesScreen({super.key});

  @override
  State<UniversitiesScreen> createState() => _UniversitiesScreenState();
}

class _UniversitiesScreenState extends State<UniversitiesScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _apps = [];
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
          .from('uni_applications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      setState(() => _apps = List<Map<String, dynamic>>.from(data));
    } catch (_) {
      _snack('Failed to load applications', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDialog([Map<String, dynamic>? existing]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UniDialog(existing: existing),
    );
    if (result == null) return;
    try {
      final uid = _db.auth.currentUser!.id;
      if (existing == null) {
        await _db.from('uni_applications').insert({...result, 'user_id': uid});
      } else {
        await _db
            .from('uni_applications')
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
      await _db.from('uni_applications').delete().eq('id', id);
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
      case 'submitted':
        return Colors.blue;
      case 'interview':
        return Colors.orange;
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('University Applications'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _apps.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _apps.length,
                    itemBuilder: (_, i) => _appCard(_apps[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Application'),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No university applications yet',
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add First Application'),
            ),
          ],
        ),
      );

  Widget _appCard(Map<String, dynamic> app) {
    final color = _statusColor(app['status']);
    return Dismissible(
      key: Key(app['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red[700],
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white),
            Text('Delete',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Application'),
          content: Text('Delete "${app['university']} — ${app['program']}"?'),
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
      onDismissed: (_) => _delete(app['id']),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withAlpha(30),
            child: Text(
              (app['university'] as String? ?? '?').isNotEmpty
                  ? (app['university'] as String)[0].toUpperCase()
                  : '?',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(app['university'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${app['program'] ?? ''} · ${app['degree'] ?? ''}'),
          trailing: _statusChip(app['status'] ?? 'preparing', color),
          onTap: () => _openDialog(app),
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
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      );
}

// ──────────────────────────────────────────────
// Add / Edit dialog
// ──────────────────────────────────────────────
class _UniDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _UniDialog({this.existing});

  @override
  State<_UniDialog> createState() => _UniDialogState();
}

class _UniDialogState extends State<_UniDialog> {
  final _uni = TextEditingController();
  final _program = TextEditingController();
  final _deadline = TextEditingController();
  final _portal = TextEditingController();
  final _notes = TextEditingController();
  String _degree = 'Masters';
  String _status = 'preparing';

  @override
  void initState() {
    super.initState();
    if (widget.existing case final e?) {
      _uni.text = e['university'] ?? '';
      _program.text = e['program'] ?? '';
      _deadline.text = e['deadline'] ?? '';
      _portal.text = e['portal_url'] ?? '';
      _notes.text = e['notes'] ?? '';
      _degree = e['degree'] ?? 'Masters';
      _status = e['status'] ?? 'preparing';
    }
  }

  @override
  void dispose() {
    _uni.dispose();
    _program.dispose();
    _deadline.dispose();
    _portal.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Add University Application'
          : 'Edit Application'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(_uni, 'University *', Icons.school_outlined),
          const SizedBox(height: 12),
          _field(_program, 'Program *', Icons.menu_book_outlined),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _degree,
            decoration: const InputDecoration(
                labelText: 'Degree', border: OutlineInputBorder()),
            items: ['Bachelors', 'Masters', 'PhD']
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => setState(() => _degree = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(
                labelText: 'Status', border: OutlineInputBorder()),
            items: [
              'preparing',
              'submitted',
              'interview',
              'accepted',
              'rejected'
            ]
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _status = v!),
          ),
          const SizedBox(height: 12),
          _field(_deadline, 'Deadline (e.g. 2026-12-01)', Icons.calendar_today),
          const SizedBox(height: 12),
          _field(_portal, 'Portal URL (optional)', Icons.link),
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
            if (_uni.text.trim().isEmpty || _program.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(context, {
              'university': _uni.text.trim(),
              'program': _program.text.trim(),
              'degree': _degree,
              'status': _status,
              if (_deadline.text.trim().isNotEmpty)
                'deadline': _deadline.text.trim(),
              if (_portal.text.trim().isNotEmpty)
                'portal_url': _portal.text.trim(),
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
