from google import genai
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from reportlab.lib.units import inch
from reportlab.lib import colors
import io
from app.config import GEMINI_API_KEY, SUPABASE_URL, SUPABASE_KEY

async def generate_resume_pdf(profile: dict, job_description: str = "") -> str:
    # Step 1: Use Gemini to write a tailored summary and bullet points
    client = genai.Client(api_key=GEMINI_API_KEY)

    prompt = f"""
    You are a professional resume writer.
    Based on the following profile, write a clean, ATS-friendly resume summary and improve bullet points for experience.
    {"Tailor this specifically for the following job: " + job_description if job_description else ""}

    Profile:
    Name: {profile.get('full_name')}
    Skills: {", ".join(profile.get('skills', []))}
    Experience: {profile.get('experience', '')}
    Education: {profile.get('education', '')}
    Achievements: {profile.get('achievements', '')}
    Certifications: {", ".join(profile.get('certifications', []))}

    Return JSON with keys: "summary", "experience_bullets" (list of strings),
    "skills_section" (string), "achievements_bullets" (list of strings).
    """

    response = client.models.generate_content(
        model="gemini-2.0-flash",
        contents=prompt
    )
    import json, re
    raw = response.text
    # Extract JSON from response
    match = re.search(r'\{.*\}', raw, re.DOTALL)
    ai_content = json.loads(match.group()) if match else {}

    # Step 2: Build PDF using ReportLab
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4,
                            rightMargin=0.75*inch, leftMargin=0.75*inch,
                            topMargin=0.75*inch, bottomMargin=0.75*inch)

    styles = getSampleStyleSheet()
    name_style = ParagraphStyle('Name', fontSize=20, fontName='Helvetica-Bold', spaceAfter=4)
    heading_style = ParagraphStyle('Heading', fontSize=12, fontName='Helvetica-Bold',
                                   textColor=colors.HexColor('#2563EB'), spaceAfter=4, spaceBefore=12)
    body_style = styles['Normal']

    story = []

    # Header
    story.append(Paragraph(profile.get('full_name', ''), name_style))
    contact_parts = [x for x in [
        profile.get('email',''), profile.get('phone',''),
        profile.get('linkedin_url',''), profile.get('github_url',''),
        profile.get('portfolio_url',''),
    ] if x]
    story.append(Paragraph('  |  '.join(contact_parts), body_style))
    story.append(Spacer(1, 0.1*inch))

    # Summary
    story.append(Paragraph("SUMMARY", heading_style))
    story.append(Paragraph(ai_content.get('summary', profile.get('summary', '')), body_style))

    # Skills
    story.append(Paragraph("SKILLS", heading_style))
    story.append(Paragraph(ai_content.get('skills_section', ', '.join(profile.get('skills', []))), body_style))

    # Experience
    story.append(Paragraph("EXPERIENCE", heading_style))
    for bullet in ai_content.get('experience_bullets', []):
        story.append(Paragraph(f"• {bullet}", body_style))

    # Achievements
    achievements = ai_content.get('achievements_bullets', [])
    if not achievements and profile.get('achievements'):
        achievements = [line.strip() for line in profile['achievements'].split('\n') if line.strip()]
    if achievements:
        story.append(Paragraph("ACHIEVEMENTS", heading_style))
        for item in achievements:
            story.append(Paragraph(f"• {item}", body_style))

    # Certifications
    certs = profile.get('certifications', [])
    if certs:
        story.append(Paragraph("CERTIFICATIONS", heading_style))
        for cert in certs:
            story.append(Paragraph(f"• {cert}", body_style))

    # Education
    story.append(Paragraph("EDUCATION", heading_style))
    edu_text = profile.get('education', '')
    if isinstance(edu_text, list):
        edu_text = '\n'.join(edu_text)
    for line in edu_text.split('\n'):
        if line.strip():
            story.append(Paragraph(line.strip(), body_style))
    if False:  # keep old loop unreachable to avoid delete
        for edu in profile.get('education', []):
            story.append(Paragraph(
                f"<b>{edu.get('degree','')}</b> — {edu.get('institution','')} ({edu.get('year','')})",
            body_style))

    doc.build(story)
    buffer.seek(0)

    # Step 3: Upload to Supabase Storage
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    file_path = f"resumes/{profile['user_id']}/resume.pdf"
    sb.storage.from_("resumes").upload(file_path, buffer.read(),
                                       {"content-type": "application/pdf", "upsert": "true"})

    public_url = sb.storage.from_("resumes").get_public_url(file_path)

    # Save URL to profile
    sb.table("user_profiles").update({"resume_url": public_url}).eq("user_id", profile["user_id"]).execute()

    return public_url
