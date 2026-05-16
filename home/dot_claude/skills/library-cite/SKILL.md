---
name: library-cite
description: Use when Han wants book-grounded answers within a learning track. Trigger phrases include "what does <book> say about X?", "Wong has X?", "show me Mermin Ch N", "cite a book on X", "any book covers X?", "đoạn nào trong <book> nói về X?", "give me the figure from <book> chapter N", or any case where Han mentions a book by author/title and asks for excerpt, page-pointer, or figure. EPUB books are searched headless via `unzip -p '*.xhtml' | grep` (no pre-conversion needed). PDF books are read native via Read tool's `pages` parameter (figures + text in one view). Images extracted on-demand to `learning/library/_assets/<book-slug>/<chapter>/`. Excerpts quoted 3-5 sentences inline, cited `Author (Year), §X.Y`. GUI fallback: Apple Books (`open <book>.epub`). NOT for downloading books (use annas-fetch). NOT for full-book summary. NOT for non-learning-context questions.
---

# Library Cite (v2)

Book-grounded excerpt + figure retrieval for any `learning/<topic>/` track. EPUB books are searched directly via unzip+grep (no intermediate markdown file). PDF books use Read tool's native `pages` parameter. Images extracted on demand. Citation inline.

## When to use

- Han asks "what does <book> say about X?" or "có chapter nào trong <book> về X không?".
- Han is in a learning track and mentions a book by author/title.
- Han wants a figure or equation rendered from book chapter.
- During `concept-explain` Q&A, Claude wants to surface a book reference.

## When NOT to use

- Han wants to download a book first → use `annas-fetch`.
- Han wants a full chapter summary → answer directly, không qua skill structure.
- Non-learning context → answer directly.

## Hard rules

1. **No conversion to markdown by default.** EPUB search uses raw XHTML via unzip+grep on the fly. Pandoc conversion is fallback only when (a) XHTML has DRM-like obfuscation, (b) grep returns too many hits and need structured search across chapters, or (c) user explicitly asks. Pandoc fallback path: `pandoc -f epub -t markdown --wrap=preserve --extract-media=learning/library/_assets/<slug> <book> -o learning/library/_text/<slug>.md` (gitignored).
2. **Index file must exist before excerpting.** Bootstrap at `learning/library/<book-slug>.md` first (TOC + concept index + EPUB structure note).
3. **Cite every excerpt.** Format: `Author (Year), §X.Y`. For PDFs with page numbers: `Author (Year), p. N, §X.Y`.
4. **Quote 3-5 sentences max per excerpt.** Longer = summarize không quote. Respect copyright + attention.
5. **Use blockquote markdown for excerpts.** `> ...` style. Distinct visually từ skill prose.
6. **Image extraction on-demand, cached.** When excerpt references figure/equation/diagram image, extract that specific file from EPUB to `learning/library/_assets/<book-slug>/<chapter>/<img>.png`. Cache for reuse. First extraction ~100ms; subsequent: instant. Report file path to Han; terminal không render image inline.
7. **Incremental concept index growth.** Append rows to `learning/library/<book-slug>.md` concept table after each successful query.
8. **Cross-link to track GLOSSARY khi relevant.** Nếu concept đã có GLOSSARY entry, mention "GLOSSARY has the definition; <book> gives the proof at §X.Y".
9. **No em-dashes (U+2014).** Per global formatting rule.

## Workflow

### Step 1: Identify book + concept

From Han's question, extract:
- Book reference: title (full or partial), author last name, or both.
- Concept: the topic Han wants.
- Type of return: excerpt (text quote), figure (image), or both.

If book ambiguous, ask Han.

### Step 2: Locate or bootstrap book index

Check `learning/library/<book-slug>.md`:

