# Database Design — Draft (Single-Device Android)

This is a logical starting point, not a final migration. The deployment target is one Android device running the entire restaurant application locally.

## Local database architecture
- Use SQLite as the embedded relational database on Android.
- No remote database, API server, LAN synchronization, or multi-terminal conflict resolution is required for the initial release.
- Use Android app-private storage for the live database.
- Use versioned database migrations; never replace the database file to upgrade the schema.
- Enable foreign-key enforcement and use transactions for every multi-record business operation.
- Use fixed-precision decimal handling for money and quantities. Do not use binary floating-point for financial calculations; define a safe storage/calculation strategy (for example scaled integers or validated decimal strings) before implementation.
- Keep a durable audit trail and immutable stock/financial movements.
- Include restaurant_id on business records only as a future-proofing measure; the initial app is operated for one restaurant on one device.
- Use soft deactivation for catalog records referenced by historical transactions.
- Store timestamps consistently and render them in the restaurant's configured timezone.

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
- units(id, restaurant_id, code, dimension)
- unit_conversions(id, restaurant_id, from_unit_id, to_unit_id, factor)
- meals(id, restaurant_id, category_id, code, selling_price, is_active)
- meal_translations(meal_id, language_code, name, description)

## Recipes
- recipes(id, restaurant_id, meal_id, version, is_active, effective_from, created_by)
- recipe_items(id, recipe_id, inventory_product_id, quantity, unit_id)
- Each recipe item is the ingredient quantity required for one meal.
- Preserve recipe versions so historical orders can be costed and reversed using the exact recipe version posted.

## Inventory
- warehouses(id, restaurant_id, name, is_active) — initial release may use one default stock location; confirm before final schema.
- inventory_balances(id, restaurant_id, warehouse_id, product_id, on_hand_base_qty, weighted_average_cost, updated_at)
- stock_movements(id, restaurant_id, warehouse_id, product_id, movement_type, quantity_base, unit_cost, source_type, source_id, source_line_id, idempotency_key, occurred_at, created_by)
- Enforce uniqueness of idempotency_key for posted source operations.
- Positive and negative stock movements are allowed; shortage warnings are calculated before kitchen posting.
- Recalculate weighted average transactionally when purchase receipts are posted.

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
1. Sending an order to the kitchen, posting recipe stock movements, recording idempotency keys, and transitioning the order must occur in one SQLite transaction.
2. A unique posting key prevents duplicate stock deduction if the cashier taps send twice or the app retries after interruption.
3. Editing a sent order creates only the delta between previously posted and newly required ingredient quantities.
4. Cancelling a sent order creates compensating stock movements; never delete the original movements.
5. Purchase receipt, stock movement, balance update, and weighted-average recalculation commit atomically.
6. Payment records are separate from invoices; partial and multiple payments remain representable.
7. Posted financial documents are reversed or cancelled with audit history, never silently deleted.
8. App restart or process termination must not leave a half-posted invoice or stock movement.

## Backup and restore
- Provide a user-initiated full backup of the local database and required attachments/settings.
- Export through Android's supported document/file picker to a user-selected destination.
- Validate backup integrity and schema version before restore.
- Restore must require confirmation and preserve a safety copy of current data before replacement.
- Clearly display the most recent successful backup date; do not claim data is backed up when it is not.
- Test backup/restore on a different Android device before release.

## Decisions required before final schema
- Confirm the default stock location count (one is expected for initial use).
- Confirm base units and allowed conversions for each inventory product.
- Confirm storekeeper permissions and whether purchase costs are visible.
- Confirm supplier payment allocation and customer credit/partial payment rules.
- Confirm tax, service charge, discounts, and rounding policy.
- Confirm return and waste workflows.
- Confirm whether inventory is decremented for direct-sale products at invoice posting or at another explicit posting event.
