from google import genai
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, HRFlowable, Table, TableStyle, KeepTogether
from reportlab.lib.units import inch
from reportlab.lib import colors
import requests
import io, json, re
from app.config import GEMINI_API_KEY, SUPABASE_URL, SUPABASE_KEY, SUPABASE_SERVICE_KEY


# ─── AI Content Enhancer ──────────────────────────────────────────────────────

async def _ai_enhance(profile: dict, job_description: str = "") -> dict:
    try:
        client = genai.Client(api_key=GEMINI_API_KEY)
        prompt = f"""
You are a professional resume writer. Based on the profile below, write a clean ATS-friendly resume.
{"Tailor the content specifically for this job: " + job_description if job_description else ""}

Profile:
Name: {profile.get('full_name', '')}
Skills: {", ".join(profile.get('skills') or [])}
Experience: {profile.get('experience', '')}
Education: {profile.get('education', '')}
Achievements: {profile.get('achievements', '')}
Certifications: {", ".join(profile.get('certifications') or [])}
Summary: {profile.get('summary', '')}

Return ONLY valid JSON (no markdown, no code blocks) with these keys:
- "summary": 2-3 sentence professional summary
- "experience_bullets": list of up to 6 strong bullet point strings
- "skills_section": comma-separated skills string
- "achievements_bullets": list of achievement strings (empty list if none)
"""
        response = client.models.generate_content(model="gemini-2.0-flash", contents=prompt)
        raw = response.text
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        return json.loads(match.group()) if match else {}
    except Exception:
        # Quota exhausted or API error — fall back to raw profile data silently
        return {}


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _edu_lines(profile: dict):
    edu = profile.get('education', '')
    if isinstance(edu, list):
        return [str(e) for e in edu if str(e).strip()]
    return [line.strip() for line in (edu or '').split('\n') if line.strip()]


def _parse_blocks(text: str) -> list:
    """Parse multiline text into [(header, [bullets])] blocks.
    Consecutive non-bullet lines (no blank line between) form one multi-line header."""
    blocks, header, bullets = [], None, []
    for raw in (text or '').split('\n'):
        line = raw.strip()
        if not line:
            if header is not None:
                blocks.append((header, bullets))
                header, bullets = None, []
            continue
        if line[:1] in ('•', '-', '*', '–', '▸', '›', '+'):
            bullets.append(line.lstrip('•-*–▸›+ '))
        else:
            if header is not None and not bullets:
                # Consecutive non-bullet lines → part of same header (e.g. title + company)
                header = header + '\n' + line
            else:
                if header is not None:
                    blocks.append((header, bullets))
                header, bullets = line, []
    if header is not None:
        blocks.append((header, bullets))
    return blocks or []


def _extract_date(text: str):
    """Return (title_without_date, date_string) from a header line."""
    for pat in [
        r'\(?\b(\d{4}\s*[-–]\s*(?:\d{4}|Present|Current|Now|Ongoing))\)?',
        r'\(?\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\.?\s+\d{4}'
        r'\s*[-–]\s*(?:\w+\.?\s+\d{4}|Present|Current))\)?',
        r'\(?\b(\d{4})\)?$',
    ]:
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            date  = m.group(1).strip()
            title = (text[:m.start()] + text[m.end():]).strip(' |·-–()')
            return title, date
    return text, ''


# ─── Shared template builder ──────────────────────────────────────────────────