- **Exists**: read it. Has TOC + concept index + EPUB structure note (XHTML naming convention, image folder pattern).
- **Doesn't exist**: bootstrap.
  - Find source file (default `~/Downloads/annas/` per annas-fetch convention).
  - Determine format (EPUB / PDF / MOBI).
  - **EPUB**: peek inside via `unzip -l <book.epub>`. Note XHTML naming (eg `OEBPS/html/<prefix>_<N>_Chapter.xhtml`) + image folder pattern (eg `OEBPS/images/<prefix>_<N>_Chapter/`). Write these to index file frontmatter as `xhtml_pattern` + `image_pattern`. NO pandoc conversion at this step.
  - **PDF**: no extraction; use Read tool's `pages` parameter natively.
  - **MOBI**: `ebook-convert <book> intermediate.epub` (cần Calibre). Then EPUB path. Or convert to PDF.
  - Build TOC: for EPUB, parse `OEBPS/package.opf` (spine order) or `OEBPS/toc.ncx` (TOC). For PDF, read first 10-20 pages via Read tool, identify chapter headings.
  - See reference: `learning/library/wong-quantum-2023.md` cho format.

### Step 3: Headless search (EPUB)

For EPUB, use unzip+grep on the fly. **Do NOT pre-convert to markdown**.

```bash
# Search across all chapter XHTML files (~0.01s on 30 MB book)
unzip -p "<book.epub>" 'OEBPS/html/*Chapter*.xhtml' 2>/dev/null | grep -in "<keyword>"

# Narrow to specific chapter once identified
unzip -p "<book.epub>" "OEBPS/html/<prefix>_<N>_Chapter.xhtml" 2>/dev/null | grep -in "<keyword>"

# Get surrounding context (3 lines before + 5 after)
unzip -p "<book.epub>" "OEBPS/html/<prefix>_<N>_Chapter.xhtml" 2>/dev/null | grep -in -B 3 -A 5 "<keyword>"
```

For PDF, use Read tool's `pages` parameter directly (figures included). No grep needed for individual queries; use `pages: "<range>"` after identifying chapter from TOC.

**Pandoc fallback**: if unzip+grep returns too many hits (>50 chapters all matching), or chapter XHTML is obfuscated/encrypted, convert that book once: `pandoc -f epub -t markdown --extract-media=learning/library/_assets/<slug> <book> -o learning/library/_text/<slug>.md`. Use the MD file for fast grep. Update index frontmatter to add `text_path` field. This is on-demand fallback, không default.

### Step 4: Extract figures/equations on-demand

When excerpt references an image (figure, equation, diagram):

1. Identify image path inside EPUB. Common patterns:
   - Equations: `OEBPS/images/<prefix>_<N>_Chapter/<prefix>_<N>_Chapter_TeX_IEq<id>.png` (Springer convention).
   - Figures: `OEBPS/images/<prefix>_<N>_Chapter/<prefix>_<N>_Chapter_Fig<num>_HTML.png`.
   - Inline equations: usually small PNG ~1-3 KB; can quote textually if math is simple.
2. Extract via unzip:
   ```bash
   mkdir -p "learning/library/_assets/<slug>/ch<N>/"
   unzip -p "<book.epub>" "OEBPS/images/<prefix>_<N>_Chapter/<img>.png" > "learning/library/_assets/<slug>/ch<N>/<img>.png"
   ```
3. Cache hit: if file already exists in `_assets/`, skip extraction.
4. Report path to Han: "Figure 19.3 saved to `learning/library/_assets/wong-quantum-2023/ch19/Fig3.png`, mở bằng QuickLook để xem".

For PDF: image extraction usually unnecessary; Read tool's page render includes figures. If Han specifically wants standalone figure file, `pdfimages -png <book.pdf> <prefix>` (Poppler tools, `brew install poppler`).

### Step 5: Quote + cite inline

Format in response:

```
Wong dành Ch 19 cho no-cloning theorem. Statement và proof cốt lõi:

> [3-5 sentence verbatim quote]

Wong (2023), §19.2. [Day-02 block 12 mention nó là bẫy chính của fault
tolerance; Wong's proof shows linearity argument explicitly.]
```

