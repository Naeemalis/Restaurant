import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/data/app_database.dart';
import '../lib/data/inventory_service.dart';
import '../lib/data/inventory_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('two sample meals consume recipe stock once and post balanced COGS', () async {
    final app = AppDatabase.instance;
    await app.closeForTesting();
    final dbPath = p.join(await getDatabasesPath(), 'naeemsoft_restaurant.db');
    await deleteDatabase(dbPath);

    await app.ensureDefaultAdmin();
    final defaultAdmin = await app.login('admin', '123456');
    expect(defaultAdmin, isNotNull);
    expect(defaultAdmin!['role'], 'admin');
    expect(defaultAdmin['must_change_pin'], 1);
    await app.changeOwnPin(userId: defaultAdmin['id'] as int, newPin: '654321');
    final changedLogin = await app.login('admin', '654321');
    expect(changedLogin?['must_change_pin'], 0);
    final adminId = defaultAdmin['id'] as int;
    Future<int> addIngredient(String ar, String en, String fr, String unit, double qty, double cost) async {
      final id = await app.saveCatalogProduct(actorUserId: adminId, names: {'ar': ar, 'en': en, 'fr': fr}, baseUnit: unit, productType: 'ingredient', categoryId: null);
      await (await app.database).update('stock_balances', {'on_hand': qty, 'approved_qty': qty, 'weighted_average_cost': cost, 'updated_at': DateTime.now().toUtc().toIso8601String()}, where: 'product_id=?', whereArgs: [id]);
      return id;
    }

    final rice = await addIngredient('أرز', 'Rice', 'Riz', 'kg', 100, 20);
    final chicken = await addIngredient('دجاج', 'Chicken', 'Poulet', 'kg', 50, 200);
    final onion = await addIngredient('بصل', 'Onion', 'Oignon', 'kg', 20, 30);
    final beef = await addIngredient('لحم بقري', 'Beef', 'Boeuf', 'kg', 40, 500);

    final chickenMeal = await app.saveCatalogProduct(actorUserId: adminId, names: {'ar': 'كبسة دجاج', 'en': 'Chicken Kabsa', 'fr': 'Kabsa au poulet'}, baseUnit: 'وجبة', productType: 'sellable', categoryId: null, salePrice: 700);
    final beefMeal = await app.saveCatalogProduct(actorUserId: adminId, names: {'ar': 'لحم مشوي مع الأرز', 'en': 'Grilled Beef with Rice', 'fr': 'Boeuf grille avec riz'}, baseUnit: 'وجبة', productType: 'sellable', categoryId: null, salePrice: 1200);

    await app.saveRecipe(actorUserId: adminId, productId: chickenMeal, lines: [
      {'productId': rice, 'quantity': 0.25},
      {'productId': chicken, 'quantity': 0.30},
      {'productId': onion, 'quantity': 0.05},
    ]);
    await app.saveRecipe(actorUserId: adminId, productId: beefMeal, lines: [
      {'productId': beef, 'quantity': 0.25},
      {'productId': rice, 'quantity': 0.15},
      {'productId': onion, 'quantity': 0.03},
    ]);

    // Start-of-day stock preparation: transfer ingredients from the main store
    // into the kitchen's custody before the first meal can be sold.
    final db = await app.database;
    await InventorySchema.ensure(db);
    for (final item in <Map<String,Object>>[
      {'id':rice,'qty':100.0},{'id':chicken,'qty':50.0},
      {'id':onion,'qty':20.0},{'id':beef,'qty':40.0},
    ]) {
      final requestId=await InventoryService.submitIssueRequest(
        db,actorUserId:adminId,destination:'المطبخ',destinationType:'kitchen',
        reason:'تجهيز بداية اليوم',receiverName:'مسؤول المطبخ',
        quantities:{item['id'] as int:item['qty'] as double},
      );
      final issueLine=(await InventoryService.issueLines(db,actorUserId:adminId,requestId:requestId)).single;
      await InventoryService.approveAndIssue(db,actorUserId:adminId,requestId:requestId,
        issueQuantities:{issueLine['id'] as int:item['qty'] as double});
    }

    final saleId = await app.createSale(actorUserId: adminId, lines: [
      {'productId': chickenMeal, 'quantity': 1.0, 'unitPrice': 700.0},
      {'productId': beefMeal, 'quantity': 1.0, 'unitPrice': 1200.0},
    ], paid: 1900.0);

    final mainStock = await db.query('stock_balances');
    double mainAvailable(int id) => (mainStock.firstWhere((r) => r['product_id'] == id)['approved_qty'] as num).toDouble();
    expect(mainAvailable(rice), 0.0);
    expect(mainAvailable(chicken), 0.0);
    expect(mainAvailable(onion), 0.0);
    expect(mainAvailable(beef), 0.0);
    final kitchenStock=await db.query('kitchen_stock_balances');
    double kitchenAvailable(int id)=>(kitchenStock.firstWhere((r)=>r['product_id']==id)['quantity'] as num).toDouble();
    expect(kitchenAvailable(rice), closeTo(99.60, 0.000001));
    expect(kitchenAvailable(chicken), closeTo(49.70, 0.000001));
    expect(kitchenAvailable(onion), closeTo(19.92, 0.000001));
    expect(kitchenAvailable(beef), closeTo(39.75, 0.000001));

    final visibleIngredients = await app.ingredientProducts(actorUserId: adminId);
    expect(visibleIngredients.length, 4, reason: 'الوجبات المباعة لا تظهر ضمن مواد المخزون');
    final components = await db.rawQuery('SELECT COUNT(*) AS n FROM sale_recipe_components WHERE sale_line_id IN (SELECT id FROM sale_lines WHERE sale_id=?)', [saleId]);
    expect(components.first['n'], 6);
    final kitchen = await db.query('kitchen_orders', where: 'sale_id=?', whereArgs: [saleId]);
    expect(kitchen.length, 1);
    final kitchenLines = await db.query('kitchen_order_lines', where: 'kitchen_order_id=?', whereArgs: [kitchen.first['id']]);
    expect(kitchenLines.length, 2);

    final pnl = await app.profitAndLoss(actorUserId: adminId);
    expect(pnl['revenue'], closeTo(1900.0, 0.000001));
    expect(pnl['cogs'], closeTo(195.4, 0.000001));
    expect(pnl['grossProfit'], closeTo(1704.6, 0.000001));
    final totals = await app.journalTotals(actorUserId: adminId);
    expect(totals['debit'], closeTo(totals['credit']!, 0.000001));

    // Editing a kitchen ticket consumes the additional recipe quantities from
    // kitchen custody, never from the already-depleted main store.
    final saleLines=await db.query('sale_lines',where:'sale_id=?',whereArgs:[saleId]);
    final editedQuantities=<int,double>{
      for(final line in saleLines)
        line['id'] as int: (line['product_id']==chickenMeal ? 2.0 : 1.0),
    };
    await app.updateKitchenOrderQuantities(actorUserId:adminId,kitchenOrderId:kitchen.single['id'] as int,quantities:editedQuantities);
    final kitchenAfterEdit=await db.query('kitchen_stock_balances');
    double kitchenAfterEditQty(int id)=>(kitchenAfterEdit.firstWhere((r)=>r['product_id']==id)['quantity'] as num).toDouble();
    expect(kitchenAfterEditQty(rice),closeTo(99.35,0.000001));
    expect(kitchenAfterEditQty(chicken),closeTo(49.40,0.000001));
    expect(kitchenAfterEditQty(onion),closeTo(19.87,0.000001));
    expect(kitchenAfterEditQty(beef),closeTo(39.75,0.000001));
    final mainAfterEdit=await db.query('stock_balances');
    expect(mainAfterEdit.every((r)=>(r['approved_qty'] as num).toDouble()==0.0),isTrue);

    // Voiding the sale restores recipe materials to kitchen custody, not to
    // the main store a second time.
    await app.voidSale(actorUserId:adminId,saleId:saleId,reason:'اختبار عكس فاتورة المطبخ');
    final kitchenAfterVoid=await db.query('kitchen_stock_balances');
    double kitchenAfterVoidQty(int id)=>(kitchenAfterVoid.firstWhere((r)=>r['product_id']==id)['quantity'] as num).toDouble();
    expect(kitchenAfterVoidQty(rice),closeTo(100.0,0.000001));
    expect(kitchenAfterVoidQty(chicken),closeTo(50.0,0.000001));
    expect(kitchenAfterVoidQty(onion),closeTo(20.0,0.000001));
    expect(kitchenAfterVoidQty(beef),closeTo(40.0,0.000001));
    final mainAfterVoid=await db.query('stock_balances');
    expect(mainAfterVoid.every((r)=>(r['approved_qty'] as num).toDouble()==0.0),isTrue);

    await expectLater(() => app.createSale(actorUserId: adminId, lines: [
      {'productId': chickenMeal, 'quantity': 1000.0, 'unitPrice': 700.0},
    ], paid: 700000.0), throwsA(anything));
    final saleCountRows = await db.rawQuery('SELECT COUNT(*) AS n FROM sales');
    final saleCount = (saleCountRows.first['n'] as num).toInt();
    expect(saleCount, 1, reason: 'الفشل بسبب نقص المخزون يجب أن يتراجع بالكامل دون إنشاء فاتورة');
    await app.closeForTesting();
    await deleteDatabase(dbPath);
  });
  test('prepared non-stock menu items route to kitchen while ready drinks do not', () async {
    final app=AppDatabase.instance;
    await app.closeForTesting();
    final path=p.join(await getDatabasesPath(),'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin=await app.login('admin','123456');
    final adminId=admin!['id'] as int;
    final preparedMeal=await app.saveCatalogProduct(
      actorUserId:adminId,names:{'ar':'ساندويتش جاهز للتحضير','en':'Prepared sandwich','fr':'Sandwich à préparer'},
      baseUnit:'قطعة',productType:'sellable',categoryId:null,salePrice:250,preparationRequired:true,
    );
    final readyDrink=await app.saveCatalogProduct(
      actorUserId:adminId,names:{'ar':'ماء','en':'Water','fr':'Eau'},
      baseUnit:'زجاجة',productType:'sellable',categoryId:null,salePrice:50,
    );
    final products=await app.sellableProducts(actorUserId:adminId);
    final prepared=products.firstWhere((p)=>p['id']==preparedMeal);
    expect(prepared['is_stock_item'],0);
    expect(prepared['preparation_required'],1);
    expect(prepared['on_hand'],isNull);
    final saleId=await app.createSale(actorUserId:adminId,lines:[
      {'productId':preparedMeal,'quantity':2.0,'unitPrice':250.0},
      {'productId':readyDrink,'quantity':1.0,'unitPrice':50.0},
    ],paid:550.0);
    final orders=await (await app.database).query('kitchen_orders',where:'sale_id=?',whereArgs:[saleId]);
    expect(orders.length,1);
    final lines=await (await app.database).query('kitchen_order_lines',where:'kitchen_order_id=?',whereArgs:[orders.single['id']]);
    expect(lines.length,1);
    final routedLine=await (await app.database).query('sale_lines',where:'id=?',whereArgs:[lines.single['sale_line_id']]);
    expect(routedLine.single['product_id'],preparedMeal);
    await app.updateKitchenOrderStatus(actorUserId:adminId,kitchenOrderId:orders.single['id'] as int,status:'preparing');
    await expectLater(()=>app.voidSale(actorUserId:adminId,saleId:saleId,reason:'إلغاء بعد بدء التحضير'),throwsA(anything));
    final stillPosted=await (await app.database).query('sales',columns:['status'],where:'id=?',whereArgs:[saleId]);
    expect(stillPosted.single['status'],'posted');
    final movements=await (await app.database).query('stock_movements',where:'source_type=? AND source_id=?',whereArgs:['sale',saleId]);
    expect(movements,isEmpty,reason:'Non-stock sellable items must not reduce store inventory');
    await app.closeForTesting();
    await deleteDatabase(path);
  });

}