# NaeemSoft Restaurant — System Requirements

## Project purpose and deployment
A single-device Android restaurant management application. The cashier, kitchen workflow, inventory, purchasing, accounting, and reports all run inside the same app on the same Android device. There is no requirement for multiple terminals, LAN synchronization, or a continuously connected server.

The application must be local-first and usable offline for normal daily operations. Internet may be used for optional updates or a user-initiated off-device backup, but must not be required to create orders, post invoices, or record stock movements.

## Supported languages
- Arabic
- English
- French

Each user chooses their own interface language. Product, category, and meal names support translations. Documents retain the language and restaurant identity captured when issued.

## Roles
### Admin
Full system administration: users, roles, permissions, catalog, meals, recipes, prices, purchases, sales, inventory, settings, reports, and document operations.

### Cashier
Creates and manages sales orders and invoices, selects dine-in or takeaway, reviews the order, and sends it to the kitchen. Cashier cannot change master selling prices.

### Storekeeper
May record physical receipt quantities as pending, record waste/expiry with a mandatory reason, and submit physical stocktakes for Admin review. May view item names and stock quantities only. Cannot approve purchase invoices, supplier payments, stocktake variances, financial adjustments, or view costs, weighted-average valuation, balances, profit, or financial reports.

### Financial confidentiality and role boundaries
- Purchase unit costs, weighted-average costs, profit/margin figures, supplier balances, customer balances, cashbox totals, expenses, and financial reports are Admin-only by default.
- Cashiers may create sales orders and record authorized payments, but cannot view purchase costs, profit/margins, supplier balances, or financial reports.
- Storekeepers may perform only explicitly granted inventory operations. They cannot view purchase costs or financial balances by default.
- No financial permission is implied by a role name or by access to sales/inventory screens. Any future exception must be an explicit, separately assigned permission approved by the Admin and recorded in the audit log.
- UI hiding is not sufficient: enforce these restrictions in the application service/business layer and database access paths as well.


Each employee has an individual account and signs in on the shared Android device using their own username or employee code and PIN. The Admin creates, disables, and assigns roles to employee accounts. Each account has its own role permissions and interface-language preference (Arabic, English, or French). The app must provide a clear lock/logout action and automatically return to the sign-in screen after a configurable period of inactivity. PINs must never be stored as plain text; store a securely salted password/PIN hash using an appropriate password-hashing method. Role-based screens and permissions remain enforced even though the device is shared. No internet-based authentication service is required.

## Local data and resilience
- Use an embedded relational database stored locally on the Android device.
- The app must not depend on a remote database or internet connection for core workflows.
- Database writes for invoices, payments, stock movements, and order posting must be transactional.
- Provide an explicit backup and restore workflow, with clear backup date/time and validation before restore.
- Backups should be exportable to a user-selected location or removable/cloud storage using Android-supported file access.
- Never silently overwrite the only valid backup.
- Protect access with user authentication and appropriate device/app security.
- Database schema changes must use versioned migrations and preserve existing user data.
- Define and test recovery behavior for app termination or device restart during a transaction.

## Sales and order workflow
1. Cashier selects dine-in or takeaway.
2. Cashier adds meals/products to the basket.
3. Cashier reviews the invoice before sending.
4. On send-to-kitchen, the system posts recipe ingredient consumption exactly once.
5. Kitchen tracks received, preparing, and ready states on the same device.
6. Re-sending an already posted order must not duplicate stock consumption.
7. Edits after posting apply only inventory differences. Cancellation creates reversal movements and preserves the audit trail.

## Cashier quantity entry
- Default mode: quantity.
- Support whole, half, and quarter quantities.
- Optional cash-amount mode: entered money amount divided by the current meal price determines the sold quantity.
- Example: a 500-priced item with cash amount 100 produces quantity 0.2.
- Cashier cannot override the master selling price.