Components:
1. Lead sentence introducing source (chapter + topic).
2. Blockquote 3-5 sentences verbatim từ XHTML body (after stripping HTML tags).
3. Citation `Author (Year), §X.Y`.
4. Optional bracket commentary linking back to current context (Day-NN block, GLOSSARY entry).
5. If figure extracted, mention path: "Equation rendered ở `learning/library/_assets/<slug>/ch<N>/<file>.png`."

### Step 6: Update concept index

After successful excerpt, append/update row in `learning/library/<book-slug>.md`:

```markdown
| no-cloning theorem | Ch 19.2 | OEBPS/html/<prefix>_19_Chapter.xhtml | Statement + linearity proof. Day-02 block 12 references this. |
```

Format: `concept | chapter.section | XHTML file (or PDF page range) | 1-câu coverage note`.

### Step 7: GUI fallback for complex chapter

If chapter has heavy layout (multi-column, tables, embedded code listings difficult to extract textually), suggest GUI:

- **EPUB on macOS**: `open "<book.epub>"` opens Apple Books by default. Han navigates manually. Skill surfaces chapter number + key page hints.
- **PDF on macOS**: `open "<book.pdf>"` opens Preview. Cmd-F searches inline.
- **Calibre ebook-viewer**: only if installed (`brew install --cask calibre`). Better search than Books.app.

Don't auto-open GUI; suggest to Han and let them invoke.

### Step 8: Propose follow-ups

End of response:
- "Cuốn này cũng có Ch X về <related concept>, muốn excerpt thêm không?"
- "Day-N của QWorld sẽ touch chủ đề này; có thể parallel-read."
- "<other book> có treatment khác về cùng concept; download xem thử?"

## Edge cases

- **Book không có trong `~/Downloads/annas/`**: ask Han where it is.
- **EPUB DRM-protected**: unzip will fail. Try `ebook-convert` (Calibre) to strip DRM if Han owns license. Otherwise stop.
- **PDF không có TOC pages**: scan first 20 pages; nếu không thấy "Contents", scan chapter title pages từ early pages.
- **Excerpt vượt 5 sentences**: summarize thay vì quote dài.
- **Concept không tìm được trong book**: nói thật "Cuốn này không nhắc <X>; suggest <other book>". Update "What's NOT in this book" section.
- **Image extracted nhưng Han không thấy được trong terminal**: standard limitation; Han mở file bằng QuickLook (Space bar in Finder) hoặc `open <file>.png`.
- **Han asks for SVG/vector image**: EPUB sometimes has SVG figures; extract preserving format.

## Anti-patterns

1. **Default pre-conversion to markdown**: v1 anti-pattern. Han pushback: "if we don't have to convert to text md, will be better". Use unzip+grep on the fly. Pandoc fallback only.
2. **Quote >5 sentences**: respect copyright + reader attention.
3. **No citation**: every excerpt MUST cite.
4. **Skip index update**: missing growth opportunity.
5. **Extract all images on bootstrap**: wasteful disk usage. On-demand per query.
6. **Auto-open GUI without asking**: surface as option; Han invokes.

## Reference

- Library home: `~/workspace/tieubao/ops-toolkit/learning/library/`
- Library README: `learning/library/README.md`
- Reference index file: `learning/library/wong-quantum-2023.md` (canonical example of v2 format with XHTML references).
- Image assets: `learning/library/_assets/<slug>/ch<N>/` (gitignored, on-demand cache).
- Companion skills:
  - `annas-fetch`: download books into `~/Downloads/annas/`.
  - `concept-explain`: GLOSSARY-aware Q&A; can cross-link to library.
  - `learning-day-process`: class-transcript ingestion.
- Tools needed:
  - `unzip` (system default on macOS).
  - `pandoc` (`brew install pandoc`, for fallback conversion).
  - `pdfgrep` (`brew install pdfgrep`, optional for PDF text search if Read tool not enough).
  - Apple Books (built-in) for EPUB GUI.
  - `calibre` (optional, `brew install --cask calibre`) for better EPUB viewer + DRM strip.
