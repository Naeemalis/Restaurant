# NaeemSoft Restaurant

A mobile-first restaurant management system covering POS, dine-in and takeaway orders, kitchen workflow, recipes, inventory, purchasing, accounting, and reports.

## Project documentation
- [System requirements](docs/SYSTEM_REQUIREMENTS.md)
- [Database design draft](docs/DATABASE_DESIGN_DRAFT.md)

## Supported interface languages
Arabic, English, and French. Each user selects their own interface language.

## Core business rules
- Recipe ingredients are deducted from inventory when an order is sent to the kitchen.
- Weighted average cost is used for inventory valuation.
- Stock shortages generate warnings but do not automatically block sending an order.
- Repeated kitchen submission must never deduct inventory twice.
- Posted financial and stock records are reversed with an audit trail, not silently deleted.

## Project status
Requirements and logical database design are being documented. Production implementation and end-to-end testing have not yet started.

## Important
See the open decisions in the documentation before implementing database migrations or finalizing workflows.


## Initial Android implementation
The first Flutter application foundation is now in `lib/`: local SQLite initialization, first-run Admin account setup, individual PIN login, a single-stock inventory list, and a first physical-stocktake submission/review flow. The GitHub Actions workflow builds a release APK artifact after code changes.

**Status:** early development foundation only. It is not a complete restaurant POS and is not yet approved for production use. Remaining work includes role/user administration, full purchasing and receipt approval, recipe and kitchen workflows, sales/payment accounting, multilingual UI selection, secure credential hardening, migration tests, stocktake stale-snapshot protection, and end-to-end tests.
