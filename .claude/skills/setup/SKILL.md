---
name: setup
description: First-time setup — asks the user for the path to their statement files, auto-detects providers and card numbers, asks minimal questions, writes cards.yaml, then runs /review-spending for every discovered statement.
allowed-tools: Read, Write, Edit, Bash(pdftotext *), Bash(find *), Bash(ls *), Bash(bash *)
argument-hint: (no arguments needed)
---

# Setup Skill

Automate first-time configuration. Ask the user where their statement files are, scan that location, identify all statement files, ask only what cannot be inferred, write `personal-info/cards.yaml`, and process every statement.

---

## Step 1 — Check if already configured

Read `personal-info/cards.yaml` if it exists. If it already has providers defined, tell the user:
> "`personal-info/cards.yaml` is already configured with providers: [list keys]. Run `/review-spending <key> <MM> <YYYY>` to process a statement. Run `/setup` again only if you're adding new cards."

Then stop — do not overwrite an existing config without permission. (Exception: if the user says "reconfigure" or "reset", proceed.)

---

## Step 2 — Ask the user for their file locations

Ask the user:
> "Where are your credit card PDF statements? Please provide the path to the folder (e.g. `~/Documents/statements/`). The folder should contain year-based subdirectories (e.g. `2025/`, `2026/`) with the PDFs inside."
>
> "Do you also have a bank statement Excel file (*עובר ושב*)? If so, what is the full path to it?"

Wait for the user's answers, then scan the specified path(s):

```bash
find <statements_path> -type f \( -name "*.pdf" -o -name "*.xlsx" -o -name "*.xls" \) | sort
```

Group files by type:
- **PDFs** — credit card statements
- **Excel files** — likely bank statements (or use the explicit bank path if provided)

If no files are found at the given path, tell the user and stop:
> "No statement files found at `<path>`. Please check the path and try again."

Stop.

---

## Step 3 — Identify each PDF's provider

For each PDF found, run `pdftotext -layout "<path>" -` and inspect the first ~100 lines of output to detect the provider:

**Detection rules:**

| Signal in extracted text | Provider | `statement_format` |
|---|---|---|
| Contains "מקס" or "max.co.il" or "MAX IT" | Max | `max` |
| Contains "כאל" or "cal-online" or "CAL" and NOT Max signals | CAL | `cal` |
| Contains "ישראכארט" or "Isracard" | Isracard | `isracard` (no format yet — note to user) |
| Contains "לאומי קארד" or "Leumi Card" | Leumi Card | `leumi` (no format yet) |
| Contains "אמריקן אקספרס" or "American Express" | Amex Israel | `amex` (no format yet) |

For each PDF also extract:
- The **card last-4 digits** — look for 4-digit sequences near "כרטיס" or "****" or the card number pattern. For Max, all card numbers appear in the transaction rows (כרטיס column). For CAL, the card number usually appears in the header.
- The **billing month and year** — look for the billing date pattern, or parse from the filename.

**For providers with no format section in CLAUDE.md** (anything other than `max` and `cal`): tell the user you found an unsupported provider, show a sample of the extracted text, and ask if they'd like to add support for it now. If yes, analyze the layout and add a new `Format: <name>` section to `CLAUDE.md`. If no, skip those files.

---

## Step 4 — Group PDFs into providers

PDFs from the same provider (same provider name + same card last-4) belong to one provider entry in `cards.yaml`. PDFs from the same provider but different card numbers are separate providers.

For Max: a single PDF may contain transactions for multiple cards. Extract all unique card last-4 values from the transaction data.

For CAL: each PDF is one card. If you find two CAL PDFs with different card numbers, they are separate provider entries (e.g. `cal1234` and `cal5678`). Check the filename for distinguishing patterns — e.g. if one has "(1)" suffix and the other doesn't, note that in `pdf_pattern`.

Build a proposed provider map:
```
max       → Max PDFs, cards: [XXXX, YYYY]
cal_XXXX  → CAL PDF (no suffix), card: XXXX
cal_YYYY  → CAL PDF ("(1)" suffix), card: YYYY
```

---

## Step 5 — Detect PDF filename pattern

For each provider, infer the `pdf_pattern` by examining the filenames across multiple months:

- Find the part that changes month-to-month and replace it with the appropriate placeholder:
  - 4-digit year → `{year}`
  - Month without leading zero → `{month}`
  - 2-digit month → `{MM}`
  - 2-digit year → `{YY}`
- Keep the rest of the filename literal (including Hebrew characters).

Example: if you see `2025_11_max.pdf` and `2026_2_max.pdf`, the pattern is `{year}_{month}_max.pdf`.

If only one PDF exists for a provider, make your best guess and tell the user what you assumed.

---

## Step 6 — Detect Excel bank statements

For each Excel file found, check if it looks like a bank statement:
- Run: `python3 -c "import openpyxl; wb = openpyxl.load_workbook('<path>'); ws = wb.active; [print([c.value for c in r]) for r in ws.iter_rows(min_row=1, max_row=10, values_only=True)]"`
- If it contains Hebrew columns like "תאריך", "תיאור התנועה", "יתרה" — it's a checking account statement (עובר ושב).
- Identify the bank from the file content (look for bank name in header rows, or ask the user).

Note the file path. Bank Excel files are imported separately (not part of `cards.yaml`).

---

## Step 7 — Ask the user minimal questions

Present your findings as a clear summary, then ask only what you couldn't infer:

```
Found the following statements:

Credit cards:
  • Max — cards: [XXXX, YYYY] — 4 PDFs (Nov 2025 – Feb 2026)
  • CAL — card: ZZZZ — 6 PDFs (Aug 2025 – Jan 2026)
  • CAL — card: WWWW — 5 PDFs (Aug 2025 – Dec 2025)

Bank:
  • Discount Bank checking account — 1 Excel file (12 months)

Questions:
1. What is your name? (used in spending-profile.md)
2. For Max card XXXX — what label should I use? (e.g. "Primary card", "Personal spending")
3. For Max card YYYY — label?
4. For CAL card ZZZZ — label?
5. For CAL card WWWW — label?
```

Do NOT ask about things you can detect: provider names, card numbers, PDF patterns, billing months.

Wait for the user's answers before proceeding.

---

## Step 8 — Write cards.yaml

Using the detected data and user answers, write `personal-info/cards.yaml` (create `personal-info/` directory if needed):

```yaml
owner: "<user's name>"

providers:
  max:
    name: "Max"
    pdf_pattern: "<detected pattern>"
    statement_format: "max"
    cards:
      - last4: "XXXX"
        label: "<user label>"
      - last4: "YYYY"
        label: "<user label>"

  cal<ZZZZ>:
    name: "CAL"
    pdf_pattern: "<detected pattern>"
    statement_format: "cal"
    cards:
      - last4: "ZZZZ"
        label: "<user label>"

  cal<WWWW>:
    name: "CAL (via Bank Discount)"
    pdf_pattern: "<detected pattern>"
    statement_format: "cal"
    cards:
      - last4: "WWWW"
        label: "<user label>"
```

Show the user the file contents and confirm before writing.

---

## Step 9 — Process all statements

Now run `/review-spending` for every discovered statement, in chronological order (oldest first), for each provider.

Tell the user:
> "Configuration saved. Now processing all [N] statements. This will take a few minutes — I'll process them in order and build your spending profile as I go."

For each statement, invoke the review-spending skill logic directly (do not call `/review-spending` as a sub-command — instead execute the same steps as that skill inline):

**For each (provider_key, month, year) tuple, in chronological order:**
1. Follow all steps from `.claude/skills/review-spending/SKILL.md`
2. Print a brief one-line status: `✓ max 2025-11 — ₪12,340 across 67 transactions`
3. Continue to next

---

## Step 10 — Import bank Excel (if found)

After all credit card statements are processed, handle the bank Excel:

Run the bank import Python script inline:

```python
import openpyxl, json, os
from datetime import datetime
from collections import defaultdict

wb = openpyxl.load_workbook('<excel_path>')
ws = wb.active

# Find data start row (look for "תאריך" header)
header_row = None
for i, row in enumerate(ws.iter_rows(min_row=1, max_row=20, values_only=True), 1):
    if any(str(c) == 'תאריך' for c in row if c):
        header_row = i
        break

if header_row is None:
    print("Could not find header row")
    exit(1)

def classify(desc):
    d = str(desc).strip()
    if 'משכורת' in d or 'שכר' in d: return 'Salary'
    if 'מקס' in d or 'MAX' in d.upper(): return 'Credit Card Payment'
    if 'כ.א.ל' in d or 'כאל' in d or 'ויזה' in d: return 'Credit Card Payment'
    if 'איביאי' in d or 'IBI' in d.upper(): return 'Investment Transfer'
    if 'ני"ע' in d or 'קרן' in d or 'אנליסט' in d: return 'Investment Purchase'
    if 'שיק' in d: return 'Check'
    if 'מזומן' in d or 'כספומט' in d: return 'ATM Withdrawal'
    if 'עמלה' in d or 'עמלות' in d: return 'Bank Fees'
    if 'החזר' in d and ('עמלה' in d or 'ריבית' in d): return 'Bank Fee Refund'
    if 'ריבית' in d: return 'Interest'
    if 'ביטוח' in d: return 'Insurance'
    return 'Other'

transactions = []
for row in ws.iter_rows(min_row=header_row+1, values_only=True):
    date_val, value_date, description, amount, balance, ref, fee, channel = (list(row) + [None]*8)[:8]
    if date_val is None or description is None: continue
    if isinstance(description, str) and description.strip() in ('תנועות עתידיות', 'N/A', ''): continue
    if isinstance(amount, str): continue
    date_str = date_val.strftime('%Y-%m-%d') if hasattr(date_val, 'strftime') else str(date_val)
    vdate_str = value_date.strftime('%Y-%m-%d') if hasattr(value_date, 'strftime') else (str(value_date) if value_date else date_str)
    transactions.append({
        "date": date_str, "value_date": vdate_str,
        "description": str(description).strip(),
        "amount": round(float(amount), 2),
        "balance": round(float(balance), 2) if balance is not None else None,
        "ref": str(ref).strip() if ref else "",
        "channel": str(channel).strip() if channel else "",
        "category": classify(str(description))
    })

by_month = defaultdict(list)
for tx in transactions:
    by_month[tx['date'][:7]].append(tx)

data_dir = 'personal-info/dashboard/data'
os.makedirs(data_dir, exist_ok=True)

for ym, txs in sorted(by_month.items()):
    year, month = ym.split('-')
    income = [t for t in txs if t['amount'] > 0]
    expenses = [t for t in txs if t['amount'] < 0]
    cat_map = defaultdict(lambda: {'total': 0.0, 'count': 0})
    for t in txs:
        cat_map[t['category']]['total'] = round(cat_map[t['category']]['total'] + t['amount'], 2)
        cat_map[t['category']]['count'] += 1
    total_income = round(sum(t['amount'] for t in income), 2)
    total_expenses = round(sum(abs(t['amount']) for t in expenses), 2)
    invested = round(sum(abs(t['amount']) for t in expenses if t['category'] in ('Investment Transfer','Investment Purchase')), 2)
    salary = round(sum(t['amount'] for t in income if t['category'] == 'Salary'), 2)
    sorted_txs = sorted(txs, key=lambda t: t['date'])
    obj = {
        "account": "<account_number>", "bank": "<bank_name>", "month": ym,
        "totalIncome": total_income, "totalExpenses": total_expenses,
        "netCashFlow": round(total_income - total_expenses, 2),
        "totalSalary": salary, "totalInvested": invested,
        "closingBalance": sorted_txs[-1]['balance'] if sorted_txs else None,
        "categories": [{"name": k, "total": round(v['total'],2), "count": v['count']} for k,v in cat_map.items()],
        "transactions": sorted_txs
    }
    fname = f'bank_discount_{year}_{month}.json'
    with open(os.path.join(data_dir, fname), 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    print(f"✓ Bank {ym} — income {total_income}, expenses {total_expenses}")
```

Fill in the actual account number and bank name from the Excel header rows before running.

After import, rebuild the dashboard:
```bash
bash dashboard/build.sh
```

---

## Step 11 — Done

Print a summary:
```
✅ Setup complete!

Processed:
  • Max: 4 months
  • CAL 1234: 6 months
  • CAL 5678: 5 months
  • Bank (Discount): 12 months

To review a new statement next month:
  /review-spending max 03 2026

To open the dashboard:
  open dashboard/index.html
```
