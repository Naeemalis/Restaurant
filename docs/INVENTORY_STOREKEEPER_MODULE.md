# Inventory Management & Storekeeper Module
## NaeemSoft Restaurant — implementation specification

Status: partially implemented on `feature/inventory-storekeeper-module`. The implementation checklist below distinguishes completed code from remaining release work; no release is approved until the latest CI build and APK artifact succeed.

## 1. Scope and operating model

- The initial restaurant deployment has one physical main-store location. Do not add warehouse selection to purchasing or cashier workflows.
- The kitchen maintains a separate custody balance and movement ledger; this is not a second purchasing warehouse. Confirmed handovers transfer stock out of the main store into kitchen custody.
- Recipe consumption, kitchen returns, and kitchen waste are posted against kitchen custody only. Never deduct the same handed-over quantity from the main store a second time.
- The module is used by the Admin and Storekeeper. Admin retains approval and all financial/cost visibility. Storekeeper sees item names, units, physical quantities, statuses, and operational documents only.
- Arabic, English, and French must be supported for screens and printable operational documents.
- All stock-changing actions must be transactional, auditable, linked to a source document, and protected against duplicate submission.
- Quantities use decimal precision and are stored in each product's base unit. Conversions must be explicit and dimension-safe.

## 2. Storekeeper work areas and tasks

### 2.1 Inventory dashboard
- Show total active stock items, available quantity status, low-stock items, out-of-stock items, pending receipts, pending issue requests, pending stocktakes, expiry alerts, and recent movements.
- Provide filters by item, category, status, date range, movement type, and acting employee.
- Do not show purchase cost, weighted-average cost, stock monetary value, supplier balances, profit, or financial reports to Storekeeper.
- Dashboard figures must be derived from the stock ledger/balance projection, not manually editable counters.

### 2.2 Item and unit reference
- View permitted item details: multilingual name, category, stock/non-stock classification, base unit, allowed purchase/issue units, conversion factors, reorder threshold, expiry tracking flag, and active status.
- Admin owns creation/editing of products, categories, units, conversions, and reorder rules unless a specific granular permission is granted.
- Never allow a conversion between incompatible dimensions (for example mass to volume) without an explicit product-specific conversion rule.
- Validate all entered quantities as finite and greater than zero for receipt, issue, waste, and return operations.

### 2.3 Receiving goods
- Select supplier and reference the supplier delivery note/purchase document.
- Record each received item, quantity, unit, converted base quantity, condition, batch/lot number when applicable, manufacture/expiry dates when applicable, receiving employee, timestamp, and notes.
- Record shortages, excess quantities, damaged goods, rejected quantities, and accepted quantities separately.
- Save a pending receipt and print/share a physical receiving note.
- Pending receipt quantities must immediately appear in physical on-hand quantity as unapproved/unvalued stock, traceable to the exact receipt line. They must not create a supplier payable, payment, financial journal, or weighted-average-cost recalculation before Admin approval.
- Admin reviews quantities and costs, then approves, partially approves, amends, or rejects with mandatory reason and audit details.
- Approval must atomically post accepted quantity, supplier payable/accounting entries, and weighted-average cost. Rejection/amendment must reconcile any quantity already consumed; never silently erase used goods.
- Receiving retries must not duplicate receipt quantities.

### 2.4 Issue and internal delivery
- Create an issue request or record a permitted issue to a defined operational destination/reason (kitchen, cleaning, staff meal, maintenance, other approved use).
- Capture item, quantity, unit, base quantity, requested-by, issued-by, received-by, destination, reason, reference, and timestamps.
- Support draft, submitted, approved, partially issued, issued, rejected, and cancelled states as applicable.
- Generate a sequential issue voucher and allow print/share.
- A posted issue creates exactly one linked negative stock movement. Duplicate taps/retries must not deduct twice.
- Record partial fulfillment and remaining quantity; do not silently mark an unfulfilled request as issued.
- Storekeeper may only approve/issue within assigned permissions and limits. Admin approval is required for configured sensitive operations.
- Kitchen recipe consumption remains separate from manual issue so ingredients are not deducted twice.

### 2.5 Kitchen and operational returns
- Record unused materials returned from kitchen/department, with item, quantity, unit, condition, source issue/order, return reason, receiver, and timestamp.
- Returned good stock increases available quantity through a linked positive movement.
- Damaged/contaminated returns are routed to waste/quarantine review and must not be treated as usable stock.
- Prevent returns exceeding the unreturned quantity of the original issue unless Admin records an explicit exception.