def _build_template(profile: dict, ai: dict, *,
                    accent,
                    name_size: int,
                    center_name: bool,
                    thick_bar: bool,
                    div_color,
                    div_thickness: float,
                    sec_transform=None,
                    margin_in: float = 0.75) -> bytes:

    buf = io.BytesIO()
    mg  = margin_in * inch
    doc = SimpleDocTemplate(buf, pagesize=A4,
                            rightMargin=mg, leftMargin=mg,
                            topMargin=mg, bottomMargin=mg)
    PAGE_W = A4[0] - 2 * mg
    DATE_W = 80.0
    BODY_W = PAGE_W - DATE_W

    DARK  = colors.HexColor('#1A1A1A')
    MID   = colors.HexColor('#555555')
    LIGHT = colors.HexColor('#F5F5F5')
    LGRID = colors.HexColor('#E0E0E0')

    align = 1 if center_name else 0

    name_s    = ParagraphStyle('NS',  fontSize=name_size, fontName='Helvetica-Bold',
                               spaceAfter=5, alignment=align, textColor=accent)
    sub_s     = ParagraphStyle('SS',  fontSize=10.5, fontName='Helvetica',
                               spaceBefore=2, spaceAfter=5, alignment=align, textColor=MID)
    contact_s = ParagraphStyle('CS',  fontSize=8.5, fontName='Helvetica',
                               spaceBefore=4, spaceAfter=8, alignment=align, textColor=MID)
    sec_s     = ParagraphStyle('SH',  fontSize=10, fontName='Helvetica-Bold',
                               spaceBefore=10, spaceAfter=3, textColor=accent)
    body_s    = ParagraphStyle('BS',  fontSize=9.5, fontName='Helvetica',
                               spaceAfter=2, leading=14, textColor=DARK)
    bold_s    = ParagraphStyle('BBS', fontSize=9.5, fontName='Helvetica-Bold',
                               spaceAfter=1, leading=14, textColor=DARK)
    date_s    = ParagraphStyle('DS',  fontSize=8.5, fontName='Helvetica-Oblique',
                               leading=14, textColor=accent, alignment=2)
    skill_s   = ParagraphStyle('SKS', fontSize=9, fontName='Helvetica',
                               leading=13, textColor=DARK)
    link_s    = ParagraphStyle('LKS', fontSize=9, fontName='Helvetica',
                               leading=14, textColor=colors.HexColor('#2563EB'))
    cert_s    = ParagraphStyle('CRS', fontSize=9.5, fontName='Helvetica',
                               spaceAfter=3, leading=14, textColor=DARK)
    acc_bul_s   = ParagraphStyle('ABS', fontSize=11, fontName='Helvetica-Bold',
                                 leading=14, textColor=accent)
    company_s   = ParagraphStyle('COS', fontSize=9.0, fontName='Helvetica-Oblique',
                                 spaceAfter=2, leading=13, textColor=accent)
    cert_name_s = ParagraphStyle('CNS', fontSize=9.5, fontName='Helvetica-Bold',
                                 leading=13, textColor=DARK)
    cert_iss_s  = ParagraphStyle('CIS', fontSize=8.5, fontName='Helvetica',
                                 leading=13, textColor=accent, alignment=2)

    story = []

    # ── Header ──────────────────────────────────────────────────────────────
    story.append(Paragraph(profile.get('full_name', 'Your Name'), name_s))

    subtitle = (profile.get('current_title') or profile.get('title')
                or profile.get('job_title') or '').strip()
    if subtitle:
        story.append(Paragraph(subtitle, sub_s))

    contact_parts = [x for x in [
        profile.get('email', ''),
        profile.get('phone', ''),
        profile.get('linkedin_url', ''),
        profile.get('github_url', ''),
    ] if x]
    if contact_parts:
        story.append(Paragraph('   |   '.join(contact_parts), contact_s))

    if thick_bar:
        story.append(HRFlowable(width='100%', thickness=2.5, color=accent, spaceAfter=6))
    else:
        story.append(HRFlowable(width='100%', thickness=max(div_thickness, 0.8),
                                color=div_color, spaceAfter=6))
    story.append(Spacer(1, 2))

    # ── Inner helpers ────────────────────────────────────────────────────────
    def _label(t): return sec_transform(t) if sec_transform else t.upper()

    def _sec(title):
        story.append(Paragraph(_label(title), sec_s))
        story.append(HRFlowable(width='100%', thickness=div_thickness,
                                color=div_color, spaceAfter=4))

    def _entry(header_text, bullets):
        lines = [l.strip() for l in header_text.split('\n') if l.strip()]
        if not lines:
            return
        # Separate date from title/company — scan each line, extract first date found
        date_str, cleaned = '', []
        for line in lines:
            t_part, d = _extract_date(line)
            if d and not date_str:
                date_str = d
                if t_part.strip():
                    cleaned.append(t_part.strip())
                # else: the line was only a date — drop it
            else:
                cleaned.append(line)
        title_line   = cleaned[0] if cleaned else ''
        company_line = ', '.join(cleaned[1:]) if len(cleaned) > 1 else ''
        # Title (left) | Date (right-aligned)
        t = Table([[Paragraph(title_line, bold_s), Paragraph(date_str, date_s)]],
                  colWidths=[PAGE_W - DATE_W, DATE_W])
        t.setStyle(TableStyle([
            ('VALIGN',        (0, 0), (-1, -1), 'TOP'),
            ('ALIGN',         (1, 0), (1, -1), 'RIGHT'),
            ('TOPPADDING',    (0, 0), (-1, -1), 0),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
            ('LEFTPADDING',   (0, 0), (-1, -1), 0),
            ('RIGHTPADDING',  (0, 0), (-1, -1), 0),
        ]))
        elems = [t]
        if company_line:
            elems.append(Paragraph(company_line, company_s))
        for b in bullets:
            elems.append(Paragraph(f'  ▸  {b}', body_s))
        elems.append(Spacer(1, 6))
        try:
            story.append(KeepTogether(elems))
        except Exception:
            story.extend(elems)

    def _skills_grid(skills_list):
        COLS = 3
        padded = list(skills_list)
        while len(padded) % COLS:
            padded.append('')
        rows = [[
            Paragraph(f'◆  {padded[i+j]}' if padded[i+j] else '', skill_s)
            for j in range(COLS)
        ] for i in range(0, len(padded), COLS)]
        col_w = PAGE_W / COLS
        t = Table(rows, colWidths=[col_w] * COLS)
        t.setStyle(TableStyle([
            ('BACKGROUND',    (0, 0), (-1, -1), LIGHT),
            ('GRID',          (0, 0), (-1, -1), 0.3, LGRID),
            ('TOPPADDING',    (0, 0), (-1, -1), 4),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
            ('LEFTPADDING',   (0, 0), (-1, -1), 8),
            ('RIGHTPADDING',  (0, 0), (-1, -1), 4),
            ('VALIGN',        (0, 0), (-1, -1), 'MIDDLE'),
        ]))
        story.append(t)
        story.append(Spacer(1, 4))

    def _cbullet(text):
        t = Table([[Paragraph('●', acc_bul_s), Paragraph(text, cert_s)]],
                  colWidths=[14, PAGE_W - 14])
        t.setStyle(TableStyle([
            ('VALIGN',        (0, 0), (-1, -1), 'TOP'),
            ('TOPPADDING',    (0, 0), (-1, -1), 1),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
            ('LEFTPADDING',   (0, 0), (-1, -1), 0),
            ('RIGHTPADDING',  (0, 0), (-1, -1), 2),
        ]))
        story.append(t)

    def _cert_entry(text):
        """Certification row: highlighted background, cert name left (bold bullet), issuer right (accent)."""
        parts = re.split(r'\s+[-–|]\s+|\s+from\s+|\s+by\s+', str(text), maxsplit=1, flags=re.IGNORECASE)
        cert_name = parts[0].strip()
        issuer    = parts[1].strip() if len(parts) > 1 else ''
        CERT_W    = PAGE_W * 0.65
        ISSU_W    = PAGE_W - CERT_W
        t = Table([[Paragraph(f'●  {cert_name}', cert_name_s), Paragraph(issuer, cert_iss_s)]],
                  colWidths=[CERT_W, ISSU_W])
        t.setStyle(TableStyle([
            ('BACKGROUND',    (0, 0), (-1, -1), LIGHT),
            ('GRID',          (0, 0), (-1, -1), 0.3, LGRID),
            ('VALIGN',        (0, 0), (-1, -1), 'MIDDLE'),
            ('ALIGN',         (1, 0), (1, -1), 'RIGHT'),
            ('TOPPADDING',    (0, 0), (-1, -1), 5),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
            ('LEFTPADDING',   (0, 0), (-1, -1), 8),
            ('RIGHTPADDING',  (0, 0), (-1, -1), 6),
        ]))
        story.append(t)
        story.append(Spacer(1, 2))

    # ── Summary ──────────────────────────────────────────────────────────────
    summary = ai.get('summary') or profile.get('summary', '')
    if summary:
        _sec('Summary')
        story.append(Paragraph(summary, body_s))

    # ── Skills ───────────────────────────────────────────────────────────────
    skills_raw  = ai.get('skills_section') or ', '.join(profile.get('skills') or [])
    skills_list = [s.strip() for s in skills_raw.replace(';', ',').split(',') if s.strip()]
    if skills_list:
        _sec('Skills')
        _skills_grid(skills_list)

    # ── Experience ───────────────────────────────────────────────────────────
    exp_bullets = ai.get('experience_bullets', [])
    exp_text    = profile.get('experience', '') or ''
    if exp_bullets or exp_text.strip():
        _sec('Experience')
        if exp_bullets:
            for b in exp_bullets:
                story.append(Paragraph(f'▸  {b}', body_s))
        else:
            for header, buls in _parse_blocks(exp_text):
                if header:
                    _entry(header, buls)
                elif buls:
                    for b in buls:
                        story.append(Paragraph(f'▸  {b}', body_s))

    # ── Projects ─────────────────────────────────────────────────────────────
    proj_text = profile.get('projects', '') or ''
    if proj_text.strip():
        _sec('Projects')
        for header, buls in _parse_blocks(proj_text):
            if header:
                _entry(header, buls)
            elif buls:
                for b in buls:
                    story.append(Paragraph(f'▸  {b}', body_s))

    # ── Education ────────────────────────────────────────────────────────────
    edu_lines = _edu_lines(profile)
    if edu_lines:
        _sec('Education')
        for header, buls in _parse_blocks('\n'.join(edu_lines)):
            if header:
                _entry(header, buls)

    # ── Certifications ───────────────────────────────────────────────────────
    certs = profile.get('certifications') or []
    if certs:
        _sec('Certifications')
        for c in certs:
            _cert_entry(str(c))

    # ── Achievements ─────────────────────────────────────────────────────────
    ach_bullets = ai.get('achievements_bullets', [])
    ach_text    = profile.get('achievements', '') or ''
    if not ach_bullets and ach_text:
        ach_bullets = [l.lstrip('•-* ').strip() for l in ach_text.split('\n') if l.strip()]
    if ach_bullets:
        _sec('Achievements')
        for a in ach_bullets:
            _cbullet(a)

    # ── Custom extra sections ─────────────────────────────────────────────────
    extra_secs = profile.get('extra_sections') or []
    if isinstance(extra_secs, str):
        try:
            extra_secs = json.loads(extra_secs)
        except Exception:
            extra_secs = []
    for sec in (extra_secs or []):
        sec_title = (sec.get('title') or '').strip()
        sec_body  = (sec.get('body')  or '').strip()
        if sec_title and sec_body:
            _sec(sec_title)
            for header, buls in _parse_blocks(sec_body):
                if header:
                    _entry(header, buls)
                elif buls:
                    for b in buls:
                        story.append(Paragraph(f'  \u25b8  {b}', body_s))

    # ── Social Links ─────────────────────────────────────────────────────────
    social_extras = [x for x in [
        profile.get('portfolio_url', ''),
        profile.get('github_url', ''),
        profile.get('linkedin_url', ''),
    ] if x and x not in contact_parts]
    if social_extras:
        _sec('Social Links')
        story.append(Paragraph('   |   '.join(social_extras), link_s))

    doc.build(story)
    buf.seek(0)
    return buf.read()


