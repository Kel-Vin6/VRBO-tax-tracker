# VRBO tax tracker

A short-term rental tax tracker for iPhone, iPad, Mac and Vision Pro, built
around IRS Schedule E rather than bolted onto a general ledger. Every figure a
host records has a numbered line on the form it belongs to, and the rules that
decide whether it can actually be claimed are checked all year rather than in
April.

Written in SwiftUI with SwiftData, `@Observable`, Swift Charts and the
`Tab`/`sidebarAdaptable` navigation API, from one target.

## What it does

**The return**

- Generates Schedule E (Form 1040) Part I, one column per property, with the
  detail behind every line one tap away.
- Applies §280A: fair rental days, personal-use days, the greater-of-14-days-or-
  10% limit, expense allocation and the income cap, with both the IRS and the
  Tax Court (Bolton) allocation methods.
- Runs MACRS depreciation from first principles — mid-month straight line for
  buildings over 27.5 or 39 years, declining balance with an automatic
  straight-line switch and the half-year convention for contents, plus §179 and
  bonus depreciation. Reproduces the Pub. 946 percentages exactly.
- Detects when the mid-quarter convention would apply and says so rather than
  producing a quiet, wrong figure.
- Amortises mortgages so line 12 is known without waiting for a Form 1098.
- Estimates federal tax, the net investment income tax, state tax and the
  quarterly safe harbor, and tracks instalments against it.

**The decisions that cost real money**

- **Personal-use radar** — how many owner nights are left before the property
  becomes a residence and the loss disappears, with a what-if slider.
- **Material participation** — average period of customer use against the
  seven-day exception, plus the §469 tests, deciding whether a loss is passive.
- **Repair or improvement** — walks the de minimis, routine maintenance and
  small taxpayer safe harbors before the betterment/adaptation/restoration test,
  and prices the timing difference.
- **1099-K reconciliation** — rebuilds what each platform should have reported
  and explains the gap, which is usually the host service fee nobody deducted.
- **Sale estimator** — unrecaptured §1250 gain, capital gain and the cash that
  actually reaches you.
- **Scenario lab** — the after-tax cost of a purchase, extra nights, a rate rise
  or a week of your own, modelled against your real figures.
- **Audit readiness score** — what an examiner asks for first, what is missing,
  and how much deduction is at risk.

**Capture**

- Receipt scanning with the system document camera and on-device OCR (Vision)
  that fills in the amount, date and merchant. Nothing is uploaded.
- CSV import for Airbnb and Vrbo payout exports and bank statements, with
  auto-detected column mapping, a preview and duplicate detection.
- Mileage log with the statutory rate by year, tolls, and a completeness check
  against what the IRS actually requires.
- A participation timer whose start time survives a restart.
- Recurring bills, a document vault with renewal reminders, and a full export
  package: CSV ledgers, a printable PDF summary and the receipt images.

## Project layout

```
VRBO tax tracker/
  App/          Entry point, root navigation, app state, lock screen
  Models/       SwiftData models and the domain vocabulary
  Engines/      Pure calculation: Schedule E, MACRS, §280A, §469, estimator,
                amortisation, analytics, audit scoring, scenarios
  Services/     Persistence, settings, OCR, notifications, app lock, CSV,
                PDF rendering, recurring bills
  Support/      Decimal and calendar-day helpers, formatting
  Views/        One folder per area of the app
```

The engines hold no UI and no SwiftData dependencies beyond the models, so the
tax logic can be reasoned about — and tested — on its own.

## Before you ship

Two things need doing in Xcode that cannot be set from source:

1. **iCloud sync.** The Settings toggle is wired and the schema is
   CloudKit-compatible (optional relationships, defaults on every property), but
   the target needs the iCloud capability with CloudKit enabled and a container
   selected. Without it the app falls back to a local store and tells the user
   why, rather than failing silently.
2. **App icon.** `Assets.xcassets/AppIcon.appiconset` is still empty.

Usage descriptions for the camera, Face ID and the photo library are already set
in the build settings.

## A note on the numbers

The app produces estimates to help a host plan and to hand their accountant a
complete, documented file. It is not tax advice and it does not file anything.
Rate tables ship with published figures through 2025; any later year carries the
most recent table forward and is flagged in the interface as unconfirmed, with
every rate editable in Settings.
