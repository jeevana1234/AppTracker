import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

// ─── Template meta ────────────────────────────────────────────────────────────

class _TemplateInfo {
  final String id;
  final String name;
  final Color color;
  final Color nameColor;
  final bool centerName;
  final bool thickBar;
  final Color dividerColor;
  final double dividerThickness;
  final Color sectionColor;

  const _TemplateInfo({
    required this.id,
    required this.name,
    required this.color,
    required this.nameColor,
    this.centerName = false,
    this.thickBar = false,
    required this.dividerColor,
    this.dividerThickness = 0.5,
    required this.sectionColor,
  });
}

const _kTemplates = <_TemplateInfo>[
  _TemplateInfo(
    id: 'classic', name: 'Classic',
    color: Color(0xFF374151), nameColor: Colors.black,
    centerName: true,
    dividerColor: Colors.black, dividerThickness: 1.2,
    sectionColor: Colors.black,
  ),
  _TemplateInfo(
    id: 'modern', name: 'Modern',
    color: Color(0xFF2563EB), nameColor: Color(0xFF2563EB),
    thickBar: true,
    dividerColor: Color(0xFFCCCCCC),
    sectionColor: Color(0xFF2563EB),
  ),
  _TemplateInfo(
    id: 'minimalist', name: 'Minimalist',
    color: Color(0xFF6B7280), nameColor: Colors.black87,
    centerName: true,
    dividerColor: Color(0xFF777777), dividerThickness: 0.4,
    sectionColor: Color(0xFF777777),
  ),
  _TemplateInfo(
    id: 'executive', name: 'Executive',
    color: Color(0xFF1E3A5F), nameColor: Color(0xFF1E3A5F),
    thickBar: true,
    dividerColor: Color(0xFF1E3A5F), dividerThickness: 1.0,
    sectionColor: Color(0xFF1E3A5F),
  ),
];

// ─── Sample preview data ──────────────────────────────────────────────────────

const _kName = 'Sarah Johnson';
const _kTitle = 'Senior Software Engineer';
const _kContact = 'sarah@email.com  ·  +1 (555) 234-5678  ·  linkedin.com/in/sarah';
const _kSummary =
    'Results-driven software engineer with 5+ years of experience building scalable web applications. '
    'Adept at leading teams, architecting solutions and delivering high-quality products on time.';
const _kExp = [
  'Software Engineer  ·  Acme Corp  ·  2022–Present',
  '• Led development of microservices serving 2M+ users daily',
  '• Reduced API latency by 40% through Redis caching optimizations',
  '• Mentored 3 junior developers and led bi-weekly code reviews',
];
const _kSkills =
    'Python, Dart, Flutter, FastAPI, PostgreSQL, Docker, AWS, Git, REST APIs';
const _kEdu = 'B.Tech Computer Science  ·  IIT Hyderabad  ·  2021';
const _kCerts = [
  'AWS Certified Developer – Associate',
  'Google Cloud Professional Data Engineer',
];
const _kAchievements = [
  'Best Employee Award 2023 – Acme Corp',
  'Hackathon Winner – TechFest 2022',
];
const _kSocial = 'github.com/sarah  ·  portfolio.sarah.dev';

// ─── Screen ───────────────────────────────────────────────────────────────────

class ResumeScreen extends StatefulWidget {
  const ResumeScreen({super.key});
  @override
  State<ResumeScreen> createState() => _ResumeScreenState();
}

class _ResumeScreenState extends State<ResumeScreen> {
  final _db = Supabase.instance.client;
  static const _backendUrl = 'http://localhost:8000';

  bool _loading = true;
  bool _generating = false;
  Map<String, dynamic>? _profile;
  String? _previousResumeUrl;  // loaded from profile on init
  String? _newResumeUrl;        // set after a fresh generation
  final Map<String, String> _allUrls = {};  // template id → url for all generated this session
  String? _lastGenerated;  // template id of the most recently generated

  bool _useUpload = false;
  PlatformFile? _pickedFile;
  String? _parsedFileName;
  String _selectedTemplate = 'modern';