# ─── 4 Template wrappers ─────────────────────────────────────────────────────

def _build_classic(profile, ai):
    return _build_template(profile, ai,
        accent=colors.HexColor('#1A1A1A'), name_size=20,
        center_name=True, thick_bar=False,
        div_color=colors.black, div_thickness=1.2)

def _build_modern(profile, ai):
    return _build_template(profile, ai,
        accent=colors.HexColor('#2563EB'), name_size=22,
        center_name=False, thick_bar=True,
        div_color=colors.HexColor('#CCCCCC'), div_thickness=0.5)

def _build_minimalist(profile, ai):
    return _build_template(profile, ai,
        accent=colors.HexColor('#555555'), name_size=20,
        center_name=True, thick_bar=False,
        div_color=colors.HexColor('#AAAAAA'), div_thickness=0.4,
        sec_transform=str.upper, margin_in=0.9)

def _build_executive(profile, ai):
    return _build_template(profile, ai,
        accent=colors.HexColor('#1E3A5F'), name_size=24,
        center_name=False, thick_bar=True,
        div_color=colors.HexColor('#1E3A5F'), div_thickness=1.0)


# ─── Template registry ────────────────────────────────────────────────────────

_BUILDERS = {
    'classic':    _build_classic,
    'modern':     _build_modern,
    'minimalist': _build_minimalist,
    'executive':  _build_executive,
}


