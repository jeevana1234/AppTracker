import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class JobAlertsScreen extends StatefulWidget {
  const JobAlertsScreen({super.key});
  @override
  State<JobAlertsScreen> createState() => _JobAlertsScreenState();
}

class _JobAlertsScreenState extends State<JobAlertsScreen> {
  final _db = Supabase.instance.client;
  static const _backendUrl = 'http://localhost:8000';

  List<Map<String, dynamic>> _alerts = [];
  Map<String, dynamic>? _prefs;
  bool _loading = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final uid = _db.auth.currentUser!.id;
      final alerts = await _db
          .from('job_alerts')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      final prefs = await _db
          .from('job_preferences')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      setState(() {
        _alerts = List<Map<String, dynamic>>.from(alerts);
        _prefs = prefs;
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _triggerScan() async {
    final uid = _db.auth.currentUser!.id;
    if (_prefs == null) {
      _showPrefsDialog();
      return;
    }
    setState(() => _scanning = true);
    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/monitor/scan/$uid'),
        headers: {'Content-Type': 'application/json'},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final count = body['new'] ?? 0;
        _snack('Found $count new job${count != 1 ? 's' : ''}!');
        _loadAll();
      } else {
        _snack('Scan failed: ${res.statusCode}', error: true);
      }
    } catch (_) {
      _snack('Cannot reach backend. Is it running?', error: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _autoApply(Map<String, dynamic> alert) async {
    final uid = _db.auth.currentUser!.id;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Auto-Apply?'),
        content: Text(
            'AppTrack will automatically apply to \n"${alert['title']}" at ${alert['company']}.\n\nThis uses LinkedIn Easy Apply.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply Now')),
        ],
      ),
    );
    if (confirm != true) return;

    _snack('Applying... this may take 30 seconds');
    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/monitor/auto-apply'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': uid, 'job_alert_id': alert['id']}),
      ).timeout(const Duration(seconds: 60));
      final body = jsonDecode(res.body);
      if (body['success'] == true) {
        _snack('✅ ${body['message']}');
        _loadAll();
      } else {
        _snack(body['message'] ?? 'Auto-apply failed', error: true);
      }
    } catch (_) {
      _snack('Auto-apply timed out or backend unreachable', error: true);
    }
  }

  Future<void> _dismiss(String alertId) async {
    try {
      await http.patch(Uri.parse('$_backendUrl/monitor/alerts/$alertId/dismiss'));
      _loadAll();
    } catch (_) {}
  }

  void _showPrefsDialog() {
    final rolesCtrl = TextEditingController(
        text: (_prefs?['roles'] as List?)?.join(', ') ?? '');
    final locCtrl = TextEditingController(
        text: (_prefs?['locations'] as List?)?.join(', ') ?? 'Remote');
    bool autoApply = _prefs?['auto_apply'] ?? false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Job Search Preferences'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('AppTrack will search LinkedIn every hour for matching jobs.',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: rolesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Job Roles (comma separated)',
                  hintText: 'e.g. Flutter Developer, Software Engineer',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work_outline),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locCtrl,
                decoration: const InputDecoration(
                  labelText: 'Locations (comma separated)',
                  hintText: 'e.g. Remote, Bangalore, Hyderabad',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Auto-Apply (LinkedIn Easy Apply)'),
                subtitle: const Text('Automatically submit applications', style: TextStyle(fontSize: 12)),
                value: autoApply,
                onChanged: (v) => setSt(() => autoApply = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final uid = _db.auth.currentUser!.id;
                final roles = rolesCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                final locs = locCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                await http.post(
                  Uri.parse('$_backendUrl/monitor/preferences'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'user_id': uid,
                    'roles': roles,
                    'locations': locs,
                    'auto_apply': autoApply,
                    'is_active': true,
                  }),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _loadAll();
              },
              child: const Text('Save & Activate'),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red[700] : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Alerts'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Preferences',
            onPressed: _showPrefsDialog,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Status banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: _prefs != null && _prefs!['is_active'] == true
                      ? Colors.green[50]
                      : Colors.orange[50],
                  child: Row(children: [
                    Icon(
                      _prefs != null && _prefs!['is_active'] == true
                          ? Icons.sensors
                          : Icons.sensors_off,
                      color: _prefs != null && _prefs!['is_active'] == true
                          ? Colors.green[700]
                          : Colors.orange[700],
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _prefs != null
                            ? 'Monitoring: ${(_prefs!['roles'] as List?)?.join(', ') ?? 'No roles set'}'
                            : 'Not set up — tap Settings to add your job preferences',
                        style: TextStyle(
                          fontSize: 13,
                          color: _prefs != null ? Colors.green[800] : Colors.orange[800],
                        ),
                      ),
                    ),
                  ]),
                ),

                // Alert list
                Expanded(
                  child: _alerts.isEmpty
                      ? _emptyState()
                      : RefreshIndicator(
                          onRefresh: _loadAll,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _alerts.length,
                            itemBuilder: (_, i) => _alertCard(_alerts[i]),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _triggerScan,
        icon: _scanning
            ? const SizedBox(height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.search),
        label: Text(_scanning ? 'Scanning...' : 'Scan Now'),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.notifications_none, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No job alerts yet',
              style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          const SizedBox(height: 8),
          Text('Set your preferences and tap Scan Now',
              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _showPrefsDialog,
            icon: const Icon(Icons.tune),
            label: const Text('Set Preferences'),
          ),
        ]),
      );

  Widget _alertCard(Map<String, dynamic> alert) {
    final isNew = alert['status'] == 'new';
    final isApplied = alert['status'] == 'applied';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(alert['title'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            if (isApplied)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Applied', style: TextStyle(color: Colors.green[800], fontSize: 11)),
              )
            else if (isNew)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('New', style: TextStyle(color: Colors.blue[800], fontSize: 11)),
              ),
          ]),
          const SizedBox(height: 4),
          Text('${alert['company'] ?? ''} · ${alert['location'] ?? ''}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text('via ${alert['source'] ?? 'LinkedIn'}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            if (alert['job_url'] != null && (alert['job_url'] as String).isNotEmpty)
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(alert['job_url'])),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('View Job'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (!isApplied) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _autoApply(alert),
                icon: const Icon(Icons.send, size: 14),
                label: const Text('Auto-Apply'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
            const Spacer(),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: Colors.grey[400]),
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: () => _dismiss(alert['id']),
            ),
          ]),
        ]),
      ),
    );
  }
}
