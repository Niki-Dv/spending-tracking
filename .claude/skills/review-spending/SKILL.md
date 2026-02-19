---
name: review-spending
description: Review and summarize credit card spending from a monthly statement
disable-model-invocation: true
allowed-tools: Read, Edit, Bash(pdftotext *)
argument-hint: [provider_key] [month: MM] [year: YYYY]
---

# Review Spending Skill

Review a monthly credit card statement against the known spending profile and produce a structured summary.

## Arguments

- `provider_key`: A provider key from `cards.yaml` (e.g., `max`, `cal1234`, `cal5678`)
- `month`: 2-digit month (e.g., `02`)
- `year`: 4-digit year (e.g., `2026`)

## Steps

### 1. Load config and baseline data

Read the config and spending profile (paths relative to project root):
```
Read: personal-info/cards.yaml
Read: personal-info/spending-profile.md
```

Find the provider entry in `personal-info/cards.yaml` matching the `provider_key` argument. If not found, list available provider keys and abort.

**First run:** If `personal-info/spending-profile.md` doesn't exist, it will be created from scratch in Step 5. Skip anomaly detection (no baseline) and recurring payment checks for the first run. Populate it with the first statement's data.

### 2. Extract statement text

Resolve the PDF path from the provider's `pdf_pattern` in `cards.yaml`. Substitute template variables:
- `{year}` → 4-digit year (e.g., `2026`)
- `{month}` → month WITHOUT leading zero (e.g., `2`)
- `{MM}` → 2-digit month (e.g., `02`)
- `{YY}` → 2-digit year (e.g., `26`)

The PDF lives in `{year}/` subdirectory under the project root.

Run: `pdftotext -layout "<pdf_path>" -` to extract text.

### 3. Parse transactions

Look up `statement_format` from the provider config in `cards.yaml`. Find the matching "Format: {statement_format}" section in `CLAUDE.md` for parsing rules.

Parse all transactions from the extracted text. For each transaction extract:
- Date
- Merchant name
- Category
- Amount (₪)
- Transaction type (regular, standing order, installment, foreign)
- Card (last 4 digits, for providers with multiple cards)

**Merchant category overrides:** Regardless of what the statement PDF says, always assign these categories:
- Merchant name contains "aliexpress" (case-insensitive) → category: `"Online Shopping"`
- Merchant name is "AMAZON" or contains "amazon" (case-insensitive) → category: `"Online Shopping"`

### 4. Produce structured report

Output the following sections **in this order**:

#### Suspicious / Abnormal Transactions
List any transactions matching anomaly detection guidelines from spending-profile.md:
- Unknown merchants (not in spending profile)
- Recurring payment amount changed >10%
- Transaction from a new foreign country
- Possible duplicates (same merchant, same day, same amount)
- Missing expected recurring payments

Format each as a bullet with the reason for flagging.

#### High Amount Transactions (₪500+)
List each transaction over ₪500 individually with date, merchant, amount, and category.

#### Spending by Category
For each category, show:
- Category name
- Total amount
- Transaction count
- Top merchants by spend

#### Recurring Payments Check
For each expected recurring payment (from spending-profile.md) relevant to this card:
- Show whether it appeared in this statement
- Compare the amount to the expected range
- Flag if missing or amount changed significantly

#### Monthly Total
- This month's total
- Historical average for this card
- Difference / trend note

### 5. Auto-update spending-profile.md

After presenting the report, update `personal-info/spending-profile.md` with new data.

