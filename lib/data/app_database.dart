import 'dart:convert';
import 'inventory_service.dart';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _db;

  Future<void> closeForTesting() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(p.join(dir, 'naeemsoft_restaurant.db'), version: 15, onConfigure: (db) async { await db.execute('PRAGMA foreign_keys = OFF'); }, onOpen: (db) async { await db.execute('PRAGMA foreign_keys = ON'); }, onCreate: (db, version) async {
      await db.execute("CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('admin','cashier','storekeeper','kitchen')), pin_salt TEXT NOT NULL, pin_hash TEXT NOT NULL, must_change_pin INTEGER NOT NULL DEFAULT 0, preferred_language TEXT NOT NULL DEFAULT 'ar', is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)");
      await db.execute("CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE, is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)");
      await db.execute("CREATE TABLE category_translations(id INTEGER PRIMARY KEY AUTOINCREMENT, category_id INTEGER NOT NULL, language_code TEXT NOT NULL CHECK(language_code IN ('ar','en','fr')), name TEXT NOT NULL, UNIQUE(category_id, language_code), FOREIGN KEY(category_id) REFERENCES categories(id))");
      await db.execute("CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name_ar TEXT NOT NULL, base_unit TEXT NOT NULL, sale_price REAL NOT NULL DEFAULT 0, category_id INTEGER, code TEXT UNIQUE, product_type TEXT NOT NULL DEFAULT 'ingredient' CHECK(product_type IN ('ingredient','sellable','both')), is_sellable INTEGER NOT NULL DEFAULT 0, is_stock_item INTEGER NOT NULL DEFAULT 1, expiry_tracked INTEGER NOT NULL DEFAULT 0, preparation_required INTEGER NOT NULL DEFAULT 0 CHECK(preparation_required IN (0,1)), is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, FOREIGN KEY(category_id) REFERENCES categories(id))");
      await db.execute("CREATE TABLE product_translations(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, language_code TEXT NOT NULL CHECK(language_code IN ('ar','en','fr')), name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', UNIQUE(product_id, language_code), FOREIGN KEY(product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE stock_balances(product_id INTEGER PRIMARY KEY, on_hand REAL NOT NULL DEFAULT 0, approved_qty REAL NOT NULL DEFAULT 0, unapproved_qty REAL NOT NULL DEFAULT 0, weighted_average_cost REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, FOREIGN KEY(product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE stock_movements(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, movement_type TEXT NOT NULL, quantity_delta REAL NOT NULL, source_type TEXT NOT NULL, source_id INTEGER, idempotency_key TEXT NOT NULL UNIQUE, actor_user_id INTEGER, note TEXT, occurred_at TEXT NOT NULL)");
      await db.execute("CREATE TABLE kitchen_stock_balances(product_id INTEGER PRIMARY KEY, quantity REAL NOT NULL DEFAULT 0 CHECK(quantity>=0), weighted_average_cost REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, FOREIGN KEY(product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE kitchen_stock_movements(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, quantity_delta REAL NOT NULL CHECK(quantity_delta<>0), movement_type TEXT NOT NULL, source_type TEXT NOT NULL, source_id INTEGER, idempotency_key TEXT NOT NULL UNIQUE, actor_user_id INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, FOREIGN KEY(product_id) REFERENCES products(id), FOREIGN KEY(actor_user_id) REFERENCES users(id))");
      await db.execute("CREATE TABLE stocktakes(id INTEGER PRIMARY KEY AUTOINCREMENT, status TEXT NOT NULL CHECK(status IN ('draft','submitted','approved','rejected')), note TEXT, created_by INTEGER NOT NULL, created_at TEXT NOT NULL, reviewed_by INTEGER, reviewed_at TEXT, review_note TEXT)");
      await db.execute("CREATE TABLE stocktake_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, stocktake_id INTEGER NOT NULL, product_id INTEGER NOT NULL, system_qty REAL NOT NULL, counted_qty REAL NOT NULL, difference_qty REAL NOT NULL, movement_sequence_snapshot INTEGER NOT NULL DEFAULT 0, FOREIGN KEY(stocktake_id) REFERENCES stocktakes(id), FOREIGN KEY(product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE waste_records(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, quantity REAL NOT NULL CHECK(quantity > 0), reason_code TEXT NOT NULL, reason_note TEXT NOT NULL, recorded_by INTEGER NOT NULL, recorded_at TEXT NOT NULL, movement_id INTEGER NOT NULL)");
      await db.execute("CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, address TEXT, notes TEXT NOT NULL DEFAULT '', is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)");
      await db.execute("CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT NOT NULL UNIQUE, customer_id INTEGER, cashier_user_id INTEGER NOT NULL, subtotal REAL NOT NULL, discount REAL NOT NULL DEFAULT 0, total REAL NOT NULL, paid REAL NOT NULL DEFAULT 0, balance REAL NOT NULL DEFAULT 0, status TEXT NOT NULL CHECK(status IN ('posted','voided')), created_at TEXT NOT NULL, FOREIGN KEY(customer_id) REFERENCES customers(id), FOREIGN KEY(cashier_user_id) REFERENCES users(id))");
      await db.execute("CREATE TABLE sale_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER NOT NULL, product_name_snapshot TEXT NOT NULL, unit_snapshot TEXT NOT NULL, quantity REAL NOT NULL, unit_price REAL NOT NULL, line_total REAL NOT NULL, cost_total REAL NOT NULL DEFAULT 0, FOREIGN KEY(sale_id) REFERENCES sales(id), FOREIGN KEY(product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE customer_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, customer_id INTEGER NOT NULL, sale_id INTEGER, amount REAL NOT NULL CHECK(amount>0), payment_type TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', received_by INTEGER NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(customer_id) REFERENCES customers(id), FOREIGN KEY(sale_id) REFERENCES sales(id))");
      await db.execute("CREATE TABLE suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, address TEXT, notes TEXT NOT NULL DEFAULT '', is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)");
      await db.execute("CREATE TABLE purchase_receipts(id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT NOT NULL, supplier_id INTEGER NOT NULL, status TEXT NOT NULL CHECK(status IN ('submitted','approved','rejected')), created_by INTEGER NOT NULL, created_at TEXT NOT NULL, reviewed_by INTEGER, reviewed_at TEXT, review_note TEXT NOT NULL DEFAULT '', total_cost REAL NOT NULL DEFAULT 0, FOREIGN KEY(supplier_id) REFERENCES suppliers(id))");
      await db.execute("CREATE TABLE purchase_receipt_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, receipt_id INTEGER NOT NULL, product_id INTEGER NOT NULL, received_qty REAL NOT NULL CHECK(received_qty>0), unit_cost REAL NOT NULL DEFAULT 0, line_total REAL NOT NULL DEFAULT 0, FOREIGN KEY(receipt_id) REFERENCES purchase_receipts(id), FOREIGN KEY(product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE supplier_ledger(id INTEGER PRIMARY KEY AUTOINCREMENT, supplier_id INTEGER NOT NULL, receipt_id INTEGER, entry_type TEXT NOT NULL, debit REAL NOT NULL DEFAULT 0, credit REAL NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', actor_user_id INTEGER NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(supplier_id) REFERENCES suppliers(id), FOREIGN KEY(receipt_id) REFERENCES purchase_receipts(id))");
      await db.execute("CREATE TABLE recipes(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL UNIQUE, version INTEGER NOT NULL DEFAULT 1, is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE recipe_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, recipe_id INTEGER NOT NULL, ingredient_product_id INTEGER NOT NULL, quantity_per_meal REAL NOT NULL CHECK(quantity_per_meal>0), unit_snapshot TEXT NOT NULL, FOREIGN KEY(recipe_id) REFERENCES recipes(id), FOREIGN KEY(ingredient_product_id) REFERENCES products(id), UNIQUE(recipe_id,ingredient_product_id))");
      await db.execute("CREATE TABLE sale_recipe_components(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_line_id INTEGER NOT NULL, ingredient_product_id INTEGER NOT NULL, ingredient_name_snapshot TEXT NOT NULL, unit_snapshot TEXT NOT NULL, quantity REAL NOT NULL CHECK(quantity>0), recipe_version INTEGER NOT NULL, unit_cost_snapshot REAL NOT NULL DEFAULT 0, FOREIGN KEY(sale_line_id) REFERENCES sale_lines(id), FOREIGN KEY(ingredient_product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE kitchen_orders(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL UNIQUE, status TEXT NOT NULL CHECK(status IN ('new','preparing','ready','cancelled')), created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(sale_id) REFERENCES sales(id))");
      await db.execute("CREATE TABLE kitchen_order_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, kitchen_order_id INTEGER NOT NULL, sale_line_id INTEGER NOT NULL, FOREIGN KEY(kitchen_order_id) REFERENCES kitchen_orders(id), FOREIGN KEY(sale_line_id) REFERENCES sale_lines(id), UNIQUE(kitchen_order_id,sale_line_id))");
      await db.execute("CREATE TABLE sale_refunds(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL UNIQUE, amount REAL NOT NULL CHECK(amount>0), reason TEXT NOT NULL, approved_by INTEGER NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(sale_id) REFERENCES sales(id), FOREIGN KEY(approved_by) REFERENCES users(id))");
      await db.execute("CREATE TABLE cash_transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, direction TEXT NOT NULL CHECK(direction IN ('in','out')), category TEXT NOT NULL, amount REAL NOT NULL CHECK(amount>0), payment_method TEXT NOT NULL DEFAULT 'cash', source_type TEXT NOT NULL, source_id INTEGER, idempotency_key TEXT NOT NULL UNIQUE, note TEXT NOT NULL DEFAULT '', actor_user_id INTEGER NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(actor_user_id) REFERENCES users(id))");
      await db.execute("CREATE TABLE accounts(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL UNIQUE, name_ar TEXT NOT NULL, account_type TEXT NOT NULL CHECK(account_type IN ('asset','liability','equity','revenue','expense')), is_active INTEGER NOT NULL DEFAULT 1)");
      await db.execute("CREATE TABLE journal_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, entry_no TEXT NOT NULL UNIQUE, source_type TEXT NOT NULL, source_id INTEGER NOT NULL, description TEXT NOT NULL, actor_user_id INTEGER NOT NULL, created_at TEXT NOT NULL, UNIQUE(source_type,source_id), FOREIGN KEY(actor_user_id) REFERENCES users(id))");
      await db.execute("CREATE TABLE journal_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, entry_id INTEGER NOT NULL, account_id INTEGER NOT NULL, debit REAL NOT NULL DEFAULT 0 CHECK(debit>=0), credit REAL NOT NULL DEFAULT 0 CHECK(credit>=0), CHECK(NOT(debit>0 AND credit>0)), FOREIGN KEY(entry_id) REFERENCES journal_entries(id), FOREIGN KEY(account_id) REFERENCES accounts(id))");
      await db.execute("INSERT INTO accounts(code,name_ar,account_type) VALUES ('CASH','الصندوق','asset'),('AR','ذمم الزبائن','asset'),('INVENTORY','المخزون','asset'),('AP','ذمم الموردين','liability'),('SALES','إيرادات المبيعات','revenue'),('EXPENSE','المصروفات التشغيلية','expense'),('SALES_RETURNS','مرتجعات المبيعات','revenue'),('CAPITAL','رأس المال','equity'),('COGS','تكلفة البضاعة المباعة','expense')");
      await db.execute("CREATE TABLE audit_logs(id INTEGER PRIMARY KEY AUTOINCREMENT, actor_user_id INTEGER, action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id INTEGER, details TEXT NOT NULL, created_at TEXT NOT NULL)");
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute('ALTER TABLE stocktake_lines ADD COLUMN movement_sequence_snapshot INTEGER NOT NULL DEFAULT 0');
      }
      if (oldVersion < 3) {
        await db.execute("CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE, is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)");
        await db.execute("CREATE TABLE category_translations(id INTEGER PRIMARY KEY AUTOINCREMENT, category_id INTEGER NOT NULL, language_code TEXT NOT NULL CHECK(language_code IN ('ar','en','fr')), name TEXT NOT NULL, UNIQUE(category_id, language_code), FOREIGN KEY(category_id) REFERENCES categories(id))");
        await db.execute("ALTER TABLE products ADD COLUMN category_id INTEGER REFERENCES categories(id)");
        await db.execute("ALTER TABLE products ADD COLUMN code TEXT");
        await db.execute("ALTER TABLE products ADD COLUMN product_type TEXT NOT NULL DEFAULT 'ingredient' CHECK(product_type IN ('ingredient','sellable','both'))");
        await db.execute("ALTER TABLE products ADD COLUMN is_sellable INTEGER NOT NULL DEFAULT 0");
        await db.execute("ALTER TABLE products ADD COLUMN is_stock_item INTEGER NOT NULL DEFAULT 1");
        await db.execute("CREATE UNIQUE INDEX idx_products_code_unique ON products(code) WHERE code IS NOT NULL AND code <> ''");
        await db.execute("CREATE TABLE product_translations(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, language_code TEXT NOT NULL CHECK(language_code IN ('ar','en','fr')), name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', UNIQUE(product_id, language_code), FOREIGN KEY(product_id) REFERENCES products(id))");
        await db.execute("INSERT INTO product_translations(product_id, language_code, name) SELECT id, 'ar', name_ar FROM products");
      }
      if (oldVersion < 5) {
        await db.execute("ALTER TABLE products ADD COLUMN sale_price REAL NOT NULL DEFAULT 0");
        await db.execute("CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, address TEXT, notes TEXT NOT NULL DEFAULT '', is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)");
        await db.execute("CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT NOT NULL UNIQUE, customer_id INTEGER, cashier_user_id INTEGER NOT NULL, subtotal REAL NOT NULL, discount REAL NOT NULL DEFAULT 0, total REAL NOT NULL, paid REAL NOT NULL DEFAULT 0, balance REAL NOT NULL DEFAULT 0, status TEXT NOT NULL CHECK(status IN ('posted','voided')), created_at TEXT NOT NULL, FOREIGN KEY(customer_id) REFERENCES customers(id), FOREIGN KEY(cashier_user_id) REFERENCES users(id))");
        await db.execute("CREATE TABLE sale_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER NOT NULL, product_name_snapshot TEXT NOT NULL, unit_snapshot TEXT NOT NULL, quantity REAL NOT NULL, unit_price REAL NOT NULL, line_total REAL NOT NULL, FOREIGN KEY(sale_id) REFERENCES sales(id), FOREIGN KEY(product_id) REFERENCES products(id))");
        await db.execute("CREATE TABLE customer_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, customer_id INTEGER NOT NULL, sale_id INTEGER, amount REAL NOT NULL CHECK(amount>0), payment_type TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', received_by INTEGER NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(customer_id) REFERENCES customers(id), FOREIGN KEY(sale_id) REFERENCES sales(id))");
      }

      if (oldVersion < 8) {
      await db.execute("CREATE TABLE sale_refunds(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL UNIQUE, amount REAL NOT NULL CHECK(amount>0), reason TEXT NOT NULL, approved_by INTEGER NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(sale_id) REFERENCES sales(id), FOREIGN KEY(approved_by) REFERENCES users(id))");
      }
      if (oldVersion < 7) {
      await db.execute("CREATE TABLE recipes(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL UNIQUE, version INTEGER NOT NULL DEFAULT 1, is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE recipe_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, recipe_id INTEGER NOT NULL, ingredient_product_id INTEGER NOT NULL, quantity_per_meal REAL NOT NULL CHECK(quantity_per_meal>0), unit_snapshot TEXT NOT NULL, FOREIGN KEY(recipe_id) REFERENCES recipes(id), FOREIGN KEY(ingredient_product_id) REFERENCES products(id), UNIQUE(recipe_id,ingredient_product_id))");
      await db.execute("CREATE TABLE sale_recipe_components(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_line_id INTEGER NOT NULL, ingredient_product_id INTEGER NOT NULL, ingredient_name_snapshot TEXT NOT NULL, unit_snapshot TEXT NOT NULL, quantity REAL NOT NULL CHECK(quantity>0), recipe_version INTEGER NOT NULL, FOREIGN KEY(sale_line_id) REFERENCES sale_lines(id), FOREIGN KEY(ingredient_product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE kitchen_orders(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL UNIQUE, status TEXT NOT NULL CHECK(status IN ('new','preparing','ready','cancelled')), created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(sale_id) REFERENCES sales(id))");
      await db.execute("CREATE TABLE kitchen_order_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, kitchen_order_id INTEGER NOT NULL, sale_line_id INTEGER NOT NULL, FOREIGN KEY(kitchen_order_id) REFERENCES kitchen_orders(id), FOREIGN KEY(sale_line_id) REFERENCES sale_lines(id), UNIQUE(kitchen_order_id,sale_line_id))");
      }
      if (oldVersion < 6) {
        await db.execute("ALTER TABLE stock_balances ADD COLUMN weighted_average_cost REAL NOT NULL DEFAULT 0");
              await db.execute("CREATE TABLE purchase_receipts(id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT NOT NULL, supplier_id INTEGER NOT NULL, status TEXT NOT NULL CHECK(status IN ('submitted','approved','rejected')), created_by INTEGER NOT NULL, created_at TEXT NOT NULL, reviewed_by INTEGER, reviewed_at TEXT, review_note TEXT NOT NULL DEFAULT '', total_cost REAL NOT NULL DEFAULT 0, FOREIGN KEY(supplier_id) REFERENCES suppliers(id))");
      await db.execute("CREATE TABLE purchase_receipt_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, receipt_id INTEGER NOT NULL, product_id INTEGER NOT NULL, received_qty REAL NOT NULL CHECK(received_qty>0), unit_cost REAL NOT NULL DEFAULT 0, line_total REAL NOT NULL DEFAULT 0, FOREIGN KEY(receipt_id) REFERENCES purchase_receipts(id), FOREIGN KEY(product_id) REFERENCES products(id))");
      await db.execute("CREATE TABLE supplier_ledger(id INTEGER PRIMARY KEY AUTOINCREMENT, supplier_id INTEGER NOT NULL, receipt_id INTEGER, entry_type TEXT NOT NULL, debit REAL NOT NULL DEFAULT 0, credit REAL NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', actor_user_id INTEGER NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(supplier_id) REFERENCES suppliers(id), FOREIGN KEY(receipt_id) REFERENCES purchase_receipts(id))");
      }
      if (oldVersion < 4) {
        await db.execute("CREATE TABLE suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, address TEXT, notes TEXT NOT NULL DEFAULT '', is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)");
      }
      if (oldVersion < 9) {
        await db.execute("CREATE TABLE cash_transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, direction TEXT NOT NULL CHECK(direction IN ('in','out')), category TEXT NOT NULL, amount REAL NOT NULL CHECK(amount>0), payment_method TEXT NOT NULL DEFAULT 'cash', source_type TEXT NOT NULL, source_id INTEGER, idempotency_key TEXT NOT NULL UNIQUE, note TEXT NOT NULL DEFAULT '', actor_user_id INTEGER NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(actor_user_id) REFERENCES users(id))");
        await db.execute("CREATE INDEX idx_cash_transactions_created ON cash_transactions(created_at, id)");
        await db.execute("INSERT INTO cash_transactions(direction,category,amount,payment_method,source_type,source_id,idempotency_key,note,actor_user_id,created_at) SELECT 'in','sale',paid,'cash','sale',id,'cash:legacy-sale:'||id,'Opening migration: cash sale',cashier_user_id,created_at FROM sales WHERE customer_id IS NULL AND paid>0 AND status IN ('posted','voided')");
        await db.execute("INSERT INTO cash_transactions(direction,category,amount,payment_method,source_type,source_id,idempotency_key,note,actor_user_id,created_at) SELECT 'in','customer_payment',amount,'cash','customer_payment',customer_id,'cash:legacy-customer-payment:'||id,note,received_by,created_at FROM customer_payments");
        await db.execute("INSERT INTO cash_transactions(direction,category,amount,payment_method,source_type,source_id,idempotency_key,note,actor_user_id,created_at) SELECT 'out','sale_refund',amount,'cash','sale_refund',sale_id,'cash:legacy-sale-refund:'||sale_id,reason,approved_by,created_at FROM sale_refunds");
        await db.execute("INSERT INTO cash_transactions(direction,category,amount,payment_method,source_type,source_id,idempotency_key,note,actor_user_id,created_at) SELECT 'out','supplier_payment',credit,'cash','supplier_payment',id,'cash:legacy-supplier-payment:'||id,note,actor_user_id,created_at FROM supplier_ledger WHERE entry_type='payment' AND credit>0");
      }
      if (oldVersion < 10) {
        await db.execute("CREATE TABLE accounts(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL UNIQUE, name_ar TEXT NOT NULL, account_type TEXT NOT NULL CHECK(account_type IN ('asset','liability','equity','revenue','expense')), is_active INTEGER NOT NULL DEFAULT 1)");
        await db.execute("CREATE TABLE journal_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, entry_no TEXT NOT NULL UNIQUE, source_type TEXT NOT NULL, source_id INTEGER NOT NULL, description TEXT NOT NULL, actor_user_id INTEGER NOT NULL, created_at TEXT NOT NULL, UNIQUE(source_type,source_id), FOREIGN KEY(actor_user_id) REFERENCES users(id))");
        await db.execute("CREATE TABLE journal_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, entry_id INTEGER NOT NULL, account_id INTEGER NOT NULL, debit REAL NOT NULL DEFAULT 0 CHECK(debit>=0), credit REAL NOT NULL DEFAULT 0 CHECK(credit>=0), CHECK(NOT(debit>0 AND credit>0)), FOREIGN KEY(entry_id) REFERENCES journal_entries(id), FOREIGN KEY(account_id) REFERENCES accounts(id))");
        await db.execute("INSERT INTO accounts(code,name_ar,account_type) VALUES ('CASH','الصندوق','asset'),('AR','ذمم الزبائن','asset'),('INVENTORY','المخزون','asset'),('AP','ذمم الموردين','liability'),('SALES','إيرادات المبيعات','revenue'),('EXPENSE','المصروفات التشغيلية','expense'),('SALES_RETURNS','مرتجعات المبيعات','revenue')");
      }
      if (oldVersion < 11) {
        await db.execute("INSERT INTO accounts(code,name_ar,account_type) VALUES ('CAPITAL','رأس المال','equity')");
      }
      if (oldVersion < 13) {
        await db.execute('ALTER TABLE users ADD COLUMN must_change_pin INTEGER NOT NULL DEFAULT 0');
      }
      if (oldVersion < 14) {
        await db.execute("CREATE TABLE kitchen_stock_balances(product_id INTEGER PRIMARY KEY, quantity REAL NOT NULL DEFAULT 0 CHECK(quantity>=0), weighted_average_cost REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, FOREIGN KEY(product_id) REFERENCES products(id))");
        await db.execute("CREATE TABLE kitchen_stock_movements(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, quantity_delta REAL NOT NULL CHECK(quantity_delta<>0), movement_type TEXT NOT NULL, source_type TEXT NOT NULL, source_id INTEGER, idempotency_key TEXT NOT NULL UNIQUE, actor_user_id INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, FOREIGN KEY(product_id) REFERENCES products(id), FOREIGN KEY(actor_user_id) REFERENCES users(id))");
        await db.execute('CREATE INDEX idx_kitchen_stock_movements_product_date ON kitchen_stock_movements(product_id,created_at)');
      }
      if (oldVersion < 15) {
        await db.execute("CREATE TABLE IF NOT EXISTS kitchen_stock_balances(product_id INTEGER PRIMARY KEY, quantity REAL NOT NULL DEFAULT 0 CHECK(quantity>=0), weighted_average_cost REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, FOREIGN KEY(product_id) REFERENCES products(id))");
        await db.execute("CREATE TABLE IF NOT EXISTS kitchen_stock_movements(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, quantity_delta REAL NOT NULL CHECK(quantity_delta<>0), movement_type TEXT NOT NULL, source_type TEXT NOT NULL, source_id INTEGER, idempotency_key TEXT NOT NULL UNIQUE, actor_user_id INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, FOREIGN KEY(product_id) REFERENCES products(id), FOREIGN KEY(actor_user_id) REFERENCES users(id))");
        await db.execute('CREATE INDEX IF NOT EXISTS idx_kitchen_stock_movements_product_date ON kitchen_stock_movements(product_id,created_at)');
        final productColumns=await db.rawQuery('PRAGMA table_info(products)');
        if (!productColumns.any((column)=>column['name']=='preparation_required')) {
          await db.execute('ALTER TABLE products ADD COLUMN preparation_required INTEGER NOT NULL DEFAULT 0 CHECK(preparation_required IN (0,1))');
        }
        await db.execute("CREATE TABLE users_v15(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('admin','cashier','storekeeper','kitchen')), pin_salt TEXT NOT NULL, pin_hash TEXT NOT NULL, must_change_pin INTEGER NOT NULL DEFAULT 0, preferred_language TEXT NOT NULL DEFAULT 'ar', is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)");
        await db.execute('INSERT INTO users_v15(id,username,display_name,role,pin_salt,pin_hash,must_change_pin,preferred_language,is_active,created_at) SELECT id,username,display_name,role,pin_salt,pin_hash,must_change_pin,preferred_language,is_active,created_at FROM users');
        await db.execute('DROP TABLE users');
        await db.execute('ALTER TABLE users_v15 RENAME TO users');
        final foreignKeyErrors=await db.rawQuery('PRAGMA foreign_key_check');
        if(foreignKeyErrors.isNotEmpty) throw StateError('فشل التحقق من سلامة العلاقات بعد ترحيل حسابات الموظفين');
      }
      if (oldVersion < 12) {
        await db.execute("ALTER TABLE sale_lines ADD COLUMN cost_total REAL NOT NULL DEFAULT 0");
        await db.execute("ALTER TABLE sale_recipe_components ADD COLUMN unit_cost_snapshot REAL NOT NULL DEFAULT 0");
        await db.execute("INSERT INTO accounts(code,name_ar,account_type) VALUES ('COGS','تكلفة البضاعة المباعة','expense')");
      }
    });
    return _db!;
  }

  Future<int> ensureDefaultAdmin() async {
    final db = await database;
    return db.transaction((tx) async {
      final existing = await tx.rawQuery('SELECT id FROM users ORDER BY id LIMIT 1');
      if (existing.isNotEmpty) return existing.first['id'] as int;
      const username = 'admin';
      const initialPin = '123456';
      const displayName = 'مدير النظام';
      final salt = _salt();
      final now = DateTime.now().toUtc().toIso8601String();
      return tx.insert('users', {
        'username': username,
        'display_name': displayName,
        'role': 'admin',
        'pin_salt': salt,
        'pin_hash': _hash(initialPin, salt),
        'must_change_pin': 1,
        'preferred_language': 'ar',
        'is_active': 1,
        'created_at': now,
      });
    });
  }

  Future<bool> hasAdmin() async {
    final rows = await (await database).rawQuery("SELECT COUNT(*) AS n FROM users WHERE role='admin' AND is_active=1");
    return (rows.first['n'] as int) > 0;
  }

  String _hash(String pin, String salt) {
    // PBKDF2-HMAC-SHA256, one 32-byte output block.
    final key = utf8.encode(pin);
    final saltBytes = <int>[];
    for (var i = 0; i < salt.length; i += 2) {
      saltBytes.add(int.parse(salt.substring(i, i + 2), radix: 16));
    }
    final hmac = Hmac(sha256, key);
    var u = hmac.convert([...saltBytes, 0, 0, 0, 1]).bytes;
    final result = List<int>.from(u);
    for (var round = 1; round < 120000; round++) {
      u = hmac.convert(u).bytes;
      for (var i = 0; i < result.length; i++) {
        result[i] ^= u[i];
      }
    }
    return result.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  }

  String _salt() {
    final r = Random.secure();
    return List<int>.generate(24, (_) => r.nextInt(256)).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  }

  void _validatePin(String pin) {
    if (pin.length < 6 || int.tryParse(pin) == null) {
      throw ArgumentError('يجب أن يتكون PIN من ستة أرقام على الأقل');
    }
  }

  Future<int> createUser(String username, String name, String pin, String role) async {
    if (username.trim().isEmpty || name.trim().isEmpty) throw ArgumentError('اسم المستخدم واسم الموظف مطلوبان');
    if (role != 'admin') throw ArgumentError('إنشاء الحساب الأول مخصص للمدير');
    _validatePin(pin);
    final db = await database;
    return db.transaction((tx) async {
      final existing = await tx.rawQuery('SELECT COUNT(*) AS n FROM users');
      if ((existing.first['n'] as int) != 0) throw StateError('تم إنشاء حسابات مسبقاً؛ أنشئ الموظفين من إدارة المستخدمين');
      final salt = _salt();
      final now = DateTime.now().toUtc().toIso8601String();
      return tx.insert('users', {'username': username.trim().toLowerCase(), 'display_name': name.trim(), 'role': 'admin', 'pin_salt': salt, 'pin_hash': _hash(pin, salt), 'preferred_language': 'ar', 'is_active': 1, 'created_at': now});
    });
  }

  Future<List<Map<String, Object?>>> listUsers({required int actorUserId}) async {
    final db = await database;
    final actor = await db.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
    if (actor.isEmpty || actor.first['role'] != 'admin' || actor.first['is_active'] != 1) throw StateError('إدارة المستخدمين متاحة للمدير فقط');
    return db.query('users', columns: ['id', 'username', 'display_name', 'role', 'preferred_language', 'is_active', 'created_at'], orderBy: 'id');
  }

  Future<int> createEmployee({required int actorUserId, required String username, required String name, required String pin, required String role, String language = 'ar'}) async {
    if (username.trim().isEmpty || name.trim().isEmpty) throw ArgumentError('اسم المستخدم واسم الموظف مطلوبان');
    if (!['admin', 'cashier', 'storekeeper','kitchen'].contains(role)) throw ArgumentError('دور المستخدم غير صالح');
    if (!['ar', 'en', 'fr'].contains(language)) throw ArgumentError('لغة المستخدم غير صالحة');
    _validatePin(pin);
    final db = await database;
    return db.transaction((tx) async {
      final actor = await tx.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
      if (actor.isEmpty || actor.first['role'] != 'admin' || actor.first['is_active'] != 1) throw StateError('إنشاء حسابات الموظفين من صلاحية المدير فقط');
      final salt = _salt();
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await tx.insert('users', {'username': username.trim().toLowerCase(), 'display_name': name.trim(), 'role': role, 'pin_salt': salt, 'pin_hash': _hash(pin, salt), 'preferred_language': language, 'is_active': 1, 'created_at': now});
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'employee_created', 'entity_type': 'user', 'entity_id': id, 'details': 'Created employee ' + username.trim().toLowerCase() + ' with role ' + role, 'created_at': now});
      return id;
    });
  }

  Future<void> setEmployeeActive({required int actorUserId, required int targetUserId, required bool active}) async {
    final db = await database;
    await db.transaction((tx) async {
      final actor = await tx.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
      if (actor.isEmpty || actor.first['role'] != 'admin' || actor.first['is_active'] != 1) throw StateError('تعديل حالة الموظفين من صلاحية المدير فقط');
      final target = await tx.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [targetUserId], limit: 1);
      if (target.isEmpty) throw StateError('الموظف غير موجود');
      if (!active && targetUserId == actorUserId) throw StateError('لا يمكنك تعطيل حسابك الحالي');
      if (!active && target.first['role'] == 'admin' && target.first['is_active'] == 1) {
        final admins = await tx.rawQuery("SELECT COUNT(*) AS n FROM users WHERE role='admin' AND is_active=1");
        if ((admins.first['n'] as int) <= 1) throw StateError('لا يمكن تعطيل آخر حساب مدير نشط');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update('users', {'is_active': active ? 1 : 0}, where: 'id=?', whereArgs: [targetUserId]);
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': active ? 'employee_activated' : 'employee_deactivated', 'entity_type': 'user', 'entity_id': targetUserId, 'details': 'Employee active=' + active.toString(), 'created_at': now});
    });
  }

  Future<void> resetEmployeePin({required int actorUserId, required int targetUserId, required String newPin}) async {
    _validatePin(newPin);
    final db = await database;
    await db.transaction((tx) async {
      final actor = await tx.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
      if (actor.isEmpty || actor.first['role'] != 'admin' || actor.first['is_active'] != 1) throw StateError('إعادة PIN الموظفين من صلاحية المدير فقط');
      final target = await tx.query('users', columns: ['id'], where: 'id=?', whereArgs: [targetUserId], limit: 1);
      if (target.isEmpty) throw StateError('الموظف غير موجود');
      final salt = _salt();
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update('users', {'pin_salt': salt, 'pin_hash': _hash(newPin, salt)}, where: 'id=?', whereArgs: [targetUserId]);
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'employee_pin_reset', 'entity_type': 'user', 'entity_id': targetUserId, 'details': 'Employee PIN reset by administrator', 'created_at': now});
    });
  }

  Future<void> updateOwnLanguage({required int userId, required String language}) async {
    if (!['ar', 'en', 'fr'].contains(language)) throw ArgumentError('لغة المستخدم غير صالحة');
    final db = await database;
    final changed = await db.update('users', {'preferred_language': language}, where: 'id=? AND is_active=1', whereArgs: [userId]);
    if (changed != 1) throw StateError('تعذر تحديث لغة الحساب');
  }

  Future<void> changeOwnPin({required int userId, required String newPin}) async {
    _validatePin(newPin);
    final db = await database;
    await db.transaction((tx) async {
      final rows = await tx.query('users', columns: ['id','is_active'], where: 'id=?', whereArgs: [userId], limit: 1);
      if (rows.isEmpty || rows.first['is_active'] != 1) throw StateError('الحساب غير نشط');
      final salt = _salt();
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update('users', {'pin_salt': salt, 'pin_hash': _hash(newPin, salt), 'must_change_pin': 0}, where: 'id=?', whereArgs: [userId]);
      await tx.insert('audit_logs', {'actor_user_id': userId, 'action': 'own_pin_changed', 'entity_type': 'user', 'entity_id': userId, 'details': 'User changed own PIN', 'created_at': now});
    });
  }

  Future<Map<String, Object?>?> login(String username, String pin) async {
    final rows = await (await database).query('users', where: 'username=? AND is_active=1', whereArgs: [username.trim().toLowerCase()], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row['pin_hash'] != _hash(pin, row['pin_salt'] as String)) return null;
    return {'id': row['id'], 'username': row['username'], 'display_name': row['display_name'], 'role': row['role'], 'preferred_language': row['preferred_language'], 'must_change_pin': row['must_change_pin'] ?? 0};
  }


  Future<int> submitStocktake({required int actorUserId, required Map<int, double> counted, String note = ''}) async {
    if (counted.isEmpty) throw StateError('أدخل كمية فعلية لصنف واحد على الأقل');
    final db = await database;
    return db.transaction((tx) async {
      final actor = await tx.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
      if (actor.isEmpty || actor.first['is_active'] != 1 || !['admin', 'storekeeper'].contains(actor.first['role'])) {
        throw StateError('ليس لديك صلاحية إرسال الجرد');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final stocktakeId = await tx.insert('stocktakes', {'status': 'submitted', 'note': note.trim(), 'created_by': actorUserId, 'created_at': now});
      for (final entry in counted.entries) {
        final qty = entry.value;
        if (!qty.isFinite || qty < 0) throw ArgumentError('الكمية الفعلية غير صحيحة');
        final products = await tx.rawQuery(
          'SELECT p.id, COALESCE(b.approved_qty, 0) AS system_qty, COALESCE((SELECT MAX(m.id) FROM stock_movements m WHERE m.product_id=p.id), 0) AS movement_seq FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id WHERE p.id=? AND p.is_active=1 AND p.is_stock_item=1',
          [entry.key],
        );
        if (products.isEmpty) throw StateError('أحد الأصناف لم يعد متاحاً');
        final row = products.first;
        final systemQty = (row['system_qty'] as num).toDouble();
        await tx.insert('stocktake_lines', {
          'stocktake_id': stocktakeId,
          'product_id': entry.key,
          'system_qty': systemQty,
          'counted_qty': qty,
          'difference_qty': qty - systemQty,
          'movement_sequence_snapshot': row['movement_seq'],
        });
      }
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'stocktake_submitted', 'entity_type': 'stocktake', 'entity_id': stocktakeId, 'details': 'Physical count submitted; movement sequence snapshots captured', 'created_at': now});
      return stocktakeId;
    });
  }

  Future<void> reviewStocktake({required int stocktakeId, required int actorUserId, required bool approve, String note = ''}) async {
    final db = await database;
    await db.transaction((tx) async {
      final actor = await tx.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
      if (actor.isEmpty || actor.first['is_active'] != 1 || actor.first['role'] != 'admin') {
        throw StateError('اعتماد الجرد أو رفضه من صلاحية المدير فقط');
      }
      final stocktakes = await tx.query('stocktakes', where: "id=? AND status='submitted'", whereArgs: [stocktakeId], limit: 1);
      if (stocktakes.isEmpty) throw StateError('تمت مراجعة هذا الجرد مسبقاً أو لم يعد معلقاً');
      final lines = await tx.query('stocktake_lines', where: 'stocktake_id=?', whereArgs: [stocktakeId]);
      if (lines.isEmpty) throw StateError('الجرد لا يحتوي على أصناف');
      if (approve) {
        for (final line in lines) {
          final productId = line['product_id'] as int;
          final sequenceRows = await tx.rawQuery('SELECT COALESCE(MAX(id), 0) AS current_seq FROM stock_movements WHERE product_id=?', [productId]);
          final currentSequence = (sequenceRows.first['current_seq'] as num).toInt();
          final snapshotSequence = (line['movement_sequence_snapshot'] as num).toInt();
          if (currentSequence != snapshotSequence) {
            throw StateError('الجرد قديم: حدثت حركة مخزون بعد أخذ اللقطة. أعد الجرد للصنف المتأثر قبل الاعتماد.');
          }
        }
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final changed = await tx.update('stocktakes', {
        'status': approve ? 'approved' : 'rejected',
        'reviewed_by': actorUserId,
        'reviewed_at': now,
        'review_note': note.trim().isEmpty ? (approve ? 'Approved' : 'Rejected') : note.trim(),
      }, where: "id=? AND status='submitted'", whereArgs: [stocktakeId]);
      if (changed != 1) throw StateError('تعذر تغيير حالة الجرد؛ أعد تحميل الشاشة');
      if (approve) {
        for (final line in lines) {
          final diff = (line['difference_qty'] as num).toDouble();
          if (diff == 0) continue;
          final productId = line['product_id'] as int;
          final product = await tx.query('products',columns:['expiry_tracked'],where:'id=?',whereArgs:[productId],limit:1);
          if(product.isNotEmpty && product.first['expiry_tracked']==1){
            if(diff>0) throw StateError('لا يمكن إضافة فائض جرد لصنف يتتبع الصلاحية دون تسجيل دفعة وتاريخ انتهائها أولاً.');
            await InventoryService.consumeLotsFefo(tx,productId:productId,quantity:diff.abs(),actorUserId:actorUserId,source:'stocktake:$stocktakeId:$productId');
          }
          final moveId = await tx.insert('stock_movements', {
            'product_id': productId,
            'movement_type': 'count_adjustment',
            'quantity_delta': diff,
            'source_type': 'stocktake',
            'source_id': stocktakeId,
            'idempotency_key': 'stocktake:$stocktakeId:$productId',
            'actor_user_id': actorUserId,
            'note': note.trim().isEmpty ? 'Approved stocktake' : note.trim(),
            'occurred_at': now,
          });
          final updated = await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand+?, approved_qty=approved_qty+?, updated_at=? WHERE product_id=?', [diff, diff, now, productId]);
          if (updated != 1) throw StateError('رصيد الصنف غير موجود؛ تم إلغاء الاعتماد بالكامل');
          await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'stocktake_approved', 'entity_type': 'stock_movement', 'entity_id': moveId, 'details': 'Approved stocktake $stocktakeId; variance $diff', 'created_at': now});
        }
      }
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': approve ? 'stocktake_approved' : 'stocktake_rejected', 'entity_type': 'stocktake', 'entity_id': stocktakeId, 'details': note.trim(), 'created_at': now});
    });
  }

  Future<List<Map<String, Object?>>> products() async => (await database).rawQuery("SELECT p.*, COALESCE(b.on_hand,0) AS on_hand, COALESCE(b.approved_qty,0) AS approved_qty, COALESCE(b.unapproved_qty,0) AS unapproved_qty FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id WHERE p.is_active=1 AND p.is_stock_item=1 ORDER BY p.name_ar");

  Future<void> addProduct(String name, String unit, {required int actorUserId}) async {
    final db = await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await tx.insert('products', {'name_ar': name.trim(), 'base_unit': unit.trim(), 'created_at': now});
      await tx.insert('product_translations', {'product_id': id, 'language_code': 'ar', 'name': name.trim(), 'description': ''});
      await tx.insert('stock_balances', {'product_id': id, 'on_hand': 0, 'approved_qty': 0, 'unapproved_qty': 0, 'updated_at': now});
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'product_created', 'entity_type': 'product', 'entity_id': id, 'details': 'Product created in Arabic', 'created_at': now});
    });
  }
  Future<void> _requireAdmin(dynamic tx, int actorUserId) async {
    final rows = await tx.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
    if (rows.isEmpty || rows.first['role'] != 'admin' || rows.first['is_active'] != 1) throw StateError('هذه العملية متاحة للمدير النشط فقط');
  }

  Future<List<Map<String, Object?>>> listCategories({required int actorUserId, String language = 'ar'}) async {
    final db = await database;
    await _requireAdmin(db, actorUserId);
    return db.rawQuery("SELECT c.id, c.code, c.is_active, COALESCE((SELECT t.name FROM category_translations t WHERE t.category_id=c.id AND t.language_code=?), (SELECT t.name FROM category_translations t WHERE t.category_id=c.id AND t.language_code='ar'), '') AS display_name FROM categories c ORDER BY c.id", [language]);
  }

  Future<int> saveCategory({required int actorUserId, int? categoryId, required String code, required Map<String, String> names}) async {
    if (names.values.every((v) => v.trim().isEmpty)) throw ArgumentError('أدخل اسم الفئة بلغة واحدة على الأقل');
    if (names.keys.any((k) => !['ar', 'en', 'fr'].contains(k))) throw ArgumentError('لغة ترجمة الفئة غير مدعومة');
    final db = await database;
    return db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      final now = DateTime.now().toUtc().toIso8601String();
      int id;
      if (categoryId == null) {
        id = await tx.insert('categories', {'code': code.trim().isEmpty ? null : code.trim(), 'is_active': 1, 'created_at': now});
      } else {
        final changed = await tx.update('categories', {'code': code.trim().isEmpty ? null : code.trim()}, where: 'id=? AND is_active=1', whereArgs: [categoryId]);
        if (changed != 1) throw StateError('الفئة غير موجودة أو متوقفة');
        id = categoryId;
        await tx.delete('category_translations', where: 'category_id=?', whereArgs: [id]);
      }
      for (final entry in names.entries) {
        if (entry.value.trim().isNotEmpty) await tx.insert('category_translations', {'category_id': id, 'language_code': entry.key, 'name': entry.value.trim()});
      }
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': categoryId == null ? 'category_created' : 'category_updated', 'entity_type': 'category', 'entity_id': id, 'details': 'Category translations saved', 'created_at': now});
      return id;
    });
  }

  Future<List<Map<String, Object?>>> catalogProducts({required int actorUserId, String language = 'ar'}) async {
    final db = await database;
    await _requireAdmin(db, actorUserId);
    return db.rawQuery("SELECT p.*, COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?), p.name_ar) AS display_name, COALESCE((SELECT t.name FROM category_translations t WHERE t.category_id=p.category_id AND t.language_code=?), '') AS category_name, COALESCE(b.on_hand,0) AS on_hand FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id ORDER BY p.id DESC", [language, language]);
  }

  Future<int> saveCatalogProduct({required int actorUserId, int? productId, required Map<String, String> names, required String baseUnit, required String productType, required int? categoryId, String code = '', double salePrice = 0, bool preparationRequired = false}) async {
    if (names.values.every((v) => v.trim().isEmpty)) throw ArgumentError('أدخل اسم الصنف بلغة واحدة على الأقل');
    if (baseUnit.trim().isEmpty) throw ArgumentError('وحدة القياس الأساسية مطلوبة');
    if (!salePrice.isFinite || salePrice < 0) throw ArgumentError('سعر البيع غير صحيح');
    if (!['ingredient', 'sellable', 'both'].contains(productType)) throw ArgumentError('نوع الصنف غير صالح');
    if (names.keys.any((k) => !['ar', 'en', 'fr'].contains(k))) throw ArgumentError('لغة ترجمة الصنف غير مدعومة');
    final primaryName = names.values.firstWhere((value) => value.trim().isNotEmpty).trim();
    final db = await database;
    return db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      if (categoryId != null) {
        final categories = await tx.query('categories', columns: ['id'], where: 'id=? AND is_active=1', whereArgs: [categoryId], limit: 1);
        if (categories.isEmpty) throw StateError('الفئة المحددة غير موجودة أو متوقفة');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final isSellable = productType == 'sellable' || productType == 'both';
      final values = {'name_ar': primaryName, 'base_unit': baseUnit.trim(), 'sale_price': salePrice, 'category_id': categoryId, 'code': code.trim().isEmpty ? null : code.trim(), 'product_type': productType, 'is_sellable': isSellable ? 1 : 0, 'is_stock_item': productType == 'sellable' ? 0 : 1, 'preparation_required': preparationRequired ? 1 : 0};
      int id;
      if (productId == null) {
        id = await tx.insert('products', {...values, 'is_active': 1, 'created_at': now});
        await tx.insert('stock_balances', {'product_id': id, 'on_hand': 0, 'approved_qty': 0, 'unapproved_qty': 0, 'updated_at': now});
      } else {
        final changed = await tx.update('products', values, where: 'id=? AND is_active=1', whereArgs: [productId]);
        if (changed != 1) throw StateError('الصنف غير موجود أو متوقف');
        id = productId;
        await tx.delete('product_translations', where: 'product_id=?', whereArgs: [id]);
      }
      for (final entry in names.entries) {
        if (entry.value.trim().isNotEmpty) await tx.insert('product_translations', {'product_id': id, 'language_code': entry.key, 'name': entry.value.trim(), 'description': ''});
      }
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': productId == null ? 'product_created' : 'product_updated', 'entity_type': 'product', 'entity_id': id, 'details': 'Catalog product saved; type=' + productType + '; base_unit=' + baseUnit.trim(), 'created_at': now});
      return id;
    });
  }

  Future<void> deactivateCatalogProduct({required int actorUserId, required int productId}) async {
    final db = await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      final changed = await tx.update('products', {'is_active': 0}, where: 'id=? AND is_active=1', whereArgs: [productId]);
      if (changed != 1) throw StateError('الصنف غير موجود أو متوقف مسبقاً');
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'product_deactivated', 'entity_type': 'product', 'entity_id': productId, 'details': 'Product deactivated; historical records retained', 'created_at': now});
    });
  }


  Future<List<Map<String, Object?>>> listSuppliers({required int actorUserId, bool includeInactive = false}) async {
    final db = await database;
    final actor = await db.query('users', columns: ['role','is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
    if (actor.isEmpty || actor.first['is_active'] != 1 || !['admin','storekeeper'].contains(actor.first['role'])) throw StateError('ليس لديك صلاحية عرض الموردين');
    return db.query('suppliers', where: includeInactive ? null : 'is_active=1', orderBy: 'name COLLATE NOCASE');
  }

  Future<int> saveSupplier({required int actorUserId, int? supplierId, required String name, String phone = '', String address = '', String notes = ''}) async {
    if (name.trim().isEmpty) throw ArgumentError('اسم المورد مطلوب');
    final db = await database;
    return db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      final now = DateTime.now().toUtc().toIso8601String();
      final values = {'name': name.trim(), 'phone': phone.trim().isEmpty ? null : phone.trim(), 'address': address.trim().isEmpty ? null : address.trim(), 'notes': notes.trim(), 'updated_at': now};
      int id;
      if (supplierId == null) {
        id = await tx.insert('suppliers', {...values, 'is_active': 1, 'created_at': now});
      } else {
        final changed = await tx.update('suppliers', values, where: 'id=? AND is_active=1', whereArgs: [supplierId]);
        if (changed != 1) throw StateError('المورد غير موجود أو متوقف');
        id = supplierId;
      }
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': supplierId == null ? 'supplier_created' : 'supplier_updated', 'entity_type': 'supplier', 'entity_id': id, 'details': 'Supplier master data saved', 'created_at': now});
      return id;
    });
  }

  Future<void> deactivateSupplier({required int actorUserId, required int supplierId}) async {
    final db = await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      final now = DateTime.now().toUtc().toIso8601String();
      final changed = await tx.update('suppliers', {'is_active': 0, 'updated_at': now}, where: 'id=? AND is_active=1', whereArgs: [supplierId]);
      if (changed != 1) throw StateError('المورد غير موجود أو متوقف مسبقاً');
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'supplier_deactivated', 'entity_type': 'supplier', 'entity_id': supplierId, 'details': 'Supplier deactivated; historical records retained', 'created_at': now});
    });
  }


  Future<List<Map<String, Object?>>> listCustomers({required int actorUserId, bool includeInactive = false}) async {
    final db = await database;
    final actor = await db.query('users', columns: ['role','is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
    if (actor.isEmpty || actor.first['is_active'] != 1 || !['admin','cashier'].contains(actor.first['role'])) throw StateError('ليس لديك صلاحية عرض الزبائن');
    return db.rawQuery("SELECT c.*, COALESCE((SELECT SUM(s.balance) FROM sales s WHERE s.customer_id=c.id AND s.status='posted'),0) AS balance FROM customers c ${includeInactive ? '' : 'WHERE c.is_active=1'} ORDER BY c.name COLLATE NOCASE");
  }

  Future<int> saveCustomer({required int actorUserId, int? customerId, required String name, String phone='', String address='', String notes=''}) async {
    if (name.trim().isEmpty) throw ArgumentError('اسم الزبون مطلوب');
    final db = await database;
    return db.transaction((tx) async {
      final actor = await tx.query('users', columns:['role','is_active'], where:'id=?', whereArgs:[actorUserId], limit:1);
      if (actor.isEmpty || actor.first['role']!='admin' || actor.first['is_active']!=1) throw StateError('إدارة الزبائن من صلاحية المدير فقط');
      final now=DateTime.now().toUtc().toIso8601String();
      final values={'name':name.trim(),'phone':phone.trim().isEmpty?null:phone.trim(),'address':address.trim().isEmpty?null:address.trim(),'notes':notes.trim(),'updated_at':now};
      int id;
      if(customerId==null){ id=await tx.insert('customers',{...values,'is_active':1,'created_at':now}); }
      else { final n=await tx.update('customers',values,where:'id=? AND is_active=1',whereArgs:[customerId]); if(n!=1) throw StateError('الزبون غير موجود أو متوقف'); id=customerId; }
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':customerId==null?'customer_created':'customer_updated','entity_type':'customer','entity_id':id,'details':'Customer master data saved','created_at':now});
      return id;
    });
  }

  Future<void> deactivateCustomer({required int actorUserId, required int customerId}) async {
    final db = await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      final changed = await tx.update('customers', {'is_active': 0, 'updated_at': DateTime.now().toUtc().toIso8601String()}, where: 'id=? AND is_active=1', whereArgs: [customerId]);
      if (changed != 1) throw StateError('الزبون غير موجود أو متوقف مسبقاً');
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'customer_deactivated', 'entity_type': 'customer', 'entity_id': customerId, 'details': 'Customer deactivated; balances and historical invoices retained', 'created_at': now});
    });
  }

  Future<void> deactivateCategory({required int actorUserId, required int categoryId}) async {
    final db = await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      final changed = await tx.update('categories', {'is_active': 0}, where: 'id=? AND is_active=1', whereArgs: [categoryId]);
      if (changed != 1) throw StateError('الفئة غير موجودة أو متوقفة مسبقاً');
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'category_deactivated', 'entity_type': 'category', 'entity_id': categoryId, 'details': 'Category deactivated; historical product references retained', 'created_at': now});
    });
  }


  Future<List<Map<String, Object?>>> sellableProducts({required int actorUserId}) async {
    final db=await database;
    final a=await db.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
    if(a.isEmpty || a.first['is_active']!=1 || !['admin','cashier'].contains(a.first['role'])) throw StateError('ليس لديك صلاحية الكاشير');
    return db.rawQuery("SELECT p.id,p.name_ar,p.base_unit,p.sale_price,p.is_stock_item,p.preparation_required,CASE WHEN p.is_stock_item=0 AND NOT EXISTS(SELECT 1 FROM recipes r WHERE r.product_id=p.id AND r.is_active=1) THEN NULL WHEN EXISTS(SELECT 1 FROM recipes r WHERE r.product_id=p.id AND r.is_active=1) THEN COALESCE((SELECT MIN(ksb.quantity / rl.quantity_per_meal) FROM recipes r2 JOIN recipe_lines rl ON rl.recipe_id=r2.id LEFT JOIN kitchen_stock_balances ksb ON ksb.product_id=rl.ingredient_product_id WHERE r2.product_id=p.id AND r2.is_active=1),0) ELSE COALESCE(b.on_hand,0) END AS on_hand FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id WHERE p.is_active=1 AND p.is_sellable=1 ORDER BY p.name_ar");
  }


  Future<int> createSale({required int actorUserId, int? customerId, required List<Map<String,Object?>> lines, double discount=0, required double paid, String note='', String discountReason=''}) async {
    if(lines.isEmpty) throw StateError('أضف صنفاً واحداً على الأقل');
    if(!discount.isFinite || discount<0 || !paid.isFinite || paid<0) throw ArgumentError('قيمة الخصم أو المدفوع غير صحيحة');
    if(discount>0 && discountReason.trim().isEmpty) throw ArgumentError('سبب الخصم إلزامي');
    final db=await database;
    return db.transaction((tx) async {
      final ar=await tx.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
      if(ar.isEmpty || ar.first['is_active']!=1 || !['admin','cashier'].contains(ar.first['role'])) throw StateError('ليس لديك صلاحية تنفيذ البيع');
      if(customerId!=null){final cr=await tx.query('customers',columns:['id'],where:'id=? AND is_active=1',whereArgs:[customerId],limit:1);if(cr.isEmpty)throw StateError('الزبون غير موجود أو متوقف');}
      final prepared=<Map<String,Object?>>[]; double subtotal=0;
      for(final line in lines){
        final id=line['productId'] as int; final qty=(line['quantity'] as num).toDouble();
        if(!qty.isFinite||qty<=0)throw ArgumentError('كمية الصنف يجب أن تكون أكبر من صفر');
        final rows=await tx.rawQuery("SELECT p.name_ar,p.base_unit,p.sale_price,p.is_stock_item,p.preparation_required FROM products p WHERE p.id=? AND p.is_active=1 AND p.is_sellable=1",[id]);
        if(rows.isEmpty)throw StateError('أحد الأصناف غير متاح للبيع');
        final p=rows.first; final price=(line['unitPrice'] as num).toDouble();
        if(!price.isFinite||price<0)throw ArgumentError('سعر البيع غير صحيح');
        final recipeRows=await tx.rawQuery("SELECT r.version,rl.ingredient_product_id,rl.quantity_per_meal,rl.unit_snapshot,ip.name_ar,COALESCE(ksb.quantity,0) AS available,COALESCE(ksb.weighted_average_cost,sb.weighted_average_cost,0) AS unit_cost FROM recipes r JOIN recipe_lines rl ON rl.recipe_id=r.id JOIN products ip ON ip.id=rl.ingredient_product_id LEFT JOIN kitchen_stock_balances ksb ON ksb.product_id=ip.id LEFT JOIN stock_balances sb ON sb.product_id=ip.id WHERE r.product_id=? AND r.is_active=1",[id]);
        final components=<Map<String,Object?>>[];
        for(final c in recipeRows){
          final needed=(c['quantity_per_meal'] as num).toDouble()*qty;
          final available=(c['available'] as num).toDouble();
          if(available<needed)throw StateError('المخزون غير كافٍ لمكونات '+p['name_ar'].toString()+': '+c['name_ar'].toString()+'؛ المطلوب '+needed.toString()+' والمتاح '+available.toString());
          components.add({'id':c['ingredient_product_id'],'name':c['name_ar'],'unit':c['unit_snapshot'],'qty':needed,'version':c['version'],'unitCost':(c['unit_cost'] as num).toDouble()});
        }
        double directUnitCost=0;
        if(components.isEmpty && p['is_stock_item']==1){
          final stock=await tx.query('stock_balances',columns:['approved_qty','weighted_average_cost'],where:'product_id=?',whereArgs:[id],limit:1);
          final available=stock.isEmpty?0:(stock.first['approved_qty'] as num).toDouble();
          directUnitCost=stock.isEmpty?0:(stock.first['weighted_average_cost'] as num).toDouble();
          if(available<qty)throw StateError('المخزون غير كافٍ للصنف '+p['name_ar'].toString()+'؛ المتاح '+available.toString());
        }
        final lineTotal=qty*price;subtotal+=lineTotal;
        final costTotal=components.isEmpty ? (p['is_stock_item']==1 ? qty*directUnitCost : 0.0) : components.fold<double>(0,(sum,component)=>sum+(component['qty'] as double)*(component['unitCost'] as double));
        prepared.add({'id':id,'name':p['name_ar'],'unit':p['base_unit'],'qty':qty,'price':price,'total':lineTotal,'costTotal':costTotal,'components':components,'isStockItem':p['is_stock_item']==1,'preparationRequired':p['preparation_required']==1});
      }
      final total=subtotal-discount;
      if(discount>subtotal||paid>total)throw ArgumentError('تحقق من الخصم والمبلغ المدفوع');
      if(total-paid>0&&customerId==null)throw StateError('اختر زبوناً لتسجيل البيع الآجل');
      final now=DateTime.now().toUtc().toIso8601String();final invoice='S-'+DateTime.now().microsecondsSinceEpoch.toString();
      final saleId=await tx.insert('sales',{'invoice_no':invoice,'customer_id':customerId,'cashier_user_id':actorUserId,'subtotal':subtotal,'discount':discount,'total':total,'paid':paid,'balance':total-paid,'status':'posted','created_at':now});
      final kitchenLineIds=<int>[];
      for(final l in prepared){
        final saleLineId=await tx.insert('sale_lines',{'sale_id':saleId,'product_id':l['id'],'product_name_snapshot':l['name'],'unit_snapshot':l['unit'],'quantity':l['qty'],'unit_price':l['price'],'line_total':l['total']});
        final components=l['components'] as List<Map<String,Object?>>;
        if(components.isEmpty){
          final q=l['qty'] as double;final pid=l['id'] as int;
          if(l['isStockItem']==true){
            await InventoryService.consumeLotsFefo(tx,productId:pid,quantity:q,actorUserId:actorUserId,source:'sale:$saleId:$pid');
            await tx.insert('stock_movements',{'product_id':pid,'movement_type':'sale','quantity_delta':-q,'source_type':'sale','source_id':saleId,'idempotency_key':'sale:$saleId:$pid','actor_user_id':actorUserId,'note':'Invoice $invoice','occurred_at':now});
            final changed=await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand-?,approved_qty=approved_qty-?,updated_at=? WHERE product_id=? AND approved_qty>=?',[q,q,now,pid,q]);
            if(changed!=1)throw StateError('تغير المخزون أثناء البيع؛ ألغيت العملية بالكامل');
          }
          if(l['preparationRequired']==true) kitchenLineIds.add(saleLineId);
        }else{
          kitchenLineIds.add(saleLineId);
          for(final c in components){
            final pid=c['id'] as int;final q=c['qty'] as double;
            final kitchenBalance=await tx.query('kitchen_stock_balances',where:'product_id=?',whereArgs:[pid],limit:1);
            final kitchenAvailable=kitchenBalance.isEmpty?0.0:(kitchenBalance.first['quantity'] as num).toDouble();
            if(kitchenAvailable+0.0000001<q)throw StateError('رصيد المطبخ غير كافٍ للمكون '+c['name'].toString()+'؛ اطلب تزويداً من أمين المخزن');
            final kitchenChanged=await tx.rawUpdate('UPDATE kitchen_stock_balances SET quantity=quantity-?,updated_at=? WHERE product_id=? AND quantity>=?',[q,now,pid,q]);
            if(kitchenChanged!=1)throw StateError('تغير رصيد المطبخ أثناء البيع؛ ألغيت العملية بالكامل');
            await tx.insert('kitchen_stock_movements',{'product_id':pid,'quantity_delta':-q,'movement_type':'recipe_consumption','source_type':'sale_recipe','source_id':saleLineId,'idempotency_key':'kitchen-recipe:sale:$saleLineId:$pid','actor_user_id':actorUserId,'note':'Recipe consumption for $invoice','created_at':now});
            await tx.insert('sale_recipe_components',{'sale_line_id':saleLineId,'ingredient_product_id':pid,'ingredient_name_snapshot':c['name'],'unit_snapshot':c['unit'],'quantity':q,'recipe_version':c['version'],'unit_cost_snapshot':c['unitCost']});
            // Recipe ingredients are consumed from the kitchen's custody balance. The main store was reduced at handover, so it must not be deducted again here.
          }
        }
      }
      if(kitchenLineIds.isNotEmpty){
        final orderId=await tx.insert('kitchen_orders',{'sale_id':saleId,'status':'new','created_at':now,'updated_at':now});
        for(final lineId in kitchenLineIds){await tx.insert('kitchen_order_lines',{'kitchen_order_id':orderId,'sale_line_id':lineId});}
      }
      if(paid>0){
        if(customerId!=null) await tx.insert('customer_payments',{'customer_id':customerId,'sale_id':saleId,'amount':paid,'payment_type':'sale_payment','note':note,'received_by':actorUserId,'created_at':now});
        await tx.insert('cash_transactions',{'direction':'in','category':'sale','amount':paid,'payment_method':'cash','source_type':'sale','source_id':saleId,'idempotency_key':'cash:sale:'+saleId.toString(),'note':'قبض فاتورة '+invoice,'actor_user_id':actorUserId,'created_at':now});
      }
      final journalLines=<Map<String,Object?>>[];
      if(paid>0) journalLines.add({'accountCode':'CASH','debit':paid,'credit':0.0});
      if(total-paid>0) journalLines.add({'accountCode':'AR','debit':total-paid,'credit':0.0});
      if(total>0) journalLines.add({'accountCode':'SALES','debit':0.0,'credit':total});
      final costTotal=prepared.fold<double>(0,(sum,line)=>sum+(line['costTotal'] as double));
      if(costTotal>0){journalLines.add({'accountCode':'COGS','debit':costTotal,'credit':0.0});journalLines.add({'accountCode':'INVENTORY','debit':0.0,'credit':costTotal});}
      if(journalLines.length>=2) await _postJournal(tx,actorUserId:actorUserId,sourceType:'sale',sourceId:saleId,description:'فاتورة بيع '+invoice,lines:journalLines);
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'sale_posted','entity_type':'sale','entity_id':saleId,'details':'Invoice '+invoice+'; total='+total.toString()+'; paid='+paid.toString()+'; balance='+(total-paid).toString()+'; discountReason='+discountReason.trim()+'; kitchenLines='+kitchenLineIds.length.toString(),'created_at':now});
      return saleId;
    });
  }


  Future<List<Map<String,Object?>>> customerStatement({required int actorUserId, required int customerId}) async {
    final db=await database;
    final actor=await db.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
    if(actor.isEmpty || actor.first['is_active']!=1 || !['admin','cashier'].contains(actor.first['role'])) throw StateError('ليس لديك صلاحية كشف الحساب');
    return db.rawQuery("SELECT created_at AS date,'فاتورة' AS type,invoice_no AS reference,total AS debit,0 AS credit,balance,id AS record_id,0 AS sort_order FROM sales WHERE customer_id=? AND status='posted' UNION ALL SELECT created_at AS date,'تحصيل' AS type,'PAY-'||id AS reference,0 AS debit,amount AS credit,0 AS balance,id AS record_id,1 AS sort_order FROM customer_payments WHERE customer_id=? AND payment_type IN ('account_payment','sale_payment') UNION ALL SELECT r.created_at AS date,'استرداد فاتورة' AS type,'REF-'||r.id AS reference,r.amount AS debit,0 AS credit,0 AS balance,r.id AS record_id,2 AS sort_order FROM sale_refunds r JOIN sales s ON s.id=r.sale_id WHERE s.customer_id=? ORDER BY date,sort_order,record_id",[customerId,customerId,customerId]);
  }
  Future<void> receiveCustomerPayment({required int actorUserId,required int customerId,required double amount,required String note}) async {
    if(!amount.isFinite || amount<=0) throw ArgumentError('مبلغ التحصيل يجب أن يكون أكبر من صفر');
    if(note.trim().isEmpty) throw ArgumentError('بيان التحصيل مطلوب');
    final db=await database;
    await db.transaction((tx) async {
      final actor=await tx.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
      if(actor.isEmpty || actor.first['is_active']!=1 || !['admin','cashier'].contains(actor.first['role'])) throw StateError('ليس لديك صلاحية التحصيل');
      final customer=await tx.query('customers',columns:['id'],where:'id=? AND is_active=1',whereArgs:[customerId],limit:1);
      if(customer.isEmpty) throw StateError('الزبون غير موجود أو متوقف');
      final dueRows=await tx.rawQuery("SELECT COALESCE(SUM(balance),0) AS due FROM sales WHERE customer_id=? AND status='posted'",[customerId]);
      final due=(dueRows.first['due'] as num).toDouble();
      if(amount>due) throw StateError('المبلغ أكبر من رصيد الزبون ($due)');
      final now=DateTime.now().toUtc().toIso8601String();
      await tx.insert('customer_payments',{'customer_id':customerId,'sale_id':null,'amount':amount,'payment_type':'account_payment','note':note.trim(),'received_by':actorUserId,'created_at':now});
      var remaining=amount;
      final invoices=await tx.query('sales',columns:['id','paid','balance'],where:"customer_id=? AND status='posted' AND balance>0",whereArgs:[customerId],orderBy:'created_at ASC,id ASC');
      for(final invoice in invoices){
        if(remaining<=0) break;
        final balance=(invoice['balance'] as num).toDouble();
        final paid=(invoice['paid'] as num).toDouble();
        final applied=remaining<balance?remaining:balance;
        await tx.update('sales',{'paid':paid+applied,'balance':balance-applied},where:'id=?',whereArgs:[invoice['id']]);
        remaining-=applied;
      }
      final cashTxId=await tx.insert('cash_transactions',{'direction':'in','category':'customer_payment','amount':amount,'payment_method':'cash','source_type':'customer_payment','source_id':customerId,'idempotency_key':'cash:customer-payment:'+DateTime.now().microsecondsSinceEpoch.toString(),'note':note.trim(),'actor_user_id':actorUserId,'created_at':now});
      await _postJournal(tx,actorUserId:actorUserId,sourceType:'customer_payment',sourceId:cashTxId,description:'تحصيل من زبون',lines:[{'accountCode':'CASH','debit':amount,'credit':0.0},{'accountCode':'AR','debit':0.0,'credit':amount}]);
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'customer_payment_received','entity_type':'customer','entity_id':customerId,'details':'Received '+amount.toString()+'; '+note.trim(),'created_at':now});
    });
  }

  Future<List<Map<String,Object?>>> purchaseableProducts({required int actorUserId, String language='ar'}) async {
    final db=await database;
    final a=await db.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
    if(a.isEmpty || a.first['is_active']!=1 || !['admin','storekeeper'].contains(a.first['role'])) throw StateError('ليس لديك صلاحية التوريد');
    return db.rawQuery("SELECT p.id,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code='ar'),p.name_ar) AS name_ar,p.base_unit,COALESCE(b.on_hand,0) AS on_hand FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id WHERE p.is_active=1 AND p.is_stock_item=1 ORDER BY name_ar",[language]);
  }
  Future<int> submitPurchaseReceipt({required int actorUserId,required int supplierId,required String invoiceNo,required List<Map<String,Object?>> lines}) async {
    if(invoiceNo.trim().isEmpty || lines.isEmpty) throw ArgumentError('رقم فاتورة المورد والأصناف مطلوبان');
    final db=await database;
    return db.transaction((tx) async {
      final actor=await tx.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
      if(actor.isEmpty || actor.first['is_active']!=1 || !['admin','storekeeper'].contains(actor.first['role'])) throw StateError('ليس لديك صلاحية تسجيل الاستلام');
      final supplier=await tx.query('suppliers',columns:['id'],where:'id=? AND is_active=1',whereArgs:[supplierId],limit:1);
      if(supplier.isEmpty) throw StateError('المورد غير موجود أو متوقف');
      final now=DateTime.now().toUtc().toIso8601String();
      final rid=await tx.insert('purchase_receipts',{'invoice_no':invoiceNo.trim(),'supplier_id':supplierId,'status':'submitted','created_by':actorUserId,'created_at':now});
      for(final line in lines){
        final pid=line['productId'] as int; final qty=(line['quantity'] as num).toDouble();
        final enteredQty=(line['enteredQuantity'] as num?)?.toDouble()??qty;
        final enteredUnit=(line['enteredUnitName']??'').toString();
        final conversion=(line['conversionToBase'] as num?)?.toDouble()??1.0;
        if(!qty.isFinite || qty<=0 || !enteredQty.isFinite || enteredQty<=0 || !conversion.isFinite || conversion<=0 || (enteredQty*conversion-qty).abs()>0.000001) throw ArgumentError('كمية الاستلام أو معامل التحويل غير صحيح');
        final product=await tx.query('products',columns:['id'],where:'id=? AND is_active=1 AND is_stock_item=1',whereArgs:[pid],limit:1);
        if(product.isEmpty) throw StateError('أحد أصناف الاستلام غير صالح');
        final receiptLineId=await tx.insert('purchase_receipt_lines',{'receipt_id':rid,'product_id':pid,'received_qty':qty,'unit_cost':0,'line_total':0,'entered_qty':enteredQty,'entered_unit_name':enteredUnit,'conversion_to_base_snapshot':conversion});
        final balanceRows=await tx.query('stock_balances',where:'product_id=?',whereArgs:[pid],limit:1);
        if(balanceRows.isEmpty) throw StateError('رصيد الصنف غير موجود');
        final pendingQty=(balanceRows.first['unapproved_qty'] as num).toDouble();
        final onHand=(balanceRows.first['on_hand'] as num).toDouble();
        await tx.update('stock_balances',{'on_hand':onHand+qty,'unapproved_qty':pendingQty+qty,'updated_at':now},where:'product_id=?',whereArgs:[pid]);
        final lineId = receiptLineId;
        await tx.insert('stock_movements',{'product_id':pid,'movement_type':'purchase_pending','quantity_delta':qty,'source_type':'purchase_receipt','source_id':rid,'idempotency_key':'purchase-pending:'+rid.toString()+':'+lineId.toString(),'actor_user_id':actorUserId,'note':'استلام فعلي بانتظار اعتماد المدير','occurred_at':now});
      }
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'purchase_receipt_submitted','entity_type':'purchase_receipt','entity_id':rid,'details':'Supplier invoice '+invoiceNo.trim()+' submitted for review','created_at':now});
      return rid;
    });
  }
  Future<List<Map<String,Object?>>> pendingPurchaseReceipts({required int actorUserId}) async {
    final db=await database; await _requireAdmin(db,actorUserId);
    return db.rawQuery("SELECT r.*,s.name AS supplier_name,(SELECT COUNT(*) FROM purchase_receipt_lines l WHERE l.receipt_id=r.id) AS line_count FROM purchase_receipts r JOIN suppliers s ON s.id=r.supplier_id WHERE r.status='submitted' ORDER BY r.id");
  }
  Future<List<Map<String,Object?>>> purchaseReceiptLines({required int actorUserId,required int receiptId}) async {
    final db=await database; await _requireAdmin(db,actorUserId);
    return db.rawQuery("SELECT l.*,p.name_ar,p.base_unit FROM purchase_receipt_lines l JOIN products p ON p.id=l.product_id WHERE l.receipt_id=? ORDER BY l.id",[receiptId]);
  }
  Future<void> approvePurchaseReceipt({required int actorUserId,required int receiptId,required Map<int,double> unitCosts}) async {
    if(unitCosts.isEmpty || unitCosts.values.any((v)=>!v.isFinite || v<0)) throw ArgumentError('أدخل تكاليف شراء صحيحة');
    final db=await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx,actorUserId);
      final receipts=await tx.query('purchase_receipts',where:"id=? AND status='submitted'",whereArgs:[receiptId],limit:1);
      if(receipts.isEmpty) throw StateError('فاتورة التوريد غير معلقة أو تمت مراجعتها');
      final receipt=receipts.first;
      final lines=await tx.query('purchase_receipt_lines',where:'receipt_id=?',whereArgs:[receiptId]);
      if(lines.isEmpty || lines.any((l)=>!unitCosts.containsKey(l['id'] as int))) throw StateError('يجب تحديد تكلفة كل صنف في الفاتورة');
      final now=DateTime.now().toUtc().toIso8601String(); double total=0;
      for(final line in lines){
        final lid=line['id'] as int; final pid=line['product_id'] as int;
        final qty=(line['received_qty'] as num).toDouble(); final cost=unitCosts[lid]!;
        final lineTotal=qty*cost; total+=lineTotal;
        final balances=await tx.query('stock_balances',where:'product_id=?',whereArgs:[pid],limit:1);
        if(balances.isEmpty) throw StateError('رصيد الصنف غير موجود');
        final b=balances.first; final oldQty=(b['approved_qty'] as num).toDouble();
        final oldCost=(b['weighted_average_cost'] as num).toDouble(); final newQty=oldQty+qty;
        final average=newQty==0?0:((oldQty*oldCost)+(qty*cost))/newQty;
        await tx.update('purchase_receipt_lines',{'unit_cost':cost,'line_total':lineTotal},where:'id=?',whereArgs:[lid]);
        final pendingQty=(b['unapproved_qty'] as num).toDouble();
        if(pendingQty<qty) throw StateError('كمية الاستلام المعلقة لا تطابق الفاتورة');
        await tx.update('stock_balances',{'on_hand':(b['on_hand'] as num).toDouble(),'approved_qty':newQty,'unapproved_qty':pendingQty-qty,'weighted_average_cost':average,'updated_at':now},where:'product_id=?',whereArgs:[pid]);
        await tx.insert('stock_movements',{'product_id':pid,'movement_type':'purchase_approved','quantity_delta':0,'source_type':'purchase_receipt','source_id':receiptId,'idempotency_key':'purchase-approved:'+receiptId.toString()+':'+lid.toString(),'actor_user_id':actorUserId,'note':'Approved supplier invoice '+receipt['invoice_no'].toString(),'occurred_at':now});
      }
      await tx.update('purchase_receipts',{'status':'approved','reviewed_by':actorUserId,'reviewed_at':now,'total_cost':total},where:'id=?',whereArgs:[receiptId]);
      await tx.insert('supplier_ledger',{'supplier_id':receipt['supplier_id'],'receipt_id':receiptId,'entry_type':'purchase','debit':total,'credit':0,'note':'Supplier invoice '+receipt['invoice_no'].toString(),'actor_user_id':actorUserId,'created_at':now});
      if(total>0) await _postJournal(tx,actorUserId:actorUserId,sourceType:'purchase_receipt',sourceId:receiptId,description:'اعتماد فاتورة توريد '+receipt['invoice_no'].toString(),lines:[{'accountCode':'INVENTORY','debit':total,'credit':0.0},{'accountCode':'AP','debit':0.0,'credit':total}]);
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'purchase_receipt_approved','entity_type':'purchase_receipt','entity_id':receiptId,'details':'Approved supplier invoice; total='+total.toString(),'created_at':now});
    });
  }
  Future<void> _postJournal(dynamic tx, {required int actorUserId, required String sourceType, required int sourceId, required String description, required List<Map<String, Object?>> lines}) async {
    if (lines.length < 2) throw StateError('القيد المحاسبي يحتاج سطرين على الأقل');
    double debit = 0; double credit = 0;
    for (final line in lines) {
      final d = (line['debit'] as num).toDouble(); final cr = (line['credit'] as num).toDouble();
      if (!d.isFinite || !cr.isFinite || d < 0 || cr < 0 || (d > 0 && cr > 0) || (d == 0 && cr == 0)) throw StateError('سطر قيد محاسبي غير صالح');
      debit += d; credit += cr;
    }
    if ((debit - credit).abs() > 0.000001) throw StateError('القيد غير متوازن: المدين '+debit.toString()+' والدائن '+credit.toString());
    final existing = await tx.query('journal_entries', columns:['id'], where:'source_type=? AND source_id=?', whereArgs:[sourceType,sourceId], limit:1);
    if (existing.isNotEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final entryId = await tx.insert('journal_entries', {'entry_no':'J-'+DateTime.now().microsecondsSinceEpoch.toString(),'source_type':sourceType,'source_id':sourceId,'description':description,'actor_user_id':actorUserId,'created_at':now});
    for (final line in lines) {
      final accounts = await tx.query('accounts', columns:['id'], where:'code=? AND is_active=1', whereArgs:[line['accountCode']], limit:1);
      if (accounts.isEmpty) throw StateError('الحساب المحاسبي غير موجود: '+line['accountCode'].toString());
      await tx.insert('journal_lines', {'entry_id':entryId,'account_id':accounts.first['id'],'debit':line['debit'],'credit':line['credit']});
    }
  }

  Future<void> _postSaleJournalAdjustment(dynamic tx,{required int actorUserId,required int saleId,required int adjustmentId,required double paid,required double total,required double costTotal}) async {
    final old=<String,Map<String,double>>{};
    final rows=await tx.rawQuery("SELECT a.code,SUM(l.debit) AS debit,SUM(l.credit) AS credit FROM journal_lines l JOIN accounts a ON a.id=l.account_id JOIN journal_entries e ON e.id=l.entry_id WHERE (e.source_type='sale' AND e.source_id=?) OR (e.source_type LIKE 'sale_adjustment:%' AND e.source_id=?) GROUP BY a.code",[saleId,saleId]);
    for(final row in rows){old[row['code'].toString()]={'debit':(row['debit'] as num).toDouble(),'credit':(row['credit'] as num).toDouble()};}
    final target=<String,Map<String,double>>{
      'CASH':{'debit':paid,'credit':0},
      'AR':{'debit':total-paid,'credit':0},
      'SALES':{'debit':0,'credit':total},
      'COGS':{'debit':costTotal,'credit':0},
      'INVENTORY':{'debit':0,'credit':costTotal},
    };
    final adjustments=<Map<String,Object?>>[];
    for(final code in target.keys){
      final previous=old[code]??{'debit':0.0,'credit':0.0};
      final debitDelta=target[code]!['debit']!-previous['debit']!;
      final creditDelta=target[code]!['credit']!-previous['credit']!;
      if(debitDelta>0.000001)adjustments.add({'accountCode':code,'debit':debitDelta,'credit':0.0});
      else if(debitDelta < -0.000001)adjustments.add({'accountCode':code,'debit':0.0,'credit':-debitDelta});
      if(creditDelta>0.000001)adjustments.add({'accountCode':code,'debit':0.0,'credit':creditDelta});
      else if(creditDelta < -0.000001)adjustments.add({'accountCode':code,'debit':-creditDelta,'credit':0.0});
    }
    if(adjustments.isNotEmpty)await _postJournal(tx,actorUserId:actorUserId,sourceType:'sale_adjustment:'+adjustmentId.toString(),sourceId:saleId,description:'تسوية تعديل كميات الفاتورة '+saleId.toString(),lines:adjustments);
  }
  Future<void> _reverseJournal(dynamic tx, {required int actorUserId, required String sourceType, required int sourceId, required String reverseSourceType, required int reverseSourceId, required String description}) async {
    final entries = await tx.query('journal_entries', where:'source_type=? AND source_id=?', whereArgs:[sourceType,sourceId], limit:1);
    if (entries.isEmpty) return;
    final originalId = entries.first['id'] as int;
    final originalLines = await tx.query('journal_lines', where:'entry_id=?', whereArgs:[originalId]);
    final reversed = <Map<String,Object?>>[];
    for (final line in originalLines) {
      final debit = (line['debit'] as num).toDouble(); final credit = (line['credit'] as num).toDouble();
      final accountRows = await tx.query('accounts', columns:['code'], where:'id=?', whereArgs:[line['account_id']], limit:1);
      if (accountRows.isEmpty) throw StateError('حساب القيد الأصلي غير موجود');
      reversed.add({'accountCode':accountRows.first['code'],'debit':credit,'credit':debit});
    }
    await _postJournal(tx,actorUserId:actorUserId,sourceType:reverseSourceType,sourceId:reverseSourceId,description:description,lines:reversed);
  }
  Future<void> paySupplier({required int actorUserId, required int supplierId, required double amount, required String note}) async {
    if (!amount.isFinite || amount <= 0) throw ArgumentError('مبلغ الدفع يجب أن يكون أكبر من صفر');
    if (note.trim().isEmpty) throw ArgumentError('بيان الدفع مطلوب');
    final db = await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      final supplier = await tx.query('suppliers', columns: ['id'], where: 'id=? AND is_active=1', whereArgs: [supplierId], limit: 1);
      if (supplier.isEmpty) throw StateError('المورد غير موجود أو متوقف');
      final dueRows = await tx.rawQuery("SELECT COALESCE(SUM(debit-credit),0) AS due FROM supplier_ledger WHERE supplier_id=?", [supplierId]);
      final due = (dueRows.first['due'] as num).toDouble();
      if (amount > due) throw StateError('المبلغ أكبر من رصيد المورد المستحق ('+due.toString()+')');
      final cashRows = await tx.rawQuery("SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS balance FROM cash_transactions");
      final cashBalance = (cashRows.first['balance'] as num).toDouble();
      if (amount > cashBalance) throw StateError('رصيد الصندوق غير كافٍ. المتاح: '+cashBalance.toString());
      final now = DateTime.now().toUtc().toIso8601String();
      final paymentId = await tx.insert('supplier_ledger', {'supplier_id':supplierId,'receipt_id':null,'entry_type':'payment','debit':0,'credit':amount,'note':note.trim(),'actor_user_id':actorUserId,'created_at':now});
      await tx.insert('cash_transactions', {'direction':'out','category':'supplier_payment','amount':amount,'payment_method':'cash','source_type':'supplier_payment','source_id':paymentId,'idempotency_key':'cash:supplier-payment:'+paymentId.toString(),'note':note.trim(),'actor_user_id':actorUserId,'created_at':now});
      await _postJournal(tx,actorUserId:actorUserId,sourceType:'supplier_payment',sourceId:paymentId,description:'سداد مستحقات مورد',lines:[{'accountCode':'AP','debit':amount,'credit':0.0},{'accountCode':'CASH','debit':0.0,'credit':amount}]);
      await tx.insert('audit_logs', {'actor_user_id':actorUserId,'action':'supplier_payment_made','entity_type':'supplier','entity_id':supplierId,'details':'Paid '+amount.toString()+'; '+note.trim(),'created_at':now});
    });
  }

  Future<void> recordOpeningCashBalance({required int actorUserId,required double amount,required String note}) async {
    if (!amount.isFinite || amount <= 0) throw ArgumentError('رصيد بداية الصندوق يجب أن يكون أكبر من صفر');
    if (note.trim().isEmpty) throw ArgumentError('بيان رصيد البداية مطلوب');
    final db=await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx,actorUserId);
      final existing=await tx.query('cash_transactions',columns:['id'],limit:1);
      if(existing.isNotEmpty) throw StateError('تم تسجيل حركات نقدية مسبقاً؛ لا يمكن إضافة رصيد افتتاحي بأثر رجعي');
      final now=DateTime.now().toUtc().toIso8601String();
      final id=await tx.insert('cash_transactions',{'direction':'in','category':'opening_balance','amount':amount,'payment_method':'cash','source_type':'opening_balance','source_id':null,'idempotency_key':'cash:opening-balance','note':note.trim(),'actor_user_id':actorUserId,'created_at':now});
      await _postJournal(tx,actorUserId:actorUserId,sourceType:'opening_balance',sourceId:id,description:'رصيد افتتاحي للصندوق',lines:[{'accountCode':'CASH','debit':amount,'credit':0.0},{'accountCode':'CAPITAL','debit':0.0,'credit':amount}]);
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'cash_opening_balance_recorded','entity_type':'cash_transaction','entity_id':id,'details':'Opening cash balance '+amount.toString(),'created_at':now});
    });
  }
  Future<int> recordCashExpense({required int actorUserId, required String category, required double amount, required String note}) async {
    if (!amount.isFinite || amount <= 0) throw ArgumentError('مبلغ المصروف يجب أن يكون أكبر من صفر');
    if (category.trim().isEmpty || note.trim().isEmpty) throw ArgumentError('تصنيف وبيان المصروف مطلوبان');
    final db = await database;
    return db.transaction((tx) async {
      await _requireAdmin(tx, actorUserId);
      final cashRows = await tx.rawQuery("SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS balance FROM cash_transactions");
      final cashBalance = (cashRows.first['balance'] as num).toDouble();
      if (amount > cashBalance) throw StateError('رصيد الصندوق غير كافٍ. المتاح: '+cashBalance.toString());
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await tx.insert('cash_transactions', {'direction':'out','category':'expense','amount':amount,'payment_method':'cash','source_type':'expense','source_id':null,'idempotency_key':'cash:expense:'+DateTime.now().microsecondsSinceEpoch.toString(),'note':category.trim()+' - '+note.trim(),'actor_user_id':actorUserId,'created_at':now});
      await _postJournal(tx,actorUserId:actorUserId,sourceType:'cash_expense',sourceId:id,description:category.trim()+' - '+note.trim(),lines:[{'accountCode':'EXPENSE','debit':amount,'credit':0.0},{'accountCode':'CASH','debit':0.0,'credit':amount}]);
      await tx.insert('audit_logs', {'actor_user_id':actorUserId,'action':'cash_expense_recorded','entity_type':'cash_transaction','entity_id':id,'details':category.trim()+'; amount='+amount.toString()+'; '+note.trim(),'created_at':now});
      return id;
    });
  }

  Future<Map<String, double>> cashSummary({required int actorUserId}) async {
    final db = await database;
    await _requireAdmin(db, actorUserId);
    final rows = await db.rawQuery("SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE 0 END),0) AS total_in, COALESCE(SUM(CASE WHEN direction='out' THEN amount ELSE 0 END),0) AS total_out FROM cash_transactions");
    final row = rows.first;
    final totalIn = (row['total_in'] as num).toDouble();
    final totalOut = (row['total_out'] as num).toDouble();
    return {'totalIn':totalIn,'totalOut':totalOut,'balance':totalIn-totalOut};
  }

  Future<List<Map<String, Object?>>> cashTransactions({required int actorUserId, int limit = 100}) async {
    final db = await database;
    await _requireAdmin(db, actorUserId);
    return db.query('cash_transactions', orderBy:'created_at DESC,id DESC', limit:limit);
  }

  Future<double> supplierBalance({required int actorUserId, required int supplierId}) async {
    final db = await database;
    await _requireAdmin(db, actorUserId);
    final rows = await db.rawQuery("SELECT COALESCE(SUM(debit-credit),0) AS due FROM supplier_ledger WHERE supplier_id=?", [supplierId]);
    return (rows.first['due'] as num).toDouble();
  }
  Future<Map<String,double>> profitAndLoss({required int actorUserId}) async {
    final db=await database; await _requireAdmin(db,actorUserId);
    final rows=await db.rawQuery("SELECT COALESCE(SUM(CASE WHEN a.code='SALES' THEN l.credit-l.debit ELSE 0 END),0) AS revenue,COALESCE(SUM(CASE WHEN a.code='COGS' THEN l.debit-l.credit ELSE 0 END),0) AS cogs,COALESCE(SUM(CASE WHEN a.code='EXPENSE' THEN l.debit-l.credit ELSE 0 END),0) AS expenses FROM journal_lines l JOIN accounts a ON a.id=l.account_id");
    final row=rows.first; final revenue=(row['revenue'] as num).toDouble(); final cogs=(row['cogs'] as num).toDouble(); final expenses=(row['expenses'] as num).toDouble();
    return {'revenue':revenue,'cogs':cogs,'grossProfit':revenue-cogs,'expenses':expenses,'netProfit':revenue-cogs-expenses};
  }
  Future<Map<String,double>> journalTotals({required int actorUserId}) async {
    final db=await database; await _requireAdmin(db,actorUserId);
    final rows=await db.rawQuery('SELECT COALESCE(SUM(debit),0) AS debit,COALESCE(SUM(credit),0) AS credit FROM journal_lines');
    return {'debit':(rows.first['debit'] as num).toDouble(),'credit':(rows.first['credit'] as num).toDouble()};
  }

  Future<List<Map<String,Object?>>> accountBalances({required int actorUserId}) async {
    final db=await database; await _requireAdmin(db,actorUserId);
    return db.rawQuery("SELECT a.code,a.name_ar,a.account_type,COALESCE(SUM(l.debit),0) AS debit,COALESCE(SUM(l.credit),0) AS credit,CASE WHEN a.account_type IN ('asset','expense') THEN COALESCE(SUM(l.debit-l.credit),0) ELSE COALESCE(SUM(l.credit-l.debit),0) END AS balance FROM accounts a LEFT JOIN journal_lines l ON l.account_id=a.id WHERE a.is_active=1 GROUP BY a.id ORDER BY a.code");
  }

  Future<List<Map<String,Object?>>> recentJournalEntries({required int actorUserId,int limit=30}) async {
    final db=await database; await _requireAdmin(db,actorUserId);
    return db.rawQuery('SELECT e.*,COALESCE(SUM(l.debit),0) AS debit,COALESCE(SUM(l.credit),0) AS credit FROM journal_entries e JOIN journal_lines l ON l.entry_id=e.id GROUP BY e.id ORDER BY e.id DESC LIMIT ?', [limit]);
  }
  Future<void> rejectPurchaseReceipt({required int actorUserId,required int receiptId,required String reason}) async {
    if(reason.trim().isEmpty) throw ArgumentError('سبب رفض الاستلام مطلوب');
    final db=await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx,actorUserId);
      final rows=await tx.query('purchase_receipts',where:"id=? AND status='submitted'",whereArgs:[receiptId],limit:1);
      if(rows.isEmpty) throw StateError('فاتورة التوريد غير معلقة');
      final now=DateTime.now().toUtc().toIso8601String();
      final lines=await tx.query('purchase_receipt_lines',where:'receipt_id=?',whereArgs:[receiptId]);
      for(final line in lines){
        final pid=line['product_id'] as int; final qty=(line['received_qty'] as num).toDouble();
        final balances=await tx.query('stock_balances',where:'product_id=?',whereArgs:[pid],limit:1);
        if(balances.isNotEmpty){
          final pendingQty=(balances.first['unapproved_qty'] as num).toDouble();
          if(pendingQty<qty) throw StateError('كمية الاستلام المعلقة لا تطابق الفاتورة');
          final onHand=(balances.first['on_hand'] as num).toDouble();
          if(onHand<qty) throw StateError('الرصيد الفعلي المعلق لا يطابق فاتورة الاستلام');
          await tx.update('stock_balances',{'on_hand':onHand-qty,'unapproved_qty':pendingQty-qty,'updated_at':now},where:'product_id=?',whereArgs:[pid]);
          final lineId=line['id'] as int;
          await tx.insert('stock_movements',{'product_id':pid,'movement_type':'purchase_rejected','quantity_delta':-qty,'source_type':'purchase_receipt','source_id':receiptId,'idempotency_key':'purchase-rejected:'+receiptId.toString()+':'+lineId.toString(),'actor_user_id':actorUserId,'note':reason.trim(),'occurred_at':now});
        }
      }
      await tx.update('purchase_receipts',{'status':'rejected','reviewed_by':actorUserId,'reviewed_at':now,'review_note':reason.trim()},where:'id=?',whereArgs:[receiptId]);
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'purchase_receipt_rejected','entity_type':'purchase_receipt','entity_id':receiptId,'details':reason.trim(),'created_at':now});
    });
  }
  Future<List<Map<String,Object?>>> supplierStatement({required int actorUserId,required int supplierId}) async {
    final db=await database; await _requireAdmin(db,actorUserId);
    return db.query('supplier_ledger',where:'supplier_id=?',whereArgs:[supplierId],orderBy:'created_at,id');
  }

  Future<List<Map<String,Object?>>> recipeProducts({required int actorUserId}) async {
    final db=await database;await _requireAdmin(db,actorUserId);
    return db.rawQuery("SELECT id,name_ar,base_unit FROM products WHERE is_active=1 AND is_sellable=1 ORDER BY name_ar");
  }
  Future<List<Map<String,Object?>>> ingredientProducts({required int actorUserId}) async {
    final db=await database;await _requireAdmin(db,actorUserId);
    return db.rawQuery("SELECT p.id,p.name_ar,p.base_unit,COALESCE(b.approved_qty,0) AS available_qty FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id WHERE p.is_active=1 AND p.is_stock_item=1 ORDER BY p.name_ar");
  }
  Future<List<Map<String,Object?>>> recipeLines({required int actorUserId,required int productId}) async {
    final db=await database;await _requireAdmin(db,actorUserId);
    return db.rawQuery("SELECT rl.*,p.name_ar FROM recipes r JOIN recipe_lines rl ON rl.recipe_id=r.id JOIN products p ON p.id=rl.ingredient_product_id WHERE r.product_id=? AND r.is_active=1 ORDER BY rl.id",[productId]);
  }
  Future<void> saveRecipe({required int actorUserId,required int productId,required List<Map<String,Object?>> lines}) async {
    if(lines.isEmpty)throw ArgumentError('الوصفة يجب أن تحتوي على مكون واحد على الأقل');
    final db=await database;
    await db.transaction((tx) async {
      await _requireAdmin(tx,actorUserId);
      final meal=await tx.query('products',columns:['id','is_sellable'],where:'id=? AND is_active=1',whereArgs:[productId],limit:1);
      if(meal.isEmpty||meal.first['is_sellable']!=1)throw StateError('اختر وجبة مفعلة للبيع');
      final normalized=<int,Map<String,Object?>>{};
      for(final l in lines){
        final id=l['productId'] as int;final q=(l['quantity'] as num).toDouble();
        if(id==productId||!q.isFinite||q<=0)throw ArgumentError('مكون الوصفة أو كميته غير صحيح');
        final ingredient=await tx.query('products',columns:['id','base_unit'],where:'id=? AND is_active=1 AND is_stock_item=1',whereArgs:[id],limit:1);
        if(ingredient.isEmpty)throw StateError('أحد مكونات الوصفة غير موجود');
        if(normalized.containsKey(id))throw ArgumentError('لا تكرر المكون نفسه في الوصفة');
        normalized[id]={'productId':id,'quantity':q,'unit':ingredient.first['base_unit']};
      }
      final now=DateTime.now().toUtc().toIso8601String();
      final existing=await tx.query('recipes',columns:['id','version'],where:'product_id=?',whereArgs:[productId],limit:1);
      int recipeId;int version;
      if(existing.isEmpty){recipeId=await tx.insert('recipes',{'product_id':productId,'version':1,'is_active':1,'created_at':now,'updated_at':now});version=1;}
      else{recipeId=existing.first['id'] as int;version=(existing.first['version'] as int)+1;await tx.update('recipes',{'version':version,'is_active':1,'updated_at':now},where:'id=?',whereArgs:[recipeId]);await tx.delete('recipe_lines',where:'recipe_id=?',whereArgs:[recipeId]);}
      for(final l in normalized.values){await tx.insert('recipe_lines',{'recipe_id':recipeId,'ingredient_product_id':l['productId'],'quantity_per_meal':l['quantity'],'unit_snapshot':l['unit']});}
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'recipe_saved','entity_type':'recipe','entity_id':recipeId,'details':'Saved recipe version '+version.toString()+' for product '+productId.toString(),'created_at':now});
    });
  }
  Future<List<Map<String,Object?>>> kitchenOrders({required int actorUserId}) async {
    final db=await database;
    final a=await db.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
    if(a.isEmpty||a.first['is_active']!=1||!['admin','cashier','storekeeper','kitchen'].contains(a.first['role']))throw StateError('ليس لديك صلاحية شاشة المطبخ');
    return db.rawQuery("SELECT k.id AS kitchen_order_id,k.status,k.created_at,s.invoice_no,s.id AS sale_id FROM kitchen_orders k JOIN sales s ON s.id=k.sale_id WHERE s.status='posted' ORDER BY CASE k.status WHEN 'new' THEN 0 WHEN 'preparing' THEN 1 WHEN 'ready' THEN 2 ELSE 3 END,k.id");
  }
  Future<List<Map<String,Object?>>> kitchenOrderLines({required int actorUserId,required int kitchenOrderId}) async {
    final db=await database;
    final a=await db.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
    if(a.isEmpty||a.first['is_active']!=1||!['admin','cashier','storekeeper','kitchen'].contains(a.first['role']))throw StateError('ليس لديك صلاحية شاشة المطبخ');
    return db.rawQuery("SELECT sl.id AS sale_line_id,sl.product_id,sl.unit_price,sl.product_name_snapshot,sl.quantity,sl.unit_snapshot FROM kitchen_order_lines kl JOIN sale_lines sl ON sl.id=kl.sale_line_id WHERE kl.kitchen_order_id=? ORDER BY kl.id",[kitchenOrderId]);
  }
  Future<void> updateKitchenOrderStatus({required int actorUserId,required int kitchenOrderId,required String status}) async {
    if(!['preparing','ready'].contains(status))throw ArgumentError('حالة المطبخ غير صالحة');
    final db=await database;
    await db.transaction((tx) async {
      final a=await tx.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
      if(a.isEmpty||a.first['is_active']!=1||!['admin','cashier','storekeeper','kitchen'].contains(a.first['role']))throw StateError('ليس لديك صلاحية تحديث حالة المطبخ');
      final rows=await tx.query('kitchen_orders',where:"id=? AND status IN ('new','preparing')",whereArgs:[kitchenOrderId],limit:1);
      if(rows.isEmpty)throw StateError('الطلب غير موجود أو لا يقبل هذا التغيير');
      final now=DateTime.now().toUtc().toIso8601String();
      await tx.update('kitchen_orders',{'status':status,'updated_at':now},where:'id=?',whereArgs:[kitchenOrderId]);
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'kitchen_status_changed','entity_type':'kitchen_order','entity_id':kitchenOrderId,'details':'Kitchen status changed to '+status,'created_at':now});
    });
  }

  Future<void> updateKitchenOrderQuantities({required int actorUserId, required int kitchenOrderId, required Map<int,double> quantities}) async {
    if (quantities.isEmpty || quantities.values.any((q) => !q.isFinite || q < 0)) {
      throw ArgumentError('أدخل كميات صحيحة غير سالبة');
    }
    final db = await database;
    await db.transaction((tx) async {
      final actors = await tx.query('users', columns: ['role','is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
      if (actors.isEmpty || actors.first['is_active'] != 1 || !['admin','cashier'].contains(actors.first['role'])) {
        throw StateError('تعديل طلب المطبخ متاح للمدير والكاشير فقط');
      }
      final orders = await tx.rawQuery("SELECT k.*,s.id AS sale_id,s.status AS sale_status,s.subtotal,s.discount,s.paid,s.total FROM kitchen_orders k JOIN sales s ON s.id=k.sale_id WHERE k.id=? AND k.status IN ('new','preparing') AND s.status='posted'", [kitchenOrderId]);
      if (orders.isEmpty) throw StateError('الطلب غير موجود أو بدأ تجهيزه النهائي ولا يقبل التعديل');
      final order = orders.first;
      final saleId = order['sale_id'] as int;
      final linked = await tx.rawQuery('SELECT sl.* FROM kitchen_order_lines kl JOIN sale_lines sl ON sl.id=kl.sale_line_id WHERE kl.kitchen_order_id=?', [kitchenOrderId]);
      if (linked.isEmpty || linked.any((l) => !quantities.containsKey(l['id'] as int))) {
        throw StateError('يجب إرسال الكمية الجديدة لكل وجبة في الطلب');
      }
      if (quantities.values.every((q) => q == 0)) throw StateError('لا يمكن جعل جميع كميات الطلب صفراً؛ استخدم إلغاء الفاتورة');
      final now = DateTime.now().toUtc().toIso8601String();
      final editToken = DateTime.now().microsecondsSinceEpoch.toString();
      double subtotal = (order['subtotal'] as num).toDouble();
      for (final line in linked) {
        final lineId = line['id'] as int;
        final oldQty = (line['quantity'] as num).toDouble();
        final newQty = quantities[lineId]!;
        final productId = line['product_id'] as int;
        final components = await tx.query('sale_recipe_components', where: 'sale_line_id=?', whereArgs: [lineId]);
        if (components.isEmpty) {
          final productRows=await tx.query('products',columns:['is_stock_item'],where:'id=?',whereArgs:[productId],limit:1);
          final isStockItem=productRows.isNotEmpty && productRows.first['is_stock_item']==1;
          final delta = newQty - oldQty;
          if (isStockItem && delta > 0) {
            final changed = await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand-?,approved_qty=approved_qty-?,updated_at=? WHERE product_id=? AND approved_qty>=?', [delta,delta,now,productId,delta]);
            if (changed != 1) throw StateError('المخزون غير كافٍ لزيادة الصنف رقم $productId');
          } else if (isStockItem && delta < 0) {
            await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand+?,approved_qty=approved_qty+?,updated_at=? WHERE product_id=?', [-delta,-delta,now,productId]);
          }
          if (isStockItem && delta != 0) {
            await tx.insert('stock_movements', {'product_id':productId,'movement_type':delta > 0 ? 'sale_edit_consumption' : 'sale_edit_return','quantity_delta':-delta,'source_type':'sale_edit','source_id':saleId,'idempotency_key':'sale-edit:$editToken:$lineId:$productId','actor_user_id':actorUserId,'note':'Kitchen order quantity adjustment','occurred_at':now});
          }
        } else {
          for (final component in components) {
            final ingredientId = component['ingredient_product_id'] as int;
            final oldComponentQty = (component['quantity'] as num).toDouble();
            final perMeal = oldComponentQty / oldQty;
            final newComponentQty = perMeal * newQty;
            final delta = newComponentQty - oldComponentQty;
            if (delta > 0) {
              final changed = await tx.rawUpdate('UPDATE kitchen_stock_balances SET quantity=quantity-?,updated_at=? WHERE product_id=? AND quantity>=?', [delta,now,ingredientId,delta]);
              if (changed != 1) throw StateError('عهدة المطبخ غير كافية لزيادة مكون الوجبة: '+component['ingredient_name_snapshot'].toString());
            } else if (delta < 0) {
              await tx.rawInsert('INSERT INTO kitchen_stock_balances(product_id,quantity,weighted_average_cost,updated_at) VALUES(?,?,?,?) ON CONFLICT(product_id) DO UPDATE SET quantity=quantity+excluded.quantity,weighted_average_cost=CASE WHEN quantity+excluded.quantity<=0 THEN 0 ELSE ((quantity*weighted_average_cost)+(excluded.quantity*excluded.weighted_average_cost))/(quantity+excluded.quantity) END,updated_at=excluded.updated_at',[ingredientId,-delta,(component['unit_cost_snapshot'] as num).toDouble(),now]);
            }
            if (delta != 0) {
              await tx.insert('kitchen_stock_movements', {'product_id':ingredientId,'movement_type':delta > 0 ? 'recipe_edit_consumption' : 'recipe_edit_return','quantity_delta':-delta,'source_type':'sale_edit','source_id':saleId,'idempotency_key':'kitchen-sale-edit:$editToken:$lineId:$ingredientId','actor_user_id':actorUserId,'note':'Recipe component delta for kitchen order','created_at':now});
              if (newQty > 0) await tx.update('sale_recipe_components', {'quantity':newComponentQty}, where:'id=?', whereArgs:[component['id']]);
            }
          }
        }
        final price = (line['unit_price'] as num).toDouble();
        double newCostTotal=0;
        if(newQty>0){
          if(components.isEmpty){
            final oldCost=(line['cost_total'] as num?)?.toDouble()??0;
            newCostTotal=oldQty==0?0:(oldCost/oldQty)*newQty;
          }else{
            final refreshed=await tx.query('sale_recipe_components',where:'sale_line_id=?',whereArgs:[lineId]);
            newCostTotal=refreshed.fold<double>(0,(sum,component)=>sum+(component['quantity'] as num).toDouble()*(component['unit_cost_snapshot'] as num).toDouble());
          }
        }
        final lineTotal = newQty * price;
        subtotal += lineTotal - (oldQty * price);
        if (newQty == 0) {
          await tx.delete('kitchen_order_lines', where:'kitchen_order_id=? AND sale_line_id=?', whereArgs:[kitchenOrderId,lineId]);
          await tx.delete('sale_recipe_components', where:'sale_line_id=?', whereArgs:[lineId]);
          await tx.delete('sale_lines', where:'id=?', whereArgs:[lineId]);
        } else {
          await tx.update('sale_lines', {'quantity':newQty,'line_total':lineTotal,'cost_total':newCostTotal}, where:'id=?', whereArgs:[lineId]);
        }
      }
      final discount = (order['discount'] as num).toDouble();
      final paid = (order['paid'] as num).toDouble();
      final total = subtotal - discount;
      if (discount > subtotal || paid > total) throw StateError('التعديل يجعل المدفوع أكبر من إجمالي الفاتورة؛ يلزم تسوية مالية من المدير أولاً');
      final saleLines=await tx.query('sale_lines',columns:['cost_total'],where:'sale_id=?',whereArgs:[saleId]);
      final newCostTotal=saleLines.fold<double>(0,(sum,line)=>(sum+(line['cost_total'] as num).toDouble()));
      await _postSaleJournalAdjustment(tx,actorUserId:actorUserId,saleId:saleId,adjustmentId:int.parse(editToken),paid:paid,total:total,costTotal:newCostTotal);
      await tx.update('sales', {'subtotal':subtotal,'total':total,'balance':total-paid}, where:'id=?', whereArgs:[saleId]);
      await tx.update('kitchen_orders', {'updated_at':now}, where:'id=?', whereArgs:[kitchenOrderId]);
      await tx.insert('audit_logs', {'actor_user_id':actorUserId,'action':'kitchen_order_quantities_updated','entity_type':'kitchen_order','entity_id':kitchenOrderId,'details':'Updated quantities; invoice $saleId; subtotal=$subtotal; total=$total','created_at':now});
    });
  }

  Future<void> voidSale({required int actorUserId,required int saleId,required String reason}) async {
    if(reason.trim().isEmpty)throw ArgumentError('سبب إلغاء الفاتورة إلزامي');
    final db=await database;
    await db.transaction((tx) async {
      final actor=await tx.query('users',columns:['role','is_active'],where:'id=?',whereArgs:[actorUserId],limit:1);
      if(actor.isEmpty||actor.first['is_active']!=1||!['admin','cashier'].contains(actor.first['role']))throw StateError('ليس لديك صلاحية إلغاء الفاتورة');
      final rows=await tx.query('sales',where:"id=? AND status='posted'",whereArgs:[saleId],limit:1);
      if(rows.isEmpty)throw StateError('الفاتورة غير موجودة أو ملغاة مسبقاً');
      final sale=rows.first;
      final kitchenRows=await tx.query('kitchen_orders',columns:['status'],where:'sale_id=?',whereArgs:[saleId],limit:1);
      if(kitchenRows.isNotEmpty && kitchenRows.first['status']!='new') {
        throw StateError('لا يمكن إلغاء الفاتورة بعد بدء التحضير؛ سجل الاستهلاك أو الهدر والإرجاع أولاً');
      }
      final paid=(sale['paid'] as num).toDouble();
      if(paid>0&&actor.first['role']!='admin')throw StateError('الفاتورة مدفوعة؛ يلزم اعتماد المدير وتسجيل الاسترداد');
      final now=DateTime.now().toUtc().toIso8601String();
      if(paid>0){
        final cashRows=await tx.rawQuery("SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS balance FROM cash_transactions");
        final cashBalance=(cashRows.first['balance'] as num).toDouble();
        if(paid>cashBalance)throw StateError('رصيد الصندوق غير كافٍ لتنفيذ الاسترداد. المتاح: '+cashBalance.toString());
        await tx.insert('sale_refunds',{'sale_id':saleId,'amount':paid,'reason':reason.trim(),'approved_by':actorUserId,'created_at':now});
        await tx.insert('cash_transactions',{'direction':'out','category':'sale_refund','amount':paid,'payment_method':'cash','source_type':'sale_refund','source_id':saleId,'idempotency_key':'cash:sale-refund:'+saleId.toString(),'note':reason.trim(),'actor_user_id':actorUserId,'created_at':now});
      }
      await _reverseJournal(tx,actorUserId:actorUserId,sourceType:'sale',sourceId:saleId,reverseSourceType:'sale_void',reverseSourceId:saleId,description:'عكس قيد فاتورة ملغاة: '+reason.trim());
      final lines=await tx.query('sale_lines',where:'sale_id=?',whereArgs:[saleId]);
      for(final line in lines){
        final lineId=line['id'] as int;final productId=line['product_id'] as int;
        final components=await tx.query('sale_recipe_components',where:'sale_line_id=?',whereArgs:[lineId]);
        if(components.isNotEmpty){
          for(final c in components){
            final pid=c['ingredient_product_id'] as int;final qty=(c['quantity'] as num).toDouble();
            await tx.rawInsert('INSERT INTO kitchen_stock_balances(product_id,quantity,weighted_average_cost,updated_at) VALUES(?,?,?,?) ON CONFLICT(product_id) DO UPDATE SET quantity=quantity+excluded.quantity,weighted_average_cost=CASE WHEN quantity+excluded.quantity<=0 THEN 0 ELSE ((quantity*weighted_average_cost)+(excluded.quantity*excluded.weighted_average_cost))/(quantity+excluded.quantity) END,updated_at=excluded.updated_at',[pid,qty,(c['unit_cost_snapshot'] as num).toDouble(),now]);
            await tx.insert('kitchen_stock_movements',{'product_id':pid,'movement_type':'sale_void_return','quantity_delta':qty,'source_type':'sale_void','source_id':saleId,'idempotency_key':'kitchen-sale-void:$saleId:$lineId:$pid','actor_user_id':actorUserId,'note':'Return recipe components to kitchen custody: '+reason.trim(),'created_at':now});
          }
        }else{
          final productRows=await tx.query('products',columns:['is_stock_item'],where:'id=?',whereArgs:[productId],limit:1);
          if(productRows.isNotEmpty && productRows.first['is_stock_item']==1){
            final qty=(line['quantity'] as num).toDouble();
            await tx.insert('stock_movements',{'product_id':productId,'movement_type':'sale_void_return','quantity_delta':qty,'source_type':'sale_void','source_id':saleId,'idempotency_key':'sale-void:$saleId:$lineId:$productId','actor_user_id':actorUserId,'note':'Return sold item: '+reason.trim(),'occurred_at':now});
            await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand+?,approved_qty=approved_qty+?,updated_at=? WHERE product_id=?',[qty,qty,now,productId]);
          }
        }
      }
      await tx.update('sales',{'status':'voided','balance':0},where:'id=?',whereArgs:[saleId]);
      await tx.update('kitchen_orders',{'status':'cancelled','updated_at':now},where:'sale_id=?',whereArgs:[saleId]);
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'sale_voided','entity_type':'sale','entity_id':saleId,'details':'Reason: '+reason.trim()+'; refunded='+paid.toString(),'created_at':now});
    });
  }

}