  final List<String> _extraSections = [];
  final _extraCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _extraCtrl.dispose();
    super.dispose();
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
        _previousResumeUrl = data?['resume_url'] as String?;
      });
      // Pre-populate deterministic URLs for all 4 templates from Supabase Storage
      const base = 'https://xvzsuwxughgqwhtyacuo.supabase.co';
      for (final t in _kTemplates) {
        _allUrls[t.id] = '$base/storage/v1/object/public/resumes/$uid/resume_${t.id}.pdf';
      }
      // Check which files actually exist
      await _checkExistingTemplates();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _checkExistingTemplates() async {
    final checked = <String>{};
    for (final entry in _allUrls.entries) {
      try {
        final resp = await http.head(Uri.parse(entry.value));
        if (resp.statusCode == 200) checked.add(entry.key);
      } catch (_) {}
    }
    if (mounted) setState(() {
      for (final id in checked) _lastGenerated ??= id; // mark first found
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _pickedFile = result.files.first;
        _parsedFileName = _pickedFile!.name;
      });
    }
  }

  Future<void> _generate() async {
    if (_useUpload && _pickedFile == null) {
      _snack('Please pick a PDF file first', error: true);
      return;
    }
    if (!_useUpload && _profile == null) {
      _snack('Please complete your Profile first', error: true);
      return;
    }
    setState(() => _generating = true);
    try {
      final uid = _db.auth.currentUser!.id;
      String? url;
      if (_useUpload) {
        final req = http.MultipartRequest(
            'POST', Uri.parse('$_backendUrl/resume/generate-from-upload'))
          ..fields['user_id'] = uid
          ..fields['template'] = _selectedTemplate
          ..files.add(http.MultipartFile.fromBytes(
            'file', _pickedFile!.bytes!,
            filename: _pickedFile!.name,
            contentType: MediaType('application', 'pdf'),
          ));
        final streamed = await req.send();
        final respBody = await streamed.stream.bytesToString();
        if (streamed.statusCode != 200) {
          _snack('Backend error ${streamed.statusCode}: $respBody', error: true);
          return;
        }
        final body = jsonDecode(respBody);
        url = body['resume_url'] as String?;
      } else {
        final resp = await http.post(
          Uri.parse('$_backendUrl/resume/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': uid,
            'template': _selectedTemplate,
            'extra_sections': _extraSections,
          }),
        );
        if (resp.statusCode == 200) {
          url = jsonDecode(resp.body)['resume_url'] as String?;
        } else {
          _snack('Backend error ${resp.statusCode}: ${resp.body}', error: true);
          return;
        }
      }
      if (url != null) {
        await _db
            .from('user_profiles')
            .update({'resume_url': url})
            .eq('user_id', uid);
        if (mounted) setState(() {
          _newResumeUrl = url;
          _previousResumeUrl = null;
          _lastGenerated = _selectedTemplate;
          _allUrls[_selectedTemplate] = url!;
        });
        _snack('Resume generated successfully!');
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Failed to fetch') || msg.contains('SocketException') || msg.contains('Connection refused')) {
        _snack('Cannot reach backend. Make sure the server is running on port 8000.', error: true);
      } else {
        _snack('Error: $msg', error: true);
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _openPdf(String url) async {
    final uri = Uri.parse(url);
    if (kIsWeb) {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red[700] : Colors.green[700],
    ));
  }

  void _addExtra() {
    final v = _extraCtrl.text.trim();
    if (v.isEmpty || _extraSections.contains(v)) return;
    setState(() => _extraSections.add(v));
    _extraCtrl.clear();
  }

  _TemplateInfo get _tpl =>
      _kTemplates.firstWhere((t) => t.id == _selectedTemplate);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tpl = _tpl;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Resume Builder'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Step 1: template chips ────────────────────────────
                  Text('Step 1 — Choose Template',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('All templates are ATS-friendly',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[500])),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _kTemplates.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final t = _kTemplates[i];
                        final sel = _selectedTemplate == t.id;
                        return ChoiceChip(
                          label: Text(t.name),
                          selected: sel,
                          selectedColor: t.color,
                          labelStyle: TextStyle(
                            color: sel ? Colors.white : Colors.grey[700],
                            fontWeight:
                                sel ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (_) =>
                              setState(() => _selectedTemplate = t.id),
                        );
                      },
                    ),
                  ),

                  // ── Preview ───────────────────────────────────────────
                  const SizedBox(height: 14),
                  Text('Preview',
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700])),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: _ResumePreview(tpl: tpl),
                        ),
                      ),
                    ),
                  ),

                  // ── Step 2: source ────────────────────────────────────
                  const SizedBox(height: 20),
                  Text('Step 2 — Resume Source',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _srcBtn(
                        theme,
                        selected: !_useUpload,
                        icon: Icons.person_outline,
                        label: 'Use My Profile',
                        onTap: () => setState(() => _useUpload = false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _srcBtn(
                        theme,
                        selected: _useUpload,
                        icon: Icons.upload_file_outlined,
                        label: 'Upload PDF',
                        onTap: () => setState(() => _useUpload = true),
                      ),
                    ),
                  ]),
                  if (_useUpload) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(_parsedFileName ?? 'Choose PDF file...'),
                    ),
                    if (_parsedFileName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          Icon(Icons.check_circle,
                              color: Colors.green[600], size: 15),
                          const SizedBox(width: 5),
                          Text('Selected: $_parsedFileName',
                              style: TextStyle(
                                  color: Colors.green[700], fontSize: 12)),
                        ]),
                      ),
                  ] else if (_profile == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(Icons.warning_amber,
                            color: Colors.orange[700], size: 15),
                        const SizedBox(width: 5),
                        const Text(
                            'Profile not filled — go to Profile tab first',
                            style:
                                TextStyle(fontSize: 12, color: Colors.orange)),
                      ]),
                    ),

                  // ── Step 3: sections ──────────────────────────────────
                  const SizedBox(height: 20),
                  Text('Step 3 — Resume Sections',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Default sections included:',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final s in [
                                'Name & Title',
                                'Contact Info',
                                'Summary',
                                'Skills',
                                'Work Experience',
                                'Projects',
                                'Education',
                                'Certifications',
                                'Achievements',
                                'Social Links',
                              ])
                                Chip(
                                  label: Text(s,
                                      style:
                                          const TextStyle(fontSize: 11)),
                                  backgroundColor: Colors.green[50],
                                  side: BorderSide(
                                      color: Colors.green[200]!),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                ),
                              for (final s in _extraSections)
                                Chip(
                                  label: Text(s,
                                      style:
                                          const TextStyle(fontSize: 11)),
                                  backgroundColor: Colors.blue[50],
                                  side: BorderSide(
                                      color: Colors.blue[200]!),
                                  onDeleted: () => setState(
                                      () => _extraSections.remove(s)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                              '+ Add custom section (e.g. Languages, Projects):',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                          const SizedBox(height: 6),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _extraCtrl,
                                decoration: InputDecoration(
                                  hintText: 'e.g. Languages',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                ),
                                onSubmitted: (_) => _addExtra(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _addExtra,
                              style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10)),
                              child: const Text('Add'),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),

                  // ── Generate button ───────────────────────────────────
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _generating ? null : _generate,
                      style: FilledButton.styleFrom(
                        backgroundColor: tpl.color,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _generating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome,
                              color: Colors.white),
                      label: Text(
                          _generating
                              ? 'Generating...'
                              : 'Generate ${tpl.name} Resume',
                          style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),

                  // ── All generated resumes history ─────────────────────
                  if (_allUrls.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Your Generated Resumes',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 2.8,
                      children: _kTemplates.map((t) {
                        final url = _allUrls[t.id];
                        final isNew = _lastGenerated == t.id;
                        final exists = isNew || (_newResumeUrl != null && _allUrls[t.id] == _newResumeUrl)
                            || (_previousResumeUrl != null && _allUrls[t.id] == _previousResumeUrl);
                        // Show colored if it was generated this session or is the previous saved one
                        final active = _lastGenerated == t.id || (_previousResumeUrl != null && t.id == _kTemplates.firstWhere((x) => _allUrls[x.id] == _previousResumeUrl, orElse: () => t).id);
                        return InkWell(
                          onTap: url != null ? () => _openPdf(url) : null,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isNew
                                  ? t.color.withAlpha(25)
                                  : Colors.grey[100],
                              border: Border.all(
                                color: isNew ? t.color : Colors.grey[300]!,
                                width: isNew ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            child: Row(children: [
                              Icon(
                                isNew
                                    ? Icons.picture_as_pdf
                                    : Icons.picture_as_pdf_outlined,
                                color: isNew ? t.color : Colors.grey[400],
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(t.name,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isNew
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isNew
                                            ? t.color
                                            : Colors.grey[500])),
                              ),
                              if (isNew)
                                Icon(Icons.open_in_new,
                                    size: 13, color: t.color),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_lastGenerated != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Tap any colored card to open that resume PDF',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _srcBtn(ThemeData theme,
      {required bool selected,
      required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : Colors.grey[300]!,
              width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? theme.colorScheme.primary.withAlpha(15)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.grey[500]),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: selected
                        ? theme.colorScheme.primary
                        : Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

// ─── Full Resume Preview ──────────────────────────────────────────────────────

class _ResumePreview extends StatelessWidget {
  final _TemplateInfo tpl;
  const _ResumePreview({required this.tpl});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          if (tpl.centerName)
            Center(
              child: Text(_kName,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: tpl.nameColor,
                      letterSpacing: 0.5)),
            )
          else
            Text(_kName,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: tpl.nameColor)),

          if (tpl.thickBar) ...[
            const SizedBox(height: 3),
            Container(
                height: tpl.id == 'executive' ? 3 : 2.5,
                color: tpl.color),
          ],

          const SizedBox(height: 2),

          // Title
          if (tpl.centerName)
            Center(
              child: Text(_kTitle,
                  style: TextStyle(
                      fontSize: 11,
                      color: tpl.sectionColor,
                      fontWeight: FontWeight.w500)),
            )
          else
            Text(_kTitle,
                style: TextStyle(
                    fontSize: 11,
                    color: tpl.sectionColor,
                    fontWeight: FontWeight.w500)),

          const SizedBox(height: 3),

          // Contact
          if (tpl.centerName)
            Center(
              child: Text(_kContact,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 8.5, color: Color(0xFF555555))),
            )
          else
            Text(_kContact,
                style: const TextStyle(
                    fontSize: 8.5, color: Color(0xFF555555))),

          if (!tpl.thickBar) ...[
            const SizedBox(height: 5),
            Container(
                height: tpl.dividerThickness * 1.5,
                color: tpl.dividerColor),
          ],

          const SizedBox(height: 10),

          _sec('SUMMARY'),
          const Text(_kSummary,
              style: TextStyle(
                  fontSize: 8.5,
                  color: Color(0xFF333333),
                  height: 1.45)),

          const SizedBox(height: 10),
          _sec('WORK EXPERIENCE'),
          ..._kExp.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 1.5),
                child: Text(line,
                    style: TextStyle(
                        fontSize: 8.5,
                        color: const Color(0xFF333333),
                        fontWeight: line.startsWith('•')
                            ? FontWeight.normal
                            : FontWeight.bold,
                        height: 1.4)),
              )),

          const SizedBox(height: 10),
          _sec('SKILLS'),
          const Text(_kSkills,
              style: TextStyle(
                  fontSize: 8.5,
                  color: Color(0xFF333333),
                  height: 1.4)),

          const SizedBox(height: 10),
          _sec('EDUCATION'),
          const Text(_kEdu,
              style: TextStyle(
                  fontSize: 8.5, color: Color(0xFF333333))),

          const SizedBox(height: 10),
          _sec('CERTIFICATIONS'),
          ..._kCerts.map((c) => Text('• $c',
              style: const TextStyle(
                  fontSize: 8.5,
                  color: Color(0xFF333333),
                  height: 1.4))),

          const SizedBox(height: 10),
          _sec('ACHIEVEMENTS'),
          ..._kAchievements.map((a) => Text('• $a',
              style: const TextStyle(
                  fontSize: 8.5,
                  color: Color(0xFF333333),
                  height: 1.4))),

          const SizedBox(height: 10),
          _sec('SOCIAL LINKS'),
          const Text(_kSocial,
              style: TextStyle(
                  fontSize: 8.5, color: Color(0xFF2563EB))),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sec(String title) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: tpl.sectionColor,
                  letterSpacing: 0.5)),
          Container(
              height: tpl.dividerThickness,
              color: tpl.dividerColor,
              margin: const EdgeInsets.only(bottom: 4, top: 1)),
        ],
      );
}
