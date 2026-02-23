# Content Conversion

Use `any2md <input>` to convert files, URLs, arxiv papers, and directories to Markdown.
- arxiv: `any2md 2312.00752` or `any2md https://arxiv.org/abs/2312.00752`
- Files: `any2md file.pdf` (PDF, DOCX, PPTX, Excel, images, etc.)
- Directories: `any2md ./src/` (uses code2prompt)
- Web URLs: `any2md https://docs.anthropic.com` (checks llms.txt first)
- Multiple: `any2md paper1.pdf paper2.pdf`
- Clipboard: `any2md -c`
- Prefer `any2md` over raw `markitdown` for automatic format routing.