## Meal recipes
Admin maintains recipes centrally. A recipe defines ingredient quantities required for one meal. The cashier selects meals only; recipe ingredients are never entered at the point of sale. The same stock item may be used by multiple recipes and may also be sold directly.

## Inventory structure
- The restaurant uses exactly **one physical stock location** for the initial release. There is no separate kitchen warehouse or second stock location.
- All received ingredients and stock items are tracked in this single inventory.
- The kitchen is an operational destination/workflow, not a separate warehouse. Sending an order to the kitchen consumes recipe quantities directly from the same stock ledger.
- Stock counts, pending/unapproved receipts, approved receipts, waste, adjustments, direct sales, and recipe consumption all affect this one stock location, with each movement classified and auditable.
- Do not add warehouse selection to cashier or purchasing workflows for this release.

## Inventory and costing
- Inventory valuation method: weighted average cost.
- Recalculate weighted average after each posted receipt.
- Preserve original purchase invoice prices.
- Allow orders even when stock is insufficient, but show ingredient-level shortage warnings.
- Record negative stock and all movements transparently; never hide shortages.
- Recipe consumption is triggered when the invoice is sent to the kitchen, not when kitchen preparation is completed.

### Storekeeper waste and expiry recording
- The Storekeeper may record spoiled, damaged, contaminated, or expired stock without receiving access to purchase costs or financial information.
- A waste record must include the stock item, quantity, unit, waste/expiry reason category, explanatory note, date/time, and acting employee. The system must reject a zero or negative quantity and a blank reason.
- Saving a waste record immediately reduces the available physical stock in the single stock location through a dedicated, auditable waste stock movement. The movement must be linked to the waste record and protected against duplicate submission.
- The Storekeeper may not edit or delete a posted waste movement, change item costs, or post financial/accounting entries. Corrections require a separate reversal/adjustment with a reason and audit record.
- The Admin can review waste records by item, quantity, reason, employee, and period, and retains exclusive access to any monetary valuation or financial impact.
- Waste recording must not silently change weighted-average purchase cost or supplier balances. Any accounting treatment of waste is handled only by the Admin through the financial workflow.


### Cashier invoice cancellation
- Cashiers may cancel their sales invoices, including orders already sent to the kitchen, but cancellation requires a non-empty reason.
- The system records the employee account, timestamp, invoice/order reference, cancellation reason, and the invoice state at the time of cancellation. The original invoice and all prior events remain in the audit history; they are never physically deleted.
- If the order has not been sent to the kitchen, cancellation closes the order without posting recipe consumption.
- If the order has already been sent to the kitchen, cancellation must create compensating stock movements for the exact quantities previously deducted, exactly once, and notify/update the kitchen ticket as cancelled. The original stock movements remain preserved.
- Cancellation must be atomic and protected against duplicate taps/retries so stock is never restored twice.
- A cashier cancellation does not authorize cash refunds, payment reversals, cashbox adjustments, or access to financial reports. Any refund or reversal of a posted payment requires Admin authorization and its own audit record.
- The Admin can review all cancellations, reasons, employee identities, and related stock/payment events.

### Sales discounts and accountability
- Cashiers are allowed to apply discounts to a sales invoice.
- A discount cannot be saved or posted unless the cashier enters a non-empty explanatory note/reason.
- Every discount must record the acting employee account, timestamp, invoice reference, discount type (fixed amount or percentage), discount value, pre-discount total, and final total.
- Discount details and notes must remain visible in the invoice audit/history and be available to the Admin in reports.
- Cashiers cannot edit or erase a posted discount history. Corrections must use an auditable adjustment or invoice reversal workflow.
- Purchase costs, margins, profits, supplier balances, and other restricted financial information remain Admin-only; permission to discount does not grant access to those data.