### 2.6 Stock movements and traceability
- Provide searchable chronological ledger with opening balance, approved receipt, pending receipt, issue, recipe consumption, direct sale, return, waste, count adjustment, supplier return, and reversal.
- Each movement stores product, location, quantity in base unit, movement type, source type/id/line, actor, timestamp, note, and idempotency key.
- Show before/after balance where available and link to the source document.
- Posted movements are immutable. Corrections require linked reversal/adjustment with reason, actor, and timestamp.
- Preserve lot/batch provenance and expiry details for traceable receipt quantities.

### 2.7 Physical stocktaking
- Start full or cycle count; freeze a system-quantity snapshot per item at count start.
- Allow count entry by item, category, or scan/manual selection; support recount and count notes.
- Show system quantity and physical quantity to authorized users. Storekeeper may submit; Admin reviews and approves variance posting.
- Do not post stock movements on draft or submission.
- On approval, post one unique adjustment movement for each non-zero variance in one transaction.
- Detect stock movements made after the snapshot. Require reconciliation/recount or an explicit Admin resolution; never apply a stale count silently.
- Preserve count sheets, variances, review decision, and audit history; print/share count report.

### 2.8 Waste, spoilage, expiry, and quarantine
- Record spoiled, damaged, contaminated, expired, or preparation waste with product, quantity, unit, reason category, explanatory note, date/time, employee, and batch/expiry reference when known.
- Reject blank reasons, zero/negative quantities, and quantities exceeding available stock unless Admin authorizes an exception.
- Saving a permitted waste record creates one linked negative waste movement immediately, with duplicate protection.
- Storekeeper cannot edit/delete a posted waste record or see its monetary valuation.
- Admin reviews waste by item, reason, employee, batch, and period; financial treatment remains Admin-only.
- Support quarantine/blocked stock so unusable goods are excluded from available-to-issue quantity pending Admin disposition.

### 2.9 Reorder and expiry alerts
- Configure minimum/reorder levels per stock item.
- Alert on below-minimum, zero balance, expiring soon, expired, pending receipt, and unresolved variance.
- Expiry alerts must use batch-level expiry dates, not only a product-level date.
- Expired or blocked stock must be excluded from normal issue selection unless an Admin-approved exception is recorded.

### 2.10 Supplier returns
- Create supplier return against original receipt/purchase line where possible.
- Capture quantity, unit, base quantity, reason, condition, batch, supplier reference, and approval state.
- Prevent returning more than the traceable available quantity from the relevant receipt/lot unless Admin resolves the exception.
- Posting creates a linked negative stock movement and, only through Admin financial approval, the appropriate supplier/accounting adjustment.
- Print/share supplier return voucher and preserve original receipt history.

### 2.11 Reports and documents
Operational reports available to Storekeeper: stock on hand by item/unit, movement ledger, receipts, issues, returns, waste, expiry alerts, reorder list, stocktake sheets, and pending tasks.
- Reports support date/item/category/employee/status filters and Arabic/English/French output.
- Print, save PDF, and share documents.
- Storekeeper reports must not expose unit cost, weighted average, monetary valuation, supplier debt, profit, or journal entries.
- Admin receives additional valuation, costing, supplier, and financial reports.

## 3. Roles and permission matrix

Permissions must be checked in the service/business layer and database access paths, not merely by hiding buttons.

| Operation | Storekeeper | Admin |
|---|---|---|
| View item names and physical quantities | Yes | Yes |
| View purchase cost / weighted average / stock value | No | Yes |
| Record pending physical receipt | If granted | Yes |
| Approve purchase receipt and supplier liability | No | Yes |
| Create/submit issue request | If granted | Yes |
| Approve sensitive issue / stock adjustment | No by default | Yes |
| Record operational return | If granted | Yes |
| Record waste with reason | If granted | Yes |
| Approve financial treatment of waste | No | Yes |
| Enter and submit stocktake | If granted | Yes |
| Approve count variance | No | Yes |
| Create supplier return | If granted | Yes |
| Approve supplier/accounting adjustment | No | Yes |
| View operational reports | Yes | Yes |
| View valuation and financial reports | No | Yes |
| Edit/delete posted movements | No | No; use audited reversal |
| Manage users, roles, and permissions | No | Yes |

