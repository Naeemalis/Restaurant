# Database Design — Draft (Not Yet Approved)

This document is a logical starting point, not a final migration. Confirm unresolved workflows and unit-conversion rules before generating production SQL.

## Design principles
- Relational database with foreign keys, unique constraints, check constraints, and transactions.
- Use immutable stock and financial ledgers; derive current balances from posted movements or maintain transactional balance projections.
- Store money as fixed-precision DECIMAL, never floating point.
- Store quantities as fixed-precision DECIMAL with an explicit base unit.
- Use UTC timestamps in storage and render them in the restaurant's configured timezone.
- Include restaurant_id on business records to permit future multi-restaurant support.
- Use soft deactivation for catalog records referenced by historical transactions.
- Record created_by, updated_by, created_at, updated_at, and audit events where applicable.

## Core identity and configuration
- restaurants(id, name, legal_name, phone, address, logo_uri, currency_code, timezone, is_active)
- restaurant_settings(id, restaurant_id, setting_key, setting_value)
- users(id, restaurant_id, username, password_hash, display_name, preferred_language, is_active)
- roles(id, restaurant_id, code, name)
- permissions(id, code, description)
- role_permissions(role_id, permission_id)
- user_roles(user_id, role_id)
- audit_logs(id, restaurant_id, actor_user_id, action, entity_type, entity_id, before_json, after_json, created_at)

## Multilingual catalog
- categories(id, restaurant_id, code, is_active)
- category_translations(category_id, language_code, name)
- products(id, restaurant_id, category_id, code, base_unit_id, product_type, is_sellable, is_stock_item, is_active)
- product_translations(product_id, language_code, name, description)
- units(id, restaurant_id, code, dimension) — examples: mass, volume, count
- unit_conversions(id, restaurant_id, from_unit_id, to_unit_id, factor)
- meals(id, restaurant_id, category_id, code, selling_price, is_active)
- meal_translations(meal_id, language_code, name, description)

## Main store and kitchen custody
- Model exactly one physical main-store stock location for the initial release; do not add warehouse selection to purchasing or cashier workflows.
- Model kitchen stock as a separate custody subledger, not as another purchasable warehouse or independent supplier location. The kitchen has its own balance and movement ledger per product.
- A confirmed kitchen handover is an internal custody transfer: decrease the main-store approved/on-hand balance and increase kitchen custody in one transaction. Record linked movements in both ledgers.
- Start-of-day handovers and additional replenishment deliveries during service use the same request/issue model. Partial fulfillment transfers only the quantity actually delivered.
- Recipe consumption after handover decreases kitchen custody only. It must never deduct the main-store balance or purchase lots a second time.
- Unused good kitchen returns decrease kitchen custody and restore the main store; damaged returns leave kitchen custody and enter quarantine. Preserve lot provenance where expiry tracking is enabled.
- Keep pending/unapproved receipt quantities distinguishable from approved quantities in the main store.


## Recipes
- recipes(id, restaurant_id, meal_id, version, is_active, effective_from, created_by)
- recipe_items(id, recipe_id, inventory_product_id, quantity, unit_id)
- A recipe item references a stock product and the quantity required for one meal.
- Recipe consumption is posted against kitchen custody, not against the main-store balance. A handover has already removed the transferred quantity from the main store.
- Recipe versions must be retained so historical orders can be costed and reversed against the recipe version used at posting time.

## Inventory
- stock_locations(id, restaurant_id, code, name, is_active) — exactly one active main-store location per restaurant in the initial release; enforce with a partial unique index.
- inventory_balances(id, restaurant_id, stock_location_id, product_id, on_hand_base_qty, approved_qty, unapproved_qty, weighted_average_cost, updated_at)
- stock_movements(id, restaurant_id, stock_location_id, product_id, movement_type, quantity_base, unit_cost, source_type, source_id, source_line_id, idempotency_key, occurred_at, created_by)
- kitchen_custody_balances(id, restaurant_id, product_id, quantity_base, weighted_average_cost, updated_at)
- kitchen_custody_movements(id, restaurant_id, product_id, quantity_delta_base, movement_type, source_type, source_id, idempotency_key, occurred_at, created_by)
- Enforce uniqueness of idempotency_key for posted source operations.
- Positive and negative stock movements are allowed; shortage warnings are calculated before kitchen posting.
- Weighted average is recalculated transactionally when purchase receipts are posted.

