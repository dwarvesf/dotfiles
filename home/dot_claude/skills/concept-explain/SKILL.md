---
name: concept-explain
description: Use when Han asks "X là gì?" / "explain X" / "what is X" for a technical concept within any `learning/<topic>/` track (quantum computing, mathematics, security, etc.). Trigger phrases include "X là gì?", "explain X", "what is X", "/concept X", "giải thích X", "tại sao X", or any single-concept question while Han is in a learning context. Workflow: (1) check existing GLOSSARY.md to avoid duplicate, (2) answer in adaptive 4-layer mode (định nghĩa + first-principles + ví dụ + analogy), (3) propose saving to GLOSSARY.md if concept has cross-topic value. NOT for class-transcript processing (use learning-day-process). NOT for full lesson walkthrough (use learning-day-process to generate Day-NN-explained.md).
---

# Concept Explain

Answer ad-hoc concept questions within Han's learning tracks. Glossary-aware (avoid duplicate explanation), prose-first, with self-check + answer key. Grows `GLOSSARY.md` incrementally when concept has cumulative cross-topic value.

## When to use

- Han asks "X là gì?" / "explain X" / "what is X" while in a learning context.
- Han is reading a `Day-NN-explained.md` and asks about a concept that wasn't covered in detail.
- Han encounters a term in a paper / textbook / transcript and wants a beginner-friendly explanation.

## When NOT to use

- Han just dropped a class transcript and wants the day processed → use `learning-day-process`.
- Han asks a how-to / debugging question that's not conceptual → answer directly.
- Han wants a deep multi-page walkthrough of a topic → use `learning-day-process` style (Day-NN-explained.md).
- Concept is outside any learning track (general programming, ops, etc.) → answer directly without the skill structure.

## Hard rules

1. **Glossary check first.** If `learning/<topic>/courses/<course>/GLOSSARY.md` or `learning/<topic>/GLOSSARY.md` already has an entry for the concept, surface it instead of re-explaining. Quote the relevant sections. Save Han's time.
2. **Adaptive 4-layer answer.** Định nghĩa → First-principles WHY → Ví dụ → Analogy. Plus optional: 🚨 Bẫy, 💼 Liên kết chuyên ngành, 📊 Diagram. Per `feedback_learning_tutoring_format` memory.
3. **Prose-first, không bullet-heavy.** Diễn giải tiếng Việt là vehicle chính. Bullets chỉ khi liệt kê 3+ items.
4. **Bilingual EN/VN selective.** Gloss tiếng Việt chỉ cho term khó/lạ. Term quen với Han (algorithm, polynomial, deterministic): KHÔNG gloss.
5. **Cross-link only when natural.** 💼 liên kết chuyên ngành CHỈ khi illuminating (vd "P vs NP giống Bitcoin PoW"). Drop khi gượng.
6. **Self-check + đáp án always.** Mọi câu trả lời kết thúc bằng 🤔 self-check (2-3 câu) + 🎓 đáp án ngay sau.
7. **No em-dashes (U+2014).** Per global formatting rule.

## Workflow

### Step 1: Determine learning context

From cwd or recent files, identify which track Han is in:
- Inside `learning/<topic>/courses/<course>/` → use that.
- Inside a different folder but conversation context shows a recent class processing → use that track.
- Ambiguous → ask "Bạn đang hỏi trong context nào? (quantum / math / security / etc.)".

### Step 2: Check GLOSSARY

Read `learning/<topic>/courses/<course>/GLOSSARY.md` (if exists) and `learning/<topic>/GLOSSARY.md` (if exists, track-level glossary). Look for an entry matching the concept (case-insensitive, allow aliases).