**First run (file doesn't exist):** Create `personal-info/spending-profile.md` from scratch using the owner name and card details from `personal-info/cards.yaml`. Populate with data from the first statement. Use the existing format if you have a reference, otherwise create sections for: cards overview, recurring payments, merchant categories, monthly totals, anomaly detection guidelines.

**DO update:**
- Add new merchants that appear legitimate (not flagged as suspicious) to the appropriate category
- Expand amount ranges if a category's range has been exceeded by a legitimate transaction
- Update recurring payment amounts if they changed (e.g., price increases)
- Add new countries seen in foreign transactions
- Update monthly total averages with the new data point (add new row to the table)

**DO NOT update:**
- Do NOT add merchants that were flagged as suspicious/unknown — only after user confirms they're legit
- Do NOT remove existing merchants from the profile

Use the Edit tool to make targeted updates to `personal-info/spending-profile.md`.

### 6. Generate dashboard JSON

After producing the terminal report and updating spending-profile.md, write a JSON file to `personal-info/dashboard/data/{provider_key}_{year}_{month}.json`.

Build `cardLabel` from config: use the provider's `name` field + last4 digits of all its cards (e.g., "Max (1234 + 5678)", "CAL (1234)").

**JSON schema:**
```json
{
  "card": "<provider_key>",
  "cardLabel": "Max (1234 + 5678)",
  "month": "YYYY-MM",
  "total": 12360.27,
  "transactionCount": 67,
  "categories": [
    { "name": "Restaurants & Cafes", "total": 3347.56, "count": 29 }
  ],
  "suspicious": [
    { "merchant": "SPOTIFY", "amount": 23.90, "reason": "Card changed from CAL 1234 to Max 5678" }
  ],
  "highAmount": [
    { "date": "2025-12-29", "merchant": "Sample Merchant", "amount": 4435.63, "category": "Flights & Tourism", "note": "Installment 2/3" }
  ],
  "recurring": [
    { "merchant": "Sample Insurance", "expected": "₪286–288", "actual": 286.86, "status": "ok" }
  ],
  "monthlyHistory": [
    { "month": "2025-11", "total": 4782 },
    { "month": "2026-02", "total": 12360 }
  ],
  "average": 8987,
  "transactions": [
    { "date": "2026-01-20", "merchant": "Sample Cafe", "amount": 500.66, "category": "Restaurants & Cafes", "note": "", "card": "1234" }
  ]
}
```

**Transactions array notes:**
- Include ALL transactions from the statement (not just high-amount ones).
- Each transaction: `date` (ISO YYYY-MM-DD), `merchant` (clean name), `amount` (ILS number), `category` (English name), `note` (installment info, standing order, country for foreign — empty string if none), `card` (last 4 digits of the card used — always include, even for single-card providers).
- Apply merchant category overrides from Step 3 (e.g., AliExpress and Amazon → "Online Shopping").
- Sort transactions by amount descending.

**Field notes:**
- `monthlyHistory`: Include all months for this card from spending-profile.md, including the current month.
- `average`: The historical average from spending-profile.md for this card.
- `recurring.status`: `"ok"` if present and within 10% of expected, `"missing"` if expected but absent, `"changed"` if amount differs >10%.
- `highAmount`: All transactions ≥ ₪500. For installments, add `"note": "Installment X/Y"`.
- `suspicious`: Same items flagged in Step 4's "Suspicious / Abnormal Transactions" section.
- Category names should be in English (e.g., "Restaurants & Cafes", "Food & Groceries", "Flights & Tourism").

### 7. Regenerate spending profile JSON

After updating spending-profile.md (Step 5), also regenerate `personal-info/dashboard/data/spending_profile.json` by parsing the updated spending-profile.md into structured JSON. This file powers the "Spending Profile" tab in the dashboard.

The JSON should include: `lastUpdated`, `cards`, `recurringPayments` (active + discontinued), `merchantCategories`, `monthlyTotals` (per provider key from `personal-info/cards.yaml`), `averages`, `foreignCountries`, and `largePurchases`. See the existing file for the exact schema.

**Important:** Use provider keys from `personal-info/cards.yaml` as keys in `monthlyTotals` (e.g., `max`, `cal1234`, `cal5678`).

### 8. Bundle dashboard data

After writing any JSON files, run the dashboard build script to bundle all data for offline use:

```
bash dashboard/build.sh
```

This generates `personal-info/dashboard/data.js` (gitignored) which allows the dashboard to work by simply opening `dashboard/index.html` — no local server needed.