Granular permissions should include at least: inventory.view, inventory.receive, inventory.issue.request, inventory.issue.post, inventory.return, inventory.waste, inventory.stocktake.create, inventory.stocktake.submit, inventory.reorder.view, inventory.expiry.view, inventory.documents.print, inventory.documents.share, inventory.adjustment.request. Admin-only permissions include inventory.receipt.approve, inventory.stocktake.approve, inventory.adjustment.approve, inventory.cost.view, inventory.valuation.view, inventory.supplier_return.approve.

## 4. Required data relationships

- products 1—many stock_balances; products 1—many stock_movements.
- stock_locations 1—many stock_balances and stock_movements; initial release enforces exactly one active location per restaurant.
- products 1—many product/unit conversion definitions; each conversion references valid units of the same dimension or an explicit product-specific conversion.
- suppliers 1—many purchase receipts; each receipt 1—many receipt lines; each line references one product and its unit/conversion.
- receipt lines 1—many lot/batch records where batch tracking is enabled; each batch retains expiry/manufacture metadata and source receipt line.
- issue requests 1—many issue lines; each posted issue line creates one stock movement and records its receiver/destination.
- issue lines 1—many return lines; cumulative returns cannot exceed issued quantity without an Admin exception.
- waste records 1—1 posted waste movement; reversal records link to the original movement.
- stocktakes 1—many stocktake lines; each approved non-zero variance line creates one adjustment movement.
- recipes 1—many recipe items; each recipe item references a stock product and required base quantity/unit. Recipe version used by an order is retained.
- orders/sales lines link to recipe version and recipe-consumption movements; each posting is idempotent.
- supplier returns reference original receipt/lot lines and create stock movements; financial supplier adjustment is a separate Admin-approved event.
- users link to all created/approved/rejected documents and movements; audit_logs retain before/after state and action details.
- all operational documents and movements include restaurant_id and source references; foreign keys and unique idempotency keys prevent orphaned or duplicate postings.

## 5. Critical cross-module rules

1. Purchase receiving, stock ledger, balance projection, lot provenance, weighted-average cost, supplier payable, and journal posting must be coordinated transactionally at the appropriate approval stage.
2. A Storekeeper pending receipt increases physical on-hand as unapproved stock; it does not increase approved/valued stock or supplier payable.
3. Recipe consumption is posted once when the sale/order is sent to kitchen. Manual kitchen issue must not duplicate recipe consumption.
4. Order edits post only quantity deltas; cancellation posts compensating movements exactly once and preserves original movements.
5. Direct-sale stock products must have a single explicit stock deduction event; no duplicate deduction at both cashier and kitchen.
6. Unit conversion is applied once at document entry and the base quantity is stored for all stock movements.
7. Posted source documents and movements are immutable; correction uses a linked reversal or adjustment.
8. Every stock write validates actor permission, active product, unit compatibility, positive finite quantity, available quantity policy, and idempotency key.
9. Balance updates and movement insertion occur in the same database transaction.
10. Database migrations must preserve existing local data and include rollback/recovery tests.

## 6. Existing implementation items to reconcile before coding

- The current purchase screen displays a message that submitting a receipt does not change stock. This conflicts with the required pending-receipt physical on-hand rule. Implement the unapproved quantity path before claiming Storekeeper receiving is complete.
- The current stock screen is a read-only balance/movement view; it is not yet the complete Storekeeper workbench described here.
- Verify current database tables, permission enforcement, and movement posting before adding new schema. Reuse existing entities where sound; do not create duplicate ledgers or duplicate receipt/issue concepts.
- Update tests for receipt idempotency, pending/approved quantities, partial receipts, returns, waste, stocktake snapshot conflicts, permission isolation, recipe consumption, order edits/cancellation, and app restart during transactions.

## 7. Acceptance criteria

The module is not complete until:
- every Storekeeper task above is reachable from the inventory module and has validation, permission checks, source document, and audit trail;
- every posted quantity change has exactly one stock movement and a consistent balance;
- pending receipt stock is physically visible but unapproved and unvalued;
- Storekeeper cannot retrieve costs or financial balances through either UI or database/service APIs;
- all three languages work in screens and generated documents;
- full and partial stocktakes, returns, waste, expiry, and supplier returns pass automated tests;
- existing restaurant sales, kitchen, purchase, and accounting workflows remain functional;
- GitHub Actions build and tests pass, and the APK artifact is verified before declaring a release ready.