# ─── Main generate function ───────────────────────────────────────────────────

async def generate_resume_pdf(profile: dict, job_description: str = "",
                               template: str = "modern") -> str:
    ai = await _ai_enhance(profile, job_description)
    builder = _BUILDERS.get(template, _build_modern)
    pdf_bytes = builder(profile, ai)

    # Upload via Supabase Storage REST API directly (avoids supabase-py JWT issues)
    bucket = "resumes"
    object_path = f"{profile['user_id']}/resume_{template}.pdf"
    storage_url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{object_path}"
    headers = {
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/pdf",
        "x-upsert": "true",
    }

    # Ensure bucket exists
    bucket_url = f"{SUPABASE_URL}/storage/v1/bucket"
    requests.post(bucket_url, json={"id": bucket, "name": bucket, "public": True},
                  headers={"Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
                           "Content-Type": "application/json"})

    resp = requests.post(storage_url, headers=headers, data=pdf_bytes)
    if resp.status_code not in (200, 201):
        raise Exception(f"Storage upload failed: {resp.status_code} {resp.text}")

    public_url = f"{SUPABASE_URL}/storage/v1/object/public/{bucket}/{object_path}"

    # Save URL back to profile using supabase-py (anon key is fine for table updates)
    from supabase import create_client
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    sb.table("user_profiles").update({"resume_url": public_url}) \
        .eq("user_id", profile["user_id"]).execute()
    return public_url


