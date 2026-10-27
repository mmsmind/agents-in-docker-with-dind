# Repository language

Write all project content in English, including documentation, comments, commit messages, release notes, discussions and user-facing strings. Respond in English unless the user explicitly requests another language.

## Reading documents

- Use `doc-to-text <file> [outdir]` for PDF (including OCR), DOCX, XLSX, PPTX and HTML text.
- Use `doc-extract-images <file> [outdir]` for embedded images, including EMF/WMF conversion to PNG.
- Use `pdf-to-png <file> [first] [last] [dpi] --outdir <directory>` to inspect PDF pages (default 110 dpi).
- Output defaults to `/tmp/doc-out/<basename>`; source files are never modified.
- Extracted images are limited to 1600 pixels per side. Render PDF pages separately for small details.
- Run a helper with `--help` for usage. Python document libraries are available through `python3`.