## 8. Current implementation status (2026-11-15)

Implemented on the feature branch:
- Additive, idempotent SQLite migrations for issue requests/lines, returns, quarantine, reorder rules, and cost snapshots.
- Storekeeper screen linked from home navigation: stock overview, issue requests, returns, waste, quarantine, reorder settings, and stocktake submission/review.
- Role checks in the inventory service: storekeeper may submit operational records; Admin alone approves issues, resolves quarantine, and edits reorder rules.
- Partial issue fulfillment with cumulative issued quantities and safe retry protection.
- Kitchen handover is a custody transfer: it decreases the main-store on-hand and approved balances and increases the separate kitchen custody balance. Recipe consumption after handover decreases kitchen custody only; it must not deduct the main store or lot quantities a second time. Good kitchen returns reverse the custody transfer back to the main store.
- Pending receipts increase physical on-hand as unapproved stock. Approval changes approval status and weighted-average cost without increasing on-hand again; rejection reverses the pending physical quantity.
- Waste and quarantine write-off use cost snapshots and balanced Admin-visible journal entries. Storekeeper UI does not display cost or valuation.
- Automated tests cover issue/return/waste/quarantine/reorder permissions, kitchen handover double-deduction prevention, and pending receipt approval/rejection reconciliation.


- Batch tracking schema and Admin UI register lot code, manufacture/expiry dates, and split quantities against approved receipt lines; expiry alerts are shown on the inventory dashboard.
- FEFO allocation is applied to direct sales, recipe consumption, non-kitchen issues, waste, and quarantine. Expired lots are excluded from allocation; shortages of valid batches reject the stock transaction.
- Storekeeper-facing waste, quarantine, and supplier-return queries explicitly omit unit-cost snapshots; Admin queries retain them for accounting. A regression test verifies this data-layer boundary.
- For expiry-tracked products, stocktake decreases consume FEFO lots; positive stocktake variances are blocked until an approved receipt and identifiable batch/expiry are registered, preventing untraceable stock from entering saleable inventory.
- Inventory operational PDF templates use escaped database values and omit all cost/valuation fields. Print/share controls are available on issue, supplier-return, waste, and quarantine records.
- Supplier return requests are linked to approved receipt lines. Admin approval updates stock, supplier ledger, and balanced AP/Inventory journal; rejection is audited.
- Lot-level allocation movements are retained for traceability. Good returns from non-kitchen issues restore the exact original lots consumed by FEFO, in original allocation order; the service refuses the return transaction if the original lot provenance cannot be reconciled.

Still required before calling the module complete:
- Automated tests now cover multiple FEFO batches, expired-lot blocking, original-lot restoration on good department returns, partial supplier returns, duplicate approval rejection, package conversion snapshots, cost-data isolation, and kitchen double-deduction prevention. Broader failure/retry combinations and manual kitchen workflow scenarios still need validation.
- Supplier return requests linked to original approved receipt lines, Admin approval/rejection, stock deduction, supplier-ledger credit, and balanced AP/Inventory journal posting are implemented; add broader automated coverage and validate edge cases.
- A persistent Arabic/English/French user-language selector is implemented. Inventory screen controls, forms, messages, product names, and PDF headings, metadata, statuses, and stocktake variance labels use the selected language when translations exist. Other application screens still need complete localization.
- Print/share templates and UI actions now cover supplier receiving vouchers, issue vouchers, recorded issue returns, waste, quarantine, supplier returns, and stocktake. PDF headings and metadata respect the selected language; product names and free-text notes retain their entered language.
- A recent stock-movement history is now visible in the inventory overview, including receipt, issue, kitchen handover, return, quarantine, waste, supplier return, and stocktake movements; the report can also be printed or shared as a localized PDF. Final manual review on a real Android device and representative restaurant scenarios remains before release.
- Supplier receiving is now directly reachable as a dedicated tab in the Storekeeper workbench; it opens the existing receiving workflow and refreshes dashboard counts when the user returns.
- Product-specific units are configured by Admin in Arabic, English, and French, with independent purchase/issue availability and a positive conversion factor to the product base unit. Stock balances and all posted movements remain stored in the base unit.
- Supplier receiving and stock-issue requests accept package quantities, convert them to base units before posting, and preserve the entered quantity, unit name, and conversion-factor snapshot on the source document for audit and review. The supplier approval cost remains per base unit. Waste, quarantine, kitchen/department returns, and supplier returns also accept configured units and convert to the product base unit before posting. The supplier receipt approval view and receiving PDF show both the original package quantity and the converted base quantity.
- The inventory dashboard now summarizes active items, low/out-of-stock counts, pending receipts, pending issues, pending stocktakes, and expiry alerts. It supports item-name, category, and stock-status filters, plus movement filters by type, employee, and date range; movement rows include actor and source-document references. Recent movement rows also calculate and display the balance immediately before and after each movement by walking backward from the current physical balance through the movement deltas.
- The separate stock overview API intentionally omits financial valuation fields. The Storekeeper stock-screen query also omits weighted-average cost entirely rather than merely hiding it in the UI. A regression test checks the operational overview response shape.
- Latest GitHub Actions run must finish successfully and publish the release APK artifact. A passing Analyze or Test step alone is not a completed build.