## Physical stocktakes
- stocktakes(id, restaurant_id, status, note, created_by, created_at, reviewed_by, reviewed_at, review_note)
- stocktake_lines(id, stocktake_id, product_id, system_qty_snapshot, counted_qty, variance_qty, movement_sequence_snapshot)
- Submitting a stocktake stores immutable quantity snapshots but does not post stock movements.
- Admin approval posts one unique count_adjustment stock movement per non-zero variance and updates the single-location balance in one transaction.
- Record movement sequence/version at count time; reject or require reconciliation if intervening movements make the snapshot stale.
- Approval/rejection and all stocktake lines remain auditable.

## Waste and spoilage records
- waste_records(id, restaurant_id, product_id, quantity, unit_id, base_quantity, reason_code, reason_note, status, source_stock_movement_id, recorded_by, recorded_at)
- Each saved waste record creates one linked negative stock_movements row with movement_type = 'waste'; enforce a unique idempotency key so retries cannot deduct stock twice.
- Waste records and stock movements are immutable after posting. Corrections use a linked reversal/adjustment record with actor, timestamp, and reason.
- Do not expose unit_cost, weighted-average cost, or monetary valuation to Storekeeper-facing queries or screens. Financial valuation and journal posting are Admin-only.
- Waste posting reduces physical available stock immediately; it does not itself alter weighted-average purchase cost or supplier balances.


## Purchasing and suppliers
- suppliers(id, restaurant_id, code, name, phone, address, is_active)
- purchase_invoices(id, restaurant_id, supplier_id, document_no, status, document_language, supplier_name_snapshot, issued_at, posted_at, total_amount, created_by)
- purchase_invoice_items(id, purchase_invoice_id, product_id, quantity, unit_id, base_quantity, unit_cost, line_total)
- supplier_payments(id, restaurant_id, supplier_id, purchase_invoice_id, amount, payment_method, paid_at, created_by)
- purchase_returns(id, restaurant_id, supplier_id, original_purchase_invoice_id, status, total_amount, created_at)
- purchase_return_items(id, purchase_return_id, product_id, quantity, unit_id, base_quantity, unit_cost, line_total)

## Orders, sales, and kitchen
- dining_tables(id, restaurant_id, table_code, display_name, is_active)
- orders(id, restaurant_id, order_no, order_type, table_id, status, created_by, created_at, sent_to_kitchen_at)
- order_items(id, order_id, line_no, meal_id, product_id, quantity, unit_price_snapshot, line_total, recipe_version_id)
- sales_invoices(id, restaurant_id, order_id, invoice_no, status, document_language, restaurant_name_snapshot, issued_at, total_amount)
- payments(id, restaurant_id, sales_invoice_id, amount, payment_method, paid_at, received_by)
- kitchen_tickets(id, restaurant_id, order_id, status, created_at, sent_at)
- kitchen_ticket_items(id, kitchen_ticket_id, order_item_id, status)
- order_status_history(id, order_id, old_status, new_status, changed_by, changed_at)

## Accounting and cash control
- cashboxes(id, restaurant_id, name, is_active)
- cash_transactions(id, restaurant_id, cashbox_id, transaction_type, amount, source_type, source_id, occurred_at, created_by)
- expenses(id, restaurant_id, expense_code, description, amount, cashbox_id, occurred_at, created_by)
- accounts(id, restaurant_id, code, name, account_type)
- journal_entries(id, restaurant_id, entry_no, source_type, source_id, status, posted_at)
- journal_entry_lines(id, journal_entry_id, account_id, debit, credit)
- Enforce balanced journal entries at posting time (total debit = total credit).

## Critical transaction rules
1. Sending an order to the kitchen, posting recipe stock movements, creating the invoice state transition, and recording the idempotency key must occur in one database transaction.
2. A unique posting key prevents duplicate stock deduction if the cashier taps send twice or a request is retried.
3. Editing a sent order creates only the delta between previously posted and newly required ingredient quantities.
4. Cancelling a sent order creates compensating stock movements; never delete the original movements.
5. Purchase receipt, stock movement, balance update, and weighted-average recalculation must commit atomically.
6. Payment records are separate from invoices; partial and multiple payments remain representable.
7. Posted financial documents are reversed or cancelled with audit history, never silently deleted.

## Decisions required before final schema
- Confirm base units and allowed conversions for each inventory product.
- Confirm any additional granular Storekeeper permissions; purchase-cost visibility is Admin-only.
- Confirm supplier payment allocation and customer credit/partial payment rules.
- Confirm tax, service charge, discounts, and rounding policy.
- Confirm return and waste workflows.
- Confirm whether inventory is decremented for direct-sale products at invoice posting or at another explicit posting event.