If found:
- Surface the existing entry verbatim (or summarize if it's long).
- Add 1-2 paragraphs of context if Han's question implies he wants more depth than the glossary entry provides.
- Skip to step 5 (offer to update glossary if Han wants to expand).

If not found, proceed to step 3.

### Step 3: Answer in adaptive 4-layer mode

Structure:

**Định nghĩa** (1-2 paragraphs prose tiếng Việt). Term tiếng Anh lần đầu xuất hiện kèm VN gloss nếu term khó/lạ. Term quen: không gloss.

**🔬 First-principles WHY** (1-2 paragraphs). Đặt câu hỏi gốc, đưa ra alternatives đã loại, giải thích engineering choice. Đây là phần làm Han hiểu deep, không chỉ memorize.

**Ví dụ đơn giản nhất** (concrete instance high-schooler level). 1-3 examples tuỳ concept.

**Analogy quen thuộc** (link domain Han biết: software engineering, crypto/DeFi trading, business ops, family-office, hardware security). Chỉ khi analogy mạnh; drop khi gượng.

**Optional sections** (chọn 0-3 khi serve concept):
- 📊 Diagram (ASCII art, comparison table, Venn). Khi structural.
- 💼 Liên kết chuyên ngành (nếu cross-link tự nhiên với domain Han biết). Drop khi forced.
- 🚨 Bẫy / Để ý (2-3 common traps).
- 💡 Side note (history, etymology, nuance).

### Step 4: Self-check + đáp án

**🤔 Self-check**: 2-3 open-ended questions.

**🎓 Đáp án**: ngay sau, 2-3 câu trả lời mỗi câu. Han không phải tự đoán.

### Step 5: Propose GLOSSARY update

Sau khi trả lời, đánh giá xem concept có **cumulative cross-topic value** không:

- **Có cross-topic value**: foundational concept sẽ tái xuất ở nhiều Day / chapter (vd: "polynomial time", "decoherence", "BQP"). → propose save to GLOSSARY.
- **Course-specific only**: concept chỉ relevant cho 1 course/day (vd: "QBronze notebook Q24"). → skip GLOSSARY.
- **Quá đơn giản**: concept Han chắc đã biết, hỏi chỉ để verify (vd: "binary string"). → skip.

Propose format: "Concept này có giá trị cumulative. Có muốn save vào GLOSSARY.md không?". Nếu Han accept, append entry alphabetically vào GLOSSARY.md với footer `first seen: Day-NN` (figure out which Day this came up from context).

### Step 6: Active collaboration

Per `feedback_propose_during_work`: nếu thấy gì gợn trong lúc answer (vd: concept overlap với entry GLOSSARY khác, opportunity merge, gap in syllabus), surface inline cuối response.

## Edge cases

- **Concept không có trong track**: Han hỏi về concept ngoài QC/math nhưng đang ở qworld track. Answer trong context Han hiện tại, mention "đây không phải standard QC concept" nếu cần. Don't push back hard.
- **Concept Han hỏi 2 lần**: nếu hỏi lại concept đã được explain trong session này, surface GLOSSARY entry (nếu đã save) hoặc kéo lại từ conversation history. Đừng re-explain identically.
- **Concept đa nghĩa**: vd "state" trong QC vs "state" trong classical CS. Hỏi clarify trước, hoặc explain cả 2 nghĩa với context distinction.
- **Concept không trong learning context**: Han hỏi "X là gì?" về general topic (vd "what is gRPC?"). Skill không apply; answer directly, không cần GLOSSARY structure.
- **GLOSSARY.md không tồn tại yet**: bootstrap file với header + frontmatter on first save. Use existing reference: `learning/quantum-computing/courses/qworld-oqi/GLOSSARY.md`.

## Anti-patterns

1. **Re-explain concept đã có trong GLOSSARY**: waste of Han's time. Check first.
2. **14-section rigid template**: was v2 anti-pattern. Use adaptive (4-layer + optional). Per `feedback_learning_tutoring_format`.
3. **Bilingual gloss everywhere**: overload. Selective.
4. **Forced cross-link**: skip when not natural.
5. **Skip self-check + đáp án**: Han uses these to verify hiểu. Always include.
6. **Auto-save to GLOSSARY without asking**: per Han's working style "NEVER delete anything unless I explicitly say so" + propose-before-execute. Ask first.

## Reference

- Format contract: `~/.claude/projects/-Users-tieubao-workspace-tieubao-ops-toolkit/memory/feedback_learning_tutoring_format.md`
- Active collaboration: `~/.claude/projects/-Users-tieubao-workspace-tieubao-ops-toolkit/memory/feedback_propose_during_work.md`
- Reference glossary (qworld-oqi): `~/workspace/tieubao/ops-toolkit/learning/quantum-computing/courses/qworld-oqi/GLOSSARY.md`. P vs NP entry là canonical example của 4-layer mode đúng cách.
- Companion skill: `learning-day-process` (for class-transcript ingestion + Day-NN-explained generation).