## Kitchen custody workflow (2026-11-16)

The kitchen has a separate custody balance, independent from the main store balance.

- Start-of-day preparation is recorded as a kitchen-destination stock issue. Admin or the Storekeeper may submit the request; the Storekeeper can confirm kitchen handovers, while other department issues remain Admin-approved.
- Confirming a kitchen handover atomically decreases the main-store approved/on-hand balance, allocates tracked lots using FEFO, increases the kitchen custody balance, and records both main-store and kitchen-ledger movements.
- Additional deliveries during the day use separate kitchen-destination issue requests. Partial fulfillment remains supported; only the actually issued quantity moves between balances.
- Recipe consumption is deducted from kitchen custody when the cashier posts the sale. It does not deduct the main-store balance or lot quantities again; those were already moved out at handover.
- A good unused kitchen return decreases kitchen custody and restores the quantity to the main store, including original FEFO lot provenance. Damaged kitchen returns decrease kitchen custody and enter quarantine review without a second main-store deduction.
- The inventory overview shows main-store stock and kitchen custody separately.
- App database version 15 creates the kitchen custody ledger and preparation-routing fields for new installs. Existing installs are upgraded additively; the employee table is rebuilt transactionally with the same IDs and credentials to allow the dedicated kitchen role.

Automated regression coverage was updated for actual handover transfer, return reconciliation, and recipe consumption from kitchen custody. A successful Actions test/build run and APK artifact are still required before release approval.


## Kitchen manager account and replenishment requests

- The Admin can create a dedicated employee with role `kitchen` from Employee Management.
- The kitchen account opens the Kitchen screen only; it can view kitchen custody balances, kitchen tickets and its own replenishment requests.
- The kitchen manager submits additional stock requests for the kitchen only. The service rejects attempts by this role to request stock for another department.
- Requests show their requested and actually issued quantities and retain submitted, partially issued, issued or rejected status.
- The Storekeeper reviews and fulfills kitchen requests from Inventory Management. Partial fulfillment leaves the unissued balance pending for a later delivery.
- The kitchen manager can update preparation status, but cannot edit sale quantities, cancel sales, approve stock issues, access supplier balances or use storekeeper inventory administration.
- Automated coverage checks kitchen-role creation, kitchen ticket access, own-request tracking and rejection of requests targeting other departments.


## Prepared menu items and reversal rules

- Catalog products can be marked as requiring kitchen preparation. This sends the sale line to the kitchen even when no recipe is configured; ready-to-sell non-stock items such as bottled water are not routed.
- Non-stock sellable items do not require a main-store stock balance and do not create inventory consumption movements.
- Recipe ingredients are consumed from kitchen custody. Editing a kitchen ticket adjusts the kitchen balance; voiding a sale restores recipe materials to kitchen custody and restores directly sold stock items to the main store only when they were actually stock-tracked.
- Database version 15 includes a migration test that preserves existing employee records, adds the kitchen role constraint, and verifies foreign-key integrity.

- A sale linked to a kitchen ticket can be voided with automatic stock reversal only while the ticket is still `new`. Once preparation starts, cancellation is blocked so already-consumed ingredients are not incorrectly restored to kitchen custody; use the controlled refund/waste workflow instead.