### Storekeeper receiving boundary
- The Storekeeper may record the physical receipt of goods against a purchase/delivery document as a **pending receipt record**: items, quantities, units, observed condition, supplier/delivery reference, date/time, and receiving employee.
- Immediately after the Storekeeper saves the physical receipt, the received quantities become visible in physical on-hand stock and are available for sale/use, but remain clearly classified as **unapproved receipt stock** until Admin approval.
- Unapproved receipt stock must be tracked separately from approved/valued stock. It must not create a supplier payable, payment, purchase-cost entry, weighted-average-cost recalculation, or accounting journal before Admin approval.
- The system must preserve stock provenance by linking every quantity from an unapproved receipt to its pending receipt record. Sales/consumption from this stock must be traceable even if the receipt is later rejected or amended; the system must never silently remove already-used quantities.
- Purchase unit prices, total purchase value, weighted-average cost, supplier balances, and financial posting remain Admin-only.
- Only the Admin may review and approve/post the purchase receipt financially. Approval validates the quantities and financial details, converts the accepted receipt quantities to approved/valued stock, updates weighted-average cost, and posts the corresponding supplier/accounting entries atomically. Quantities already sold or consumed remain recorded and are included in the stock reconciliation.
- If the Admin rejects or amends a pending receipt, the system records the decision, reason, actor, and timestamp. Any discrepancy or already-used quantity must be resolved through an explicit adjustment/exception workflow; do not erase stock movements or create an unexplained negative balance.
- The Storekeeper cannot edit approved financial values, approve their own pending receipt, record supplier payments, or access purchase-cost and balance data.
- Pending, approved, rejected, and amended receipt events must be auditable. Corrections after approval use a controlled reversal/adjustment workflow; do not overwrite or delete the original record.

### Physical stocktake and variance approval
- The Storekeeper and Admin may initiate a physical count. The Storekeeper records the actual counted quantity for each selected item and may add a note.
- On submission, the system snapshots the system quantity, actual quantity, and variance for each counted item and marks the stocktake as pending Admin review.
- Submitting a count does not change on-hand stock, stock valuation, supplier balances, or financial ledgers.
- Only the Admin may approve or reject/return a submitted stocktake. Approval posts a separate, uniquely keyed stock adjustment movement for each non-zero variance and updates the single stock location atomically.
- The system records the counter, reviewer, timestamps, decision, notes, original quantities, and resulting movements in the audit history. Submitted or approved counts cannot be silently overwritten or deleted.
- A stocktake must detect stale counts: if relevant stock movements occurred after the count snapshot, the Admin must be warned and the variance must be reconciled before approval rather than blindly overwriting current stock.
- The Storekeeper cannot view purchase costs, weighted-average cost, or monetary valuation through stocktake screens or reports.

## Financial and audit integrity
- Posted invoices and financial records must not be physically erased.
- Use cancellation/reversal transactions and audit logs.
- Prevent duplicate stock posting with database-level idempotency safeguards.
- Keep historical document snapshots (document number, issue time, language, restaurant identity, and line prices).

## Main modules
1. POS and sales invoices
2. Dine-in tables and takeaway
3. Kitchen tickets and statuses
4. Meal and recipe management
5. Inventory and stock movements
6. Purchasing and suppliers
7. Cashbox, payments, expenses, and accounting
8. Reports
9. Users, roles, and permissions
10. Restaurant settings and translations
11. Local backup and restore

## Open decisions
The following are not yet approved and must be confirmed before implementation:
- Additional granular storekeeper permissions beyond receiving, waste/expiry records, and submitting stocktakes.
- Product grid layout and number of columns.
- Purchase receiving, supplier payment, and return workflows.
- Stock units and conversion rules (kg/g, litre/ml, piece, bottle, etc.).
- Return handling and any additional waste approval thresholds (basic Storekeeper waste recording is defined above).
- Customer credit and partial payment rules.
- Cashier shifts and cashbox closing.
- Invoice print/share formats and paper sizes.
- Whether kitchen tickets can be split or partially prepared.
- Android minimum supported version and device storage constraints.

## Implementation principle
Do not represent prototypes or incomplete screens as a finished system. Each module must be connected to persistent local data and tested through end-to-end scenarios before being marked complete.
