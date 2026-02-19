# Credit Card Statement Monitor

This project parses Israeli credit card and bank statement PDFs using `pdftotext -layout <file>`. Statement PDFs can live anywhere on your machine — they do not need to be inside this directory.

## Configuration

Read `personal-info/cards.yaml` for the list of configured providers, their PDF naming patterns, card numbers, and statement format references. Each provider key maps to a "Format:" section below for parsing rules.

For a new provider without a format section, extract text with `pdftotext -layout` from a sample PDF, analyze the layout, and add a new "Format:" section below.

## Directory Structure

Statement PDFs live on the user's machine outside this project — the user specifies the path during `/setup`. The expected structure is year-based subdirectories (e.g. `2025/`, `2026/`) with PDFs inside. The absolute path to this folder is stored implicitly via the `pdf_pattern` in `personal-info/cards.yaml`. When resolving a PDF path for a given month, combine the statements root path (ask the user if unclear) with the provider's `pdf_pattern`.

## Format: max

Provider: Max (מקס) — max.co.il

Transactions grouped by billing date (חיוב ב DD.MM.YYYY). Fields (right-to-left):

| Hebrew | English | Notes |
|---|---|---|
| ת.עסקה | Transaction Date | DD.MM.YY |
| שם בית העסק | Merchant Name | |
| קטגוריה | Category | See categories below |
| כרטיס | Card | Last 4 digits |
| סוג עסקה | Transaction Type | See types below |
| סכום | Amount | ILS (₪), foreign currency shown below |

**Transaction Types**: רגילה (regular), חיוב עסקת חו"ל בש"ח (foreign in ILS), חיוב עסקות מיידי (instant foreign), הוראת קבע (standing order), תשלום X מתוך Y (installment X of Y)

**Categories**: מסעדות קפה וברים (restaurants/cafes/bars), טיסות ותיירות (flights/tourism), תחבורה ורכבים (transport/vehicles), מזון וצריכה (food/groceries), פנאי בידור וספורט (leisure/entertainment/sports), אופנה (fashion), עיצוב הבית (home design), העברת כספים (money transfers), ביטוח (insurance), שונות (misc), ספרים ודפוס (books/print)

## Format: cal

Provider: CAL (כאל) — cal-online.co.il

Single billing cycle per statement. Fields (right-to-left):

| Hebrew | English | Notes |
|---|---|---|
| תאריך העסקה | Transaction Date | DD/MM/YYYY |
| שם בית העסק | Merchant Name | |
| ענף | Category | See categories below |
| פירוט | Details | Payment method, Apple Pay, הוראת קבע, country |
| סכום העסקה | Transaction Amount | Original amount |
| כרטיס הוצג | Card Presented | Whether physical card was used |
| סכום חיוב | Charge Amount | Billed in ILS |

**Categories**: תיירות (tourism), מזון ומשקא (food/beverages), ריהוט ובית (furniture/home), אופנה (fashion), פנאי בילוי (leisure), תקשורת ומח (telecom/computers), מוסדות (institutions), בתי כלבו (department stores)

## Parsing Notes

- All PDFs are Hebrew RTL text. Use `pdftotext -layout` for extraction.
- Foreign transactions show both ILS and original currency (EUR €, USD $).
- Installments: "תשלום X מתוך Y" with total on a separate line.
- CAL includes frequent flyer points balance (נקודות טיסה).

## Credit Card Monitoring

### Responsibilities

When new PDF statements are added to this directory, Claude should:

1. **Review against spending profile**: Read `spending-profile.md` for baseline spending patterns, known merchants, recurring payments, and typical amounts.
2. **Flag suspicious transactions**: Any transaction matching the anomaly detection guidelines in `spending-profile.md` should be called out — unknown merchants, unusual amounts, missing recurring payments, etc.
3. **Flag high-amount transactions**: Any single transaction above ₪500 should be listed individually for review.
4. **Verify recurring payments**: Check that all expected standing orders and subscriptions are present and within expected amount ranges.

### Quick Review

Use the `/review-spending` skill to generate a structured spending review:
```
/review-spending <provider_key> <month> <year>
```
Where `<provider_key>` is a key from `cards.yaml` (e.g., `max`, `cal1234`, `cal5678`).

### Files

- `personal-info/cards.yaml` — Provider configuration, card numbers, PDF patterns. See `cards.example.yaml` for template. **Not committed to git.**
- `personal-info/spending-profile.md` — Known merchants, recurring payments, typical amounts, anomaly detection rules. Auto-updated by `/review-spending`. **Not committed to git.**
- `personal-info/dashboard/data/*.json` — Per-month transaction data. **Not committed to git.**
- `.claude/skills/review-spending/SKILL.md` — Skill definition for the spending review command.