# ─── Heuristic resume parser (no AI required) ──────────────────────────────────

def _basic_extract(text: str) -> dict:
    """Parse plain resume text with regex heuristics — AI-free fallback."""
    email_m    = re.search(r'[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}', text)
    phone_m    = re.search(r'(?:\+?\d[\s.\-]?)?\(?\d{3,4}\)?[\s.\-]?\d{3,4}[\s.\-]?\d{3,4}', text)
    linkedin_m = re.search(r'linkedin\.com/in/[\w\-]+', text, re.IGNORECASE)
    github_m   = re.search(r'github\.com/[\w\-]+', text, re.IGNORECASE)

    lines = [l.strip() for l in text.split('\n') if l.strip()]
    full_name = lines[0] if lines else ''

    sec_re = re.compile(
        r'^\s*(experience|work experience|employment|education|academic|skills|'
        r'certifications?|achievements?|awards?|projects?|summary|objective|profile)\s*$',
        re.IGNORECASE,
    )
    sections: dict = {}
    cur_name, cur_lines = 'header', []
    for line in text.split('\n'):
        m = sec_re.match(line)
        if m:
            sections[cur_name] = '\n'.join(cur_lines).strip()
            cur_name = m.group(1).strip().lower()
            cur_lines = []
        else:
            cur_lines.append(line)
    sections[cur_name] = '\n'.join(cur_lines).strip()

    def _pick(*keys):
        for k in keys:
            for sk in sections:
                if k in sk:
                    v = sections[sk].strip()
                    if v:
                        return v
        return ''

    skills_raw = _pick('skill')
    skills = [s.strip() for s in re.split(r'[,\n\u2022\-|·]', skills_raw)
              if s.strip() and len(s.strip()) < 50]
    certs = [c.strip() for c in _pick('certif').split('\n') if c.strip()]

    return {
        'full_name':     full_name,
        'email':         email_m.group() if email_m else '',
        'phone':         phone_m.group().strip() if phone_m else '',
        'linkedin_url':  ('https://' + linkedin_m.group()) if linkedin_m else '',
        'github_url':    ('https://' + github_m.group()) if github_m else '',
        'summary':       _pick('summary', 'objective', 'profile'),
        'skills':        skills,
        'experience':    _pick('experience', 'work', 'employment'),
        'education':     _pick('education', 'academic'),
        'achievements':  _pick('achievement', 'award'),
        'certifications': certs,
        'projects':      _pick('project'),
    }


# ─── Parse uploaded resume PDF ────────────────────────────────────────────────

async def parse_uploaded_resume(pdf_bytes: bytes) -> dict:
    """Extract text from uploaded PDF and use Gemini to return structured fields."""
    import pdfplumber

    text = ""
    with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
        for page in pdf.pages:
            text += (page.extract_text() or "") + "\n"

    try:
        client = genai.Client(api_key=GEMINI_API_KEY)
        prompt = f"""
Extract resume information from the text below.
Return ONLY valid JSON (no markdown) with these exact keys:
full_name, email, phone, linkedin_url, github_url,
summary, skills (list), experience (string), education (string),
achievements (string), certifications (list)

Resume text:
{text[:5000]}
"""
        response = client.models.generate_content(model="gemini-2.0-flash", contents=prompt)
        raw = response.text
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        try:
            return json.loads(match.group()) if match else {}
        except Exception:
            return {}
    except Exception:
        # Gemini quota exceeded or unavailable — use heuristic fallback
        return _basic_extract(text)

