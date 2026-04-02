import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class ResumeScreen extends StatefulWidget {
  const ResumeScreen({super.key});

  @override
  State<ResumeScreen> createState() => _ResumeScreenState();
}

class _ResumeScreenState extends State<ResumeScreen> {
  final _db = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _generating = false;
  String? _resumeUrl;

  // Backend base URL — change to your deployed URL when live
  static const _backendUrl = 'http://10.0.2.2:8000';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final uid = _db.auth.currentUser!.id;
      final data = await _db
          .from('user_profiles')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      setState(() {
        _profile = data;
        _resumeUrl = data?['resume_url'];
      });
    } catch (_) {
      // profile doesn't exist yet
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateResume() async {
    if (_profile == null) {
      _snack('Please complete your profile first (tap Profile tab)', error: true);
      return;
    }
    setState(() => _generating = true);
    try {
      final uid = _db.auth.currentUser!.id;
      final session = _db.auth.currentSession;
      final response = await http.post(
        Uri.parse('$_backendUrl/resume/generate'),
        headers: {
          'Content-Type': 'application/json',
          if (session != null)
            'Authorization': 'Bearer ${session.accessToken}',
        },
        body: jsonEncode({'user_id': uid}),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final url = body['resume_url'] as String?;
        await _db
            .from('user_profiles')
            .update({'resume_url': url})
            .eq('user_id', uid);
        setState(() => _resumeUrl = url);
        _snack('Resume generated successfully!');
      } else {
        _snack('Generation failed: ${response.statusCode}', error: true);
      }
    } catch (e) {
      _snack(
          'Cannot reach backend. Make sure the server is running.',
          error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _openPdf() async {
    if (_resumeUrl == null) return;
    final uri = Uri.parse(_resumeUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Resume Builder'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header card
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome,
                              color: theme.colorScheme.onPrimaryContainer,
                              size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('AI-Powered Resume',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme
                                                .colorScheme.onPrimaryContainer)),
                                Text(
                                    'Gemini AI builds a tailored PDF resume from your profile',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme
                                            .colorScheme.onPrimaryContainer)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Profile summary
                  Text('Your Profile',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_profile == null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.orange[700]),
                            const SizedBox(width: 12),
                            const Expanded(
                                child: Text(
                                    'Profile incomplete — go to the Profile tab and fill in your details first.')),
                          ],
                        ),
                      ),
                    )
                  else
                    _profileSummaryCard(),
                  const SizedBox(height: 24),

                  // Generate button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _generating ? null : _generateResume,
                      icon: _generating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                          _generating ? 'Generating...' : 'Generate AI Resume',
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Download button (if resume exists)
                  if (_resumeUrl != null) ...[
                    const Divider(height: 32),
                    Text('Your Resume',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Colors.green.withAlpha(30),
                          child: const Icon(Icons.picture_as_pdf,
                              color: Colors.green),
                        ),
                        title: const Text('Resume PDF ready',
                            style:
                                TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Tap to open in browser'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: _openPdf,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _profileSummaryCard() {
    final p = _profile!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(Icons.person, p['full_name'] ?? 'No name'),
            if (p['email'] != null) _row(Icons.email, p['email']),
            if (p['phone'] != null) _row(Icons.phone, p['phone']),
            if (p['linkedin_url'] != null)
              _row(Icons.link, p['linkedin_url']),
            if (p['summary'] != null && (p['summary'] as String).isNotEmpty)
              _row(Icons.notes, p['summary'], maxLines: 2),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text, {int maxLines = 1}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
      );
}
