import 'package:sqflite/sqflite.dart';

/// Additive, idempotent inventory-module migrations.
class InventorySchema {
  InventorySchema._();

  static Future<void> ensure(Database db) async {
    await db.transaction((tx) async {
      await tx.execute('''
        CREATE TABLE IF NOT EXISTS inventory_schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        )
      ''');
      final v1 = await tx.query('inventory_schema_migrations', columns:['version'], where:'version=1', limit:1);
      if (v1.isEmpty) {
        await tx.execute('''
          CREATE TABLE stock_issue_requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_no TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL CHECK(status IN ('draft','submitted','approved','partially_issued','issued','rejected','cancelled')),
            destination TEXT NOT NULL, reason TEXT NOT NULL,
            requested_by INTEGER NOT NULL, issued_by INTEGER,
            received_by_name TEXT NOT NULL DEFAULT '', requested_at TEXT NOT NULL,
            reviewed_by INTEGER, reviewed_at TEXT, review_note TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(requested_by) REFERENCES users(id),
            FOREIGN KEY(issued_by) REFERENCES users(id),
            FOREIGN KEY(reviewed_by) REFERENCES users(id)
          )
        ''');
        await tx.execute('''
          CREATE TABLE stock_issue_lines (
            id INTEGER PRIMARY KEY AUTOINCREMENT, request_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL, requested_qty REAL NOT NULL CHECK(requested_qty>0),
            issued_qty REAL NOT NULL DEFAULT 0 CHECK(issued_qty>=0), unit_snapshot TEXT NOT NULL,
            FOREIGN KEY(request_id) REFERENCES stock_issue_requests(id),
            FOREIGN KEY(product_id) REFERENCES products(id), UNIQUE(request_id,product_id)
          )
        ''');
        await tx.execute('''
          CREATE TABLE stock_return_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT, issue_line_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL, quantity REAL NOT NULL CHECK(quantity>0),
            unit_snapshot TEXT NOT NULL,
            condition_code TEXT NOT NULL CHECK(condition_code IN ('good','damaged','quarantine')),
            reason TEXT NOT NULL, returned_by_name TEXT NOT NULL, recorded_by INTEGER NOT NULL,
            movement_id INTEGER, created_at TEXT NOT NULL,
            FOREIGN KEY(issue_line_id) REFERENCES stock_issue_lines(id),
            FOREIGN KEY(product_id) REFERENCES products(id),
            FOREIGN KEY(recorded_by) REFERENCES users(id),
            FOREIGN KEY(movement_id) REFERENCES stock_movements(id)
          )
        ''');
        await tx.execute('''
          CREATE TABLE inventory_quarantine (
            id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL,
            quantity REAL NOT NULL CHECK(quantity>0), unit_snapshot TEXT NOT NULL,
            source_type TEXT NOT NULL, source_id INTEGER, reason TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('blocked','released','written_off')),
            recorded_by INTEGER NOT NULL, reviewed_by INTEGER,
            created_at TEXT NOT NULL, reviewed_at TEXT,
            FOREIGN KEY(product_id) REFERENCES products(id),
            FOREIGN KEY(recorded_by) REFERENCES users(id),
            FOREIGN KEY(reviewed_by) REFERENCES users(id)
          )
        ''');
        await tx.execute('''
          CREATE TABLE inventory_reorder_rules (
            product_id INTEGER PRIMARY KEY, minimum_qty REAL NOT NULL DEFAULT 0 CHECK(minimum_qty>=0),
            reorder_qty REAL NOT NULL DEFAULT 0 CHECK(reorder_qty>=0),
            updated_by INTEGER NOT NULL, updated_at TEXT NOT NULL,
            FOREIGN KEY(product_id) REFERENCES products(id),
            FOREIGN KEY(updated_by) REFERENCES users(id)
          )
        ''');
        await tx.execute('CREATE INDEX idx_stock_issue_status_date ON stock_issue_requests(status,requested_at)');
        await tx.execute('CREATE INDEX idx_stock_issue_lines_product ON stock_issue_lines(product_id,request_id)');
        await tx.execute('CREATE INDEX idx_inventory_quarantine_product_status ON inventory_quarantine(product_id,status)');
        await tx.insert('inventory_schema_migrations', {'version':1,'applied_at':DateTime.now().toUtc().toIso8601String()});
      }
      final v2 = await tx.query('inventory_schema_migrations', columns:['version'], where:'version=2', limit:1);
      if (v2.isEmpty) {
        await tx.execute('ALTER TABLE inventory_quarantine ADD COLUMN unit_cost_snapshot REAL NOT NULL DEFAULT 0');
        await tx.execute('ALTER TABLE waste_records ADD COLUMN unit_cost_snapshot REAL NOT NULL DEFAULT 0');
        await tx.insert('inventory_schema_migrations', {'version':2,'applied_at':DateTime.now().toUtc().toIso8601String()});
      }
      final v3 = await tx.query('inventory_schema_migrations', columns:['version'], where:'version=3', limit:1);
      if (v3.isEmpty) {
        await tx.execute("ALTER TABLE stock_issue_requests ADD COLUMN destination_type TEXT NOT NULL DEFAULT 'department' CHECK(destination_type IN ('kitchen','department'))");
        await tx.insert('inventory_schema_migrations', {'version':3,'applied_at':DateTime.now().toUtc().toIso8601String()});
      }

      final v4 = await tx.query('inventory_schema_migrations', columns:['version'], where:'version=4', limit:1);
      if (v4.isEmpty) {
        final productColumns = await tx.rawQuery('PRAGMA table_info(products)');
        if (!productColumns.any((column) => column['name'] == 'expiry_tracked')) {
          await tx.execute("ALTER TABLE products ADD COLUMN expiry_tracked INTEGER NOT NULL DEFAULT 0");
        }
        await tx.execute('''
          CREATE TABLE inventory_lots (
            id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL,
            receipt_line_id INTEGER NOT NULL, lot_code TEXT NOT NULL,
            manufacture_date TEXT, expiry_date TEXT NOT NULL,
            quantity_received REAL NOT NULL CHECK(quantity_received>0),
            quantity_remaining REAL NOT NULL CHECK(quantity_remaining>=0),
            status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','depleted','blocked')),
            created_by INTEGER NOT NULL, created_at TEXT NOT NULL,
            UNIQUE(receipt_line_id, lot_code),
            FOREIGN KEY(product_id) REFERENCES products(id),
            FOREIGN KEY(receipt_line_id) REFERENCES purchase_receipt_lines(id),
            FOREIGN KEY(created_by) REFERENCES users(id)
          )
        ''');
        await tx.execute('CREATE INDEX idx_inventory_lots_fefo ON inventory_lots(product_id,status,expiry_date,quantity_remaining)');
        await tx.execute('CREATE INDEX idx_inventory_lots_expiry ON inventory_lots(status,expiry_date)');
        await tx.insert('inventory_schema_migrations', {'version':4,'applied_at':DateTime.now().toUtc().toIso8601String()});
      }
      final v5 = await tx.query('inventory_schema_migrations', columns:['version'], where:'version=5', limit:1);
      if (v5.isEmpty) {
        await tx.execute('''
          CREATE TABLE inventory_supplier_returns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_no TEXT NOT NULL UNIQUE,
            receipt_line_id INTEGER NOT NULL,
            lot_id INTEGER,
            product_id INTEGER NOT NULL,
            supplier_id INTEGER NOT NULL,
            quantity REAL NOT NULL CHECK(quantity>0),
            unit_cost_snapshot REAL NOT NULL DEFAULT 0,
            reason TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('submitted','approved','rejected')),
            created_by INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            reviewed_by INTEGER,
            reviewed_at TEXT,
            review_note TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(receipt_line_id) REFERENCES purchase_receipt_lines(id),
            FOREIGN KEY(lot_id) REFERENCES inventory_lots(id),
            FOREIGN KEY(product_id) REFERENCES products(id),
            FOREIGN KEY(supplier_id) REFERENCES suppliers(id),
            FOREIGN KEY(created_by) REFERENCES users(id),
            FOREIGN KEY(reviewed_by) REFERENCES users(id)
          )
        ''');
        await tx.execute('CREATE INDEX idx_inventory_supplier_returns_status ON inventory_supplier_returns(status,created_at)');
        await tx.insert('inventory_schema_migrations', {'version':5,'applied_at':DateTime.now().toUtc().toIso8601String()});
      }
      final v6 = await tx.query('inventory_schema_migrations', columns:['version'], where:'version=6', limit:1);
      if (v6.isEmpty) {
        await tx.execute('''
          CREATE TABLE inventory_lot_movements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lot_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            quantity_delta REAL NOT NULL CHECK(quantity_delta<>0),
            source_ref TEXT NOT NULL,
            actor_user_id INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(lot_id) REFERENCES inventory_lots(id),
            FOREIGN KEY(product_id) REFERENCES products(id),
            FOREIGN KEY(actor_user_id) REFERENCES users(id)
          )
        ''');
        await tx.execute('CREATE INDEX idx_inventory_lot_movements_lot ON inventory_lot_movements(lot_id,created_at)');
        await tx.insert('inventory_schema_migrations', {'version':6,'applied_at':DateTime.now().toUtc().toIso8601String()});
      }

      final v7 = await tx.query('inventory_schema_migrations', columns:['version'], where:'version=7', limit:1);
      if (v7.isEmpty) {
        await tx.execute('''
          CREATE TABLE inventory_product_units (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL,
            unit_name_ar TEXT NOT NULL,
            unit_name_en TEXT NOT NULL DEFAULT '',
            unit_name_fr TEXT NOT NULL DEFAULT '',
            conversion_to_base REAL NOT NULL CHECK(conversion_to_base>0),
            is_purchase_unit INTEGER NOT NULL DEFAULT 1 CHECK(is_purchase_unit IN (0,1)),
            is_issue_unit INTEGER NOT NULL DEFAULT 1 CHECK(is_issue_unit IN (0,1)),
            is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
            created_by INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(product_id,unit_name_ar),
            FOREIGN KEY(product_id) REFERENCES products(id),
            FOREIGN KEY(created_by) REFERENCES users(id)
          )
        ''');
        await tx.execute('CREATE INDEX idx_inventory_product_units_product ON inventory_product_units(product_id,is_active)');
        await tx.insert('inventory_schema_migrations', {'version':7,'applied_at':DateTime.now().toUtc().toIso8601String()});
      }

      final v8 = await tx.query('inventory_schema_migrations', columns:['version'], where:'version=8', limit:1);
      if (v8.isEmpty) {
        final purchaseColumns = await tx.rawQuery('PRAGMA table_info(purchase_receipt_lines)');
        if (!purchaseColumns.any((column)=>column['name']=='entered_qty')) await tx.execute('ALTER TABLE purchase_receipt_lines ADD COLUMN entered_qty REAL');
        if (!purchaseColumns.any((column)=>column['name']=='entered_unit_name')) await tx.execute("ALTER TABLE purchase_receipt_lines ADD COLUMN entered_unit_name TEXT NOT NULL DEFAULT ''");
        if (!purchaseColumns.any((column)=>column['name']=='conversion_to_base_snapshot')) await tx.execute('ALTER TABLE purchase_receipt_lines ADD COLUMN conversion_to_base_snapshot REAL NOT NULL DEFAULT 1');
        final issueColumns = await tx.rawQuery('PRAGMA table_info(stock_issue_lines)');
        if (!issueColumns.any((column)=>column['name']=='entered_qty')) await tx.execute('ALTER TABLE stock_issue_lines ADD COLUMN entered_qty REAL');
        if (!issueColumns.any((column)=>column['name']=='entered_unit_name')) await tx.execute("ALTER TABLE stock_issue_lines ADD COLUMN entered_unit_name TEXT NOT NULL DEFAULT ''");
        if (!issueColumns.any((column)=>column['name']=='conversion_to_base_snapshot')) await tx.execute('ALTER TABLE stock_issue_lines ADD COLUMN conversion_to_base_snapshot REAL NOT NULL DEFAULT 1');
        await tx.insert('inventory_schema_migrations', {'version':8,'applied_at':DateTime.now().toUtc().toIso8601String()});
      }

    });
  }
}
