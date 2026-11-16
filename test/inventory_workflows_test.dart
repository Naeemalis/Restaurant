import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/data/app_database.dart';
import '../lib/data/inventory_schema.dart';
import '../lib/data/inventory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('storekeeper issue, partial issue, return, quarantine and waste keep stock consistent', () async {
    final app = AppDatabase.instance;
    await app.closeForTesting();
    final path = p.join(await getDatabasesPath(), 'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin = await app.login('admin', '123456');
    expect(admin, isNotNull);
    final adminId = admin!['id'] as int;
    final db = await app.database;
    await InventorySchema.ensure(db);

    final productId = await app.saveCatalogProduct(
      actorUserId: adminId,
      names: {'ar': 'أرز', 'en': 'Rice', 'fr': 'Riz'},
      baseUnit: 'kg',
      productType: 'ingredient',
      categoryId: null,
    );
    await db.update('stock_balances', {
      'on_hand': 20.0,
      'approved_qty': 20.0,
      'weighted_average_cost': 5.0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'product_id=?', whereArgs: [productId]);

    final storekeeperId = await db.insert('users', {
      'username': 'storekeeper_test',
      'display_name': 'Storekeeper Test',
      'role': 'storekeeper',
      'pin_salt': 'salt',
      'pin_hash': 'hash',
      'must_change_pin': 0,
      'preferred_language': 'ar',
      'is_active': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    final storekeeperOverview=await InventoryService.stockOverview(db,actorUserId:storekeeperId);
    expect(storekeeperOverview.single.containsKey('weighted_average_cost'),isFalse,
      reason:'Storekeeper inventory queries must not retrieve valuation data');
    final adminOverview=await InventoryService.stockOverview(db,actorUserId:adminId);
    expect(adminOverview.single.containsKey('weighted_average_cost'),isFalse,
      reason:'The shared operational overview intentionally excludes financial valuation for every role');

    final requestId = await InventoryService.submitIssueRequest(
      db,
      actorUserId: storekeeperId,
      destination: 'Kitchen',
      reason: 'Daily ingredients',
      receiverName: 'Kitchen staff',
      quantities: {productId: 8.0},
    );
    var balance = (await db.query('stock_balances', where: 'product_id=?', whereArgs: [productId])).first;
    expect((balance['approved_qty'] as num).toDouble(), 20.0, reason: 'Submitting a request must not post stock movement');

    final lines = await InventoryService.issueLines(db, actorUserId: adminId, requestId: requestId);
    final lineId = lines.first['id'] as int;
    await InventoryService.approveAndIssue(db, actorUserId: adminId, requestId: requestId, issueQuantities: {lineId: 3.0});
    balance = (await db.query('stock_balances', where: 'product_id=?', whereArgs: [productId])).first;
    expect((balance['approved_qty'] as num).toDouble(), 17.0);

    final pending = await InventoryService.issueRequests(db, actorUserId: adminId, pendingOnly: true);
    expect(pending.single['status'], 'partially_issued');
    await InventoryService.approveAndIssue(db, actorUserId: adminId, requestId: requestId, issueQuantities: {lineId: 5.0});
    balance = (await db.query('stock_balances', where: 'product_id=?', whereArgs: [productId])).first;
    expect((balance['approved_qty'] as num).toDouble(), 12.0);

    await InventoryService.recordIssueReturn(
      db,
      actorUserId: storekeeperId,
      issueLineId: lineId,
      quantity: 1.0,
      condition: 'good',
      reason: 'Unused sealed bag',
      returnedBy: 'Kitchen staff',
    );
    balance = (await db.query('stock_balances', where: 'product_id=?', whereArgs: [productId])).first;
    expect((balance['approved_qty'] as num).toDouble(), 13.0);

    await InventoryService.quarantineStock(
      db,
      actorUserId: storekeeperId,
      productId: productId,
      quantity: 2.0,
      reason: 'Damaged packaging',
    );
    balance = (await db.query('stock_balances', where: 'product_id=?', whereArgs: [productId])).first;
    expect((balance['approved_qty'] as num).toDouble(), 11.0);
    final blocked = await InventoryService.quarantineRecords(db, actorUserId: adminId, blockedOnly: true);
    expect(blocked.length, 1);
    await InventoryService.resolveQuarantine(
      db,
      actorUserId: adminId,
      quarantineId: blocked.single['id'] as int,
      resolution: 'release',
      note: 'Inspected and safe',
    );
    balance = (await db.query('stock_balances', where: 'product_id=?', whereArgs: [productId])).first;
    expect((balance['approved_qty'] as num).toDouble(), 13.0);

    await InventoryService.recordWaste(
      db,
      actorUserId: storekeeperId,
      productId: productId,
      quantity: 1.5,
      reason: 'Preparation spoilage',
    );

    final secondQuarantineId = await InventoryService.quarantineStock(
      db,
      actorUserId: storekeeperId,
      productId: productId,
      quantity: 1.0,
      reason: 'Expired item',
    );
    await InventoryService.resolveQuarantine(
      db,
      actorUserId: adminId,
      quarantineId: secondQuarantineId,
      resolution: 'writeoff',
      note: 'Confirmed expired',
    );
    final inventoryJournals = await db.rawQuery(
      "SELECT source_type FROM journal_entries WHERE source_type IN ('inventory_waste','inventory_quarantine_writeoff')",
    );
    expect(inventoryJournals.length, 2);
    final journalTotals = await db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) AS debit,COALESCE(SUM(credit),0) AS credit FROM journal_lines',
    );
    expect((journalTotals.first['debit'] as num).toDouble(),
        closeTo((journalTotals.first['credit'] as num).toDouble(), 0.000001));
    balance = (await db.query('stock_balances', where: 'product_id=?', whereArgs: [productId])).first;
    expect((balance['approved_qty'] as num).toDouble(), 10.5);
    final waste = await InventoryService.wasteRecords(db, actorUserId: adminId);
    expect(waste.length, 1);

    await expectLater(
      () => InventoryService.approveAndIssue(db, actorUserId: adminId, requestId: requestId, issueQuantities: {lineId: 0.1}),
      throwsA(anything),
    );
    final movements = await db.rawQuery('SELECT COALESCE(SUM(quantity_delta),0) AS net FROM stock_movements WHERE product_id=?', [productId]);
    expect((movements.first['net'] as num).toDouble(), -9.5);
    await app.closeForTesting();
    await deleteDatabase(path);
  });

  test('storekeeper cannot approve issues or access reorder administration', () async {
    final app = AppDatabase.instance;
    await app.closeForTesting();
    final path = p.join(await getDatabasesPath(), 'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin = await app.login('admin', '123456');
    final db = await app.database;
    await InventorySchema.ensure(db);
    final storekeeperId = await db.insert('users', {
      'username': 'storekeeper_permission_test',
      'display_name': 'Storekeeper Permission Test',
      'role': 'storekeeper',
      'pin_salt': 'salt',
      'pin_hash': 'hash',
      'must_change_pin': 0,
      'preferred_language': 'ar',
      'is_active': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    final productId = await app.saveCatalogProduct(
      actorUserId: admin!['id'] as int,
      names: {'ar': 'دقيق'},
      baseUnit: 'kg',
      productType: 'ingredient',
      categoryId: null,
    );
    await expectLater(
      () => InventoryService.setReorderRule(db, actorUserId: storekeeperId, productId: productId, minimumQty: 5, reorderQty: 10),
      throwsA(anything),
    );
    await app.closeForTesting();
    await deleteDatabase(path);
  });


  test('storekeeper inventory queries never expose unit cost snapshots', () async {
    final app=AppDatabase.instance;
    await app.closeForTesting();
    final path=p.join(await getDatabasesPath(),'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin=await app.login('admin','123456');
    final adminId=admin!['id'] as int;
    final db=await app.database;
    await InventorySchema.ensure(db);
    final storekeeperId=await db.insert('users',{
      'username':'storekeeper_cost_test','display_name':'Storekeeper Cost Test','role':'storekeeper',
      'pin_salt':'salt','pin_hash':'hash','must_change_pin':0,'preferred_language':'ar',
      'is_active':1,'created_at':DateTime.now().toUtc().toIso8601String(),
    });
    final supplierId=await app.saveSupplier(actorUserId:adminId,name:'Privacy Supplier');
    final productId=await app.saveCatalogProduct(actorUserId:adminId,names:{'ar':'سكر','en':'Sugar','fr':'Sucre'},baseUnit:'kg',productType:'ingredient',categoryId:null);
    final receiptId=await app.submitPurchaseReceipt(actorUserId:adminId,supplierId:supplierId,invoiceNo:'PRIV-001',lines:[{'productId':productId,'quantity':10.0}]);
    final receiptLine=(await app.purchaseReceiptLines(actorUserId:adminId,receiptId:receiptId)).single;
    await app.approvePurchaseReceipt(actorUserId:adminId,receiptId:receiptId,unitCosts:{receiptLine['id'] as int:5.0});
    await InventoryService.submitSupplierReturn(db,actorUserId:adminId,receiptLineId:receiptLine['id'] as int,quantity:1.0,reason:'اختبار الخصوصية');
    await InventoryService.recordWaste(db,actorUserId:adminId,productId:productId,quantity:1.0,reason:'اختبار الهدر');
    await InventoryService.quarantineStock(db,actorUserId:adminId,productId:productId,quantity:1.0,reason:'اختبار الحجز');
    final supplierReturns=await InventoryService.supplierReturns(db,actorUserId:storekeeperId);
    final wastes=await InventoryService.wasteRecords(db,actorUserId:storekeeperId);
    final quarantine=await InventoryService.quarantineRecords(db,actorUserId:storekeeperId);
    expect(supplierReturns,isNotEmpty);
    expect(wastes,isNotEmpty);
    expect(quarantine,isNotEmpty);
    expect(supplierReturns.every((r)=>!r.containsKey('unit_cost_snapshot')),isTrue);
    expect(wastes.every((r)=>!r.containsKey('unit_cost_snapshot')),isTrue);
    expect(quarantine.every((r)=>!r.containsKey('unit_cost_snapshot')),isTrue);
    final adminReturns=await InventoryService.supplierReturns(db,actorUserId:adminId);
    final adminWaste=await InventoryService.wasteRecords(db,actorUserId:adminId);
    final adminQuarantine=await InventoryService.quarantineRecords(db,actorUserId:adminId);
    expect(adminReturns.single.containsKey('unit_cost_snapshot'),isTrue);
    expect(adminWaste.single.containsKey('unit_cost_snapshot'),isTrue);
    expect(adminQuarantine.single.containsKey('unit_cost_snapshot'),isTrue);
    final englishStock=await InventoryService.stockOverview(db,actorUserId:storekeeperId,language:'en');
    final frenchReturns=await InventoryService.supplierReturns(db,actorUserId:storekeeperId,language:'fr');
    expect(englishStock.single['name_ar'],'Sugar');
    expect(frenchReturns.single['name_ar'],'Sucre');
    await app.closeForTesting();
    await deleteDatabase(path);
  });

  test('pending receipt is physical but unapproved until admin decision, without double counting', () async {
    final app = AppDatabase.instance;
    await app.closeForTesting();
    final path = p.join(await getDatabasesPath(), 'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin = await app.login('admin', '123456');
    expect(admin, isNotNull);
    final adminId = admin!['id'] as int;
    final db = await app.database;
    await InventorySchema.ensure(db);
    final supplierId = await app.saveSupplier(actorUserId:adminId,name:'Test Supplier');
    final productId = await app.saveCatalogProduct(
      actorUserId:adminId,
      names:{'ar':'زيت','en':'Oil','fr':'Huile'},
      baseUnit:'L',
      productType:'ingredient',
      categoryId:null,
    );
    final receiptId = await app.submitPurchaseReceipt(
      actorUserId:adminId,supplierId:supplierId,invoiceNo:'SUP-001',
      lines:[{'productId':productId,'quantity':5.0}],
    );
    var b=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).first;
    expect((b['on_hand'] as num).toDouble(),5.0);
    expect((b['approved_qty'] as num).toDouble(),0.0);
    expect((b['unapproved_qty'] as num).toDouble(),5.0);
    expect(await db.query('supplier_ledger'),isEmpty);
    expect(await db.query('journal_entries'),isEmpty);
    final receiptLines=await app.purchaseReceiptLines(actorUserId:adminId,receiptId:receiptId);
    await app.approvePurchaseReceipt(actorUserId:adminId,receiptId:receiptId,unitCosts:{receiptLines.single['id'] as int:7.0});
    b=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).first;
    expect((b['on_hand'] as num).toDouble(),5.0,reason:'Approval must not add physical quantity twice');
    expect((b['approved_qty'] as num).toDouble(),5.0);
    expect((b['unapproved_qty'] as num).toDouble(),0.0);
    expect((b['weighted_average_cost'] as num).toDouble(),7.0);
    expect((await db.query('supplier_ledger')).length,1);
    final rejectedId=await app.submitPurchaseReceipt(actorUserId:adminId,supplierId:supplierId,invoiceNo:'SUP-002',lines:[{'productId':productId,'quantity':3.0}]);
    b=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).first;
    expect((b['on_hand'] as num).toDouble(),8.0);
    expect((b['approved_qty'] as num).toDouble(),5.0);
    expect((b['unapproved_qty'] as num).toDouble(),3.0);
    await app.rejectPurchaseReceipt(actorUserId:adminId,receiptId:rejectedId,reason:'Damaged delivery');
    b=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).first;
    expect((b['on_hand'] as num).toDouble(),5.0);
    expect((b['approved_qty'] as num).toDouble(),5.0);
    expect((b['unapproved_qty'] as num).toDouble(),0.0);
    expect((await db.query('supplier_ledger')).length,1);
    final stocktakeId=await app.submitStocktake(actorUserId:adminId,counted:{productId:4.0});
    final countLine=(await db.query('stocktake_lines',where:'stocktake_id=?',whereArgs:[stocktakeId])).single;
    expect((countLine['system_qty'] as num).toDouble(),5.0,
        reason:'Stocktake snapshot uses approved stock, not unapproved receipts');
    await app.closeForTesting();
    await deleteDatabase(path);
  });



  test('FEFO lots and supplier return keep batch, stock and supplier ledger aligned', () async {
    final app=AppDatabase.instance;
    await app.closeForTesting();
    final path=p.join(await getDatabasesPath(),'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin=await app.login('admin','123456');
    final adminId=admin!['id'] as int;
    final db=await app.database;
    await InventorySchema.ensure(db);
    final supplierId=await app.saveSupplier(actorUserId:adminId,name:'Lot Supplier');
    final productId=await app.saveCatalogProduct(actorUserId:adminId,names:{'ar':'حليب','en':'Milk','fr':'Lait'},baseUnit:'L',productType:'ingredient',categoryId:null);
    final receiptId=await app.submitPurchaseReceipt(actorUserId:adminId,supplierId:supplierId,invoiceNo:'LOT-001',lines:[{'productId':productId,'quantity':10.0}]);
    final receiptLines=await app.purchaseReceiptLines(actorUserId:adminId,receiptId:receiptId);
    final lineId=receiptLines.single['id'] as int;
    await app.approvePurchaseReceipt(actorUserId:adminId,receiptId:receiptId,unitCosts:{lineId:7.0});
    final expiry=DateTime.now().toUtc().add(const Duration(days:45)).toIso8601String().substring(0,10);
    final lotId=await InventoryService.registerLot(db,actorUserId:adminId,receiptLineId:lineId,lotCode:'MILK-A',quantity:5.0,expiryDate:expiry);
    final secondExpiry=DateTime.now().toUtc().add(const Duration(days:90)).toIso8601String().substring(0,10);
    final secondLotId=await InventoryService.registerLot(db,actorUserId:adminId,receiptLineId:lineId,lotCode:'MILK-B',quantity:5.0,expiryDate:secondExpiry);
    final initialLotMove=await db.query('inventory_lot_movements',where:'lot_id=?',whereArgs:[lotId]);
    expect(initialLotMove.length,1);
    expect((initialLotMove.single['quantity_delta'] as num).toDouble(),5.0);
    final alerts=await InventoryService.expiryAlerts(db,actorUserId:adminId,daysAhead:120);
    expect(alerts.any((x)=>x['id']==lotId),isTrue);
    await db.transaction((tx) async {
      await InventoryService.consumeLotsFefo(tx,productId:productId,quantity:2.0,actorUserId:adminId,source:'test-sale:1');
      await tx.update('stock_balances',{'on_hand':8.0,'approved_qty':8.0},where:'product_id=?',whereArgs:[productId]);
    });
    var lot=(await db.query('inventory_lots',where:'id=?',whereArgs:[lotId])).single;
    expect((lot['quantity_remaining'] as num).toDouble(),3.0);
    final returnId=await InventoryService.submitSupplierReturn(db,actorUserId:adminId,receiptLineId:lineId,lotId:lotId,quantity:0.5,reason:'جزء أول من المرتجع');
    await InventoryService.reviewSupplierReturn(db,actorUserId:adminId,returnId:returnId,approve:true,note:'اعتماد الجزء الأول');
    await expectLater(InventoryService.reviewSupplierReturn(db,actorUserId:adminId,returnId:returnId,approve:true,note:'محاولة اعتماد مكرر'),throwsStateError);
    final secondReturnId=await InventoryService.submitSupplierReturn(db,actorUserId:adminId,receiptLineId:lineId,lotId:lotId,quantity:0.5,reason:'جزء ثان من المرتجع');
    await InventoryService.reviewSupplierReturn(db,actorUserId:adminId,returnId:secondReturnId,approve:true,note:'اعتماد الجزء الثاني');
    final balance=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((balance['approved_qty'] as num).toDouble(),7.0);
    final requestId=await InventoryService.submitIssueRequest(db,actorUserId:adminId,destination:'قسم التعبئة',destinationType:'department',reason:'اختبار استعادة الدفعة',receiverName:'المستلم',quantities:{productId:1.0});
    final issueLine=(await InventoryService.issueLines(db,actorUserId:adminId,requestId:requestId)).single;
    await InventoryService.approveAndIssue(db,actorUserId:adminId,requestId:requestId,issueQuantities:{issueLine['id'] as int:1.0});
    var returnedLot=(await db.query('inventory_lots',where:'id=?',whereArgs:[lotId])).single;
    expect((returnedLot['quantity_remaining'] as num).toDouble(),1.0);
    await InventoryService.recordIssueReturn(db,actorUserId:adminId,issueLineId:issueLine['id'] as int,quantity:1.0,condition:'good',reason:'إرجاع سليم',returnedBy:'قسم التعبئة');
    returnedLot=(await db.query('inventory_lots',where:'id=?',whereArgs:[lotId])).single;
    expect((returnedLot['quantity_remaining'] as num).toDouble(),2.0);
    final restoredBalance=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((restoredBalance['approved_qty'] as num).toDouble(),7.0);
    final shrinkStocktake=await app.submitStocktake(actorUserId:adminId,counted:{productId:6.0},note:'اختبار تسوية دفعة الصلاحية');
    await app.reviewStocktake(stocktakeId:shrinkStocktake,actorUserId:adminId,approve:true,note:'اعتماد التسوية');
    returnedLot=(await db.query('inventory_lots',where:'id=?',whereArgs:[lotId])).single;
    expect((returnedLot['quantity_remaining'] as num).toDouble(),1.0);
    final surplusStocktake=await app.submitStocktake(actorUserId:adminId,counted:{productId:7.0},note:'اختبار فائض غير معرف الدفعة');
    await expectLater(app.reviewStocktake(stocktakeId:surplusStocktake,actorUserId:adminId,approve:true,note:'اعتماد الفائض'),throwsStateError);
    final afterRejectedSurplus=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((afterRejectedSurplus['approved_qty'] as num).toDouble(),6.0);
    await db.update('inventory_lots',{'expiry_date':DateTime.now().toUtc().subtract(const Duration(days:1)).toIso8601String().substring(0,10)},where:'id IN (?,?)',whereArgs:[lotId,secondLotId]);
    await expectLater(db.transaction((tx)=>InventoryService.consumeLotsFefo(tx,productId:productId,quantity:1.0,actorUserId:adminId,source:'expired-lot-test')),throwsStateError);
    final expiredLot=(await db.query('inventory_lots',where:'id=?',whereArgs:[lotId])).single;
    expect((expiredLot['quantity_remaining'] as num).toDouble(),1.0);
    final expiredSecondLot=(await db.query('inventory_lots',where:'id=?',whereArgs:[secondLotId])).single;
    expect((expiredSecondLot['quantity_remaining'] as num).toDouble(),5.0);

    lot=(await db.query('inventory_lots',where:'id=?',whereArgs:[lotId])).single;
    expect((lot['quantity_remaining'] as num).toDouble(),1.0);
    final secondLot=(await db.query('inventory_lots',where:'id=?',whereArgs:[secondLotId])).single;
    expect((secondLot['quantity_remaining'] as num).toDouble(),5.0);
    final ledger=await db.query('supplier_ledger',where:"entry_type='supplier_return'");
    expect(ledger.length,2);
    expect(ledger.fold<double>(0,(sum,row)=>sum+(row['credit'] as num).toDouble()),7.0);
    final journal=await db.rawQuery("SELECT SUM(debit) AS debit,SUM(credit) AS credit FROM journal_lines WHERE entry_id IN (SELECT id FROM journal_entries WHERE source_type='inventory_supplier_return')");
    expect((journal.single['debit'] as num).toDouble(),7.0);
    expect((journal.single['credit'] as num).toDouble(),7.0);
    await app.closeForTesting();
    await deleteDatabase(path);
  });

  test('kitchen handover does not deduct recipe stock twice', () async {
    final app=AppDatabase.instance;
    await app.closeForTesting();
    final path=p.join(await getDatabasesPath(),'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin=await app.login('admin','123456');
    final adminId=admin!['id'] as int;
    final db=await app.database;
    await InventorySchema.ensure(db);
    final productId=await app.saveCatalogProduct(actorUserId:adminId,names:{'ar':'دجاج'},baseUnit:'kg',productType:'ingredient',categoryId:null);
    await db.update('stock_balances',{'on_hand':10.0,'approved_qty':10.0,'weighted_average_cost':4.0,'updated_at':DateTime.now().toUtc().toIso8601String()},where:'product_id=?',whereArgs:[productId]);
    final storekeeperId=await db.insert('users',{
      'username':'kitchen_handover_storekeeper','display_name':'Kitchen Handover Storekeeper','role':'storekeeper',
      'pin_salt':'salt','pin_hash':'hash','must_change_pin':0,'preferred_language':'ar',
      'is_active':1,'created_at':DateTime.now().toUtc().toIso8601String(),
    });
    final requestId=await InventoryService.submitIssueRequest(
      db,actorUserId:adminId,destination:'المطبخ',destinationType:'kitchen',
      reason:'تسليم تجهيز اليوم',receiverName:'الشيف',
      quantities:{productId:4.0},
    );
    final lines=await InventoryService.issueLines(db,actorUserId:adminId,requestId:requestId);
    await InventoryService.approveAndIssue(db,actorUserId:storekeeperId,requestId:requestId,issueQuantities:{lines.single['id'] as int:4.0});
    var balance=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((balance['approved_qty'] as num).toDouble(),6.0,
      reason:'A kitchen handover transfers custody out of the main store');
    var kitchenBalance=(await db.query('kitchen_stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((kitchenBalance['quantity'] as num).toDouble(),4.0,
      reason:'The kitchen must receive the exact approved quantity');
    // Midday top-up is a second independent delivery, not an edit to the morning voucher.
    final topUpId=await InventoryService.submitIssueRequest(
      db,actorUserId:adminId,destination:'المطبخ',destinationType:'kitchen',
      reason:'نقص أثناء التشغيل',receiverName:'مسؤول المطبخ',quantities:{productId:2.0},
    );
    final topUpLine=(await InventoryService.issueLines(db,actorUserId:adminId,requestId:topUpId)).single;
    await InventoryService.approveAndIssue(db,actorUserId:storekeeperId,requestId:topUpId,
      issueQuantities:{topUpLine['id'] as int:2.0});
    balance=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    kitchenBalance=(await db.query('kitchen_stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((balance['approved_qty'] as num).toDouble(),4.0);
    expect((kitchenBalance['quantity'] as num).toDouble(),6.0,
      reason:'The midday top-up must increase kitchen custody and decrease main-store stock');
    await InventoryService.recordIssueReturn(db,actorUserId:storekeeperId,issueLineId:lines.single['id'] as int,quantity:1.0,condition:'good',reason:'Unused',returnedBy:'الشيف');
    balance=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((balance['approved_qty'] as num).toDouble(),5.0,
      reason:'Unused good materials return from kitchen custody to the main store');
    kitchenBalance=(await db.query('kitchen_stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((kitchenBalance['quantity'] as num).toDouble(),5.0);
    await InventoryService.recordIssueReturn(db,actorUserId:storekeeperId,issueLineId:lines.single['id'] as int,quantity:1.0,condition:'damaged',reason:'Damaged during preparation',returnedBy:'الشيف');
    balance=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((balance['approved_qty'] as num).toDouble(),5.0,
      reason:'Damaged kitchen stock is removed from kitchen custody, not deducted from the main store again');
    kitchenBalance=(await db.query('kitchen_stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((kitchenBalance['quantity'] as num).toDouble(),4.0);
    final blocked=await InventoryService.quarantineRecords(db,actorUserId:storekeeperId,blockedOnly:true);
    expect(blocked.length,1);
    await app.closeForTesting();
    await deleteDatabase(path);
  });

  test('product-specific purchase and issue units convert to base quantities and protect setup permissions', () async {
    final app=AppDatabase.instance;
    await app.closeForTesting();
    final path=p.join(await getDatabasesPath(),'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin=await app.login('admin','123456');
    final adminId=admin!['id'] as int;
    final db=await app.database;
    await InventorySchema.ensure(db);
    final productId=await app.saveCatalogProduct(actorUserId:adminId,names:{'ar':'أرز','en':'Rice','fr':'Riz'},baseUnit:'kg',productType:'ingredient',categoryId:null);
    final storekeeperId=await db.insert('users',{
      'username':'unit_storekeeper','display_name':'Unit Storekeeper','role':'storekeeper',
      'pin_salt':'salt','pin_hash':'hash','must_change_pin':0,'preferred_language':'ar',
      'is_active':1,'created_at':DateTime.now().toUtc().toIso8601String(),
    });
    final unitId=await InventoryService.saveProductUnit(db,actorUserId:adminId,productId:productId,
      nameAr:'جوال',nameEn:'Sack',nameFr:'Sac',conversionToBase:45,
      purchaseEnabled:true,issueEnabled:true);
    final converted=await InventoryService.toBaseQuantity(db,actorUserId:storekeeperId,
      productId:productId,quantity:25,unitId:unitId,forPurchase:true);
    expect(converted,1125);
    expect(await InventoryService.fromBaseQuantity(db,actorUserId:storekeeperId,
      productId:productId,baseQuantity:1125,unitId:unitId),25);
    final purchaseUnits=await InventoryService.productUnits(db,actorUserId:storekeeperId,
      productId:productId,forPurchase:true);
    expect(purchaseUnits.map((u)=>u['unit_name_ar']).toList(),containsAll(['kg','جوال']));
    final supplierId=await app.saveSupplier(actorUserId:adminId,name:'Package Supplier');
    final receiptId=await app.submitPurchaseReceipt(actorUserId:storekeeperId,supplierId:supplierId,invoiceNo:'PKG-45',lines:[
      {'productId':productId,'quantity':1125.0,'enteredQuantity':25.0,'enteredUnitName':'جوال','conversionToBase':45.0},
    ]);
    final receiptLines=await app.purchaseReceiptLines(actorUserId:adminId,receiptId:receiptId);
    expect(receiptLines.single['received_qty'],1125.0);
    expect(receiptLines.single['entered_qty'],25.0);
    expect(receiptLines.single['entered_unit_name'],'جوال');
    expect(receiptLines.single['conversion_to_base_snapshot'],45.0);
    final issueId=await InventoryService.submitIssueRequest(db,actorUserId:storekeeperId,destination:'Kitchen',reason:'Package issue',receiverName:'Chef',quantities:{productId:90.0},enteredQuantities:{productId:2.0},enteredUnits:{productId:'جوال'},conversionFactors:{productId:45.0});
    final issueLines=await InventoryService.issueLines(db,actorUserId:adminId,requestId:issueId);
    expect(issueLines.single['requested_qty'],90.0);
    expect(issueLines.single['entered_qty'],2.0);
    expect(issueLines.single['entered_unit_name'],'جوال');
    expect(issueLines.single['conversion_to_base_snapshot'],45.0);

    await expectLater(
      ()=>InventoryService.saveProductUnit(db,actorUserId:storekeeperId,productId:productId,
        nameAr:'صندوق',nameEn:'Box',nameFr:'Boîte',conversionToBase:12,
        purchaseEnabled:true,issueEnabled:false),
      throwsA(anything),
    );
    await expectLater(
      ()=>InventoryService.toBaseQuantity(db,actorUserId:storekeeperId,productId:productId,
        quantity:0,unitId:unitId),
      throwsA(anything),
    );
    await InventoryService.deactivateProductUnit(db,actorUserId:adminId,unitId:unitId);
    final remaining=await InventoryService.productUnits(db,actorUserId:storekeeperId,productId:productId);
    expect(remaining.length,1);
    await app.closeForTesting();
    await deleteDatabase(path);
  });

  test('FEFO consumes earliest lots, good returns restore original lots, and supplier partial returns are idempotent', () async {
    final app=AppDatabase.instance;
    await app.closeForTesting();
    final path=p.join(await getDatabasesPath(),'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin=await app.login('admin','123456');
    final adminId=admin!['id'] as int;
    final db=await app.database;
    await InventorySchema.ensure(db);
    final supplierId=await app.saveSupplier(actorUserId:adminId,name:'FEFO Supplier');
    final productId=await app.saveCatalogProduct(actorUserId:adminId,names:{'ar':'حليب','en':'Milk','fr':'Lait'},baseUnit:'L',productType:'ingredient',categoryId:null);
    final receiptId=await app.submitPurchaseReceipt(actorUserId:adminId,supplierId:supplierId,invoiceNo:'FEFO-001',lines:[{'productId':productId,'quantity':10.0}]);
    final receiptLine=(await app.purchaseReceiptLines(actorUserId:adminId,receiptId:receiptId)).single;
    await app.approvePurchaseReceipt(actorUserId:adminId,receiptId:receiptId,unitCosts:{receiptLine['id'] as int:3.0});
    final lotEarly=await InventoryService.registerLot(db,actorUserId:adminId,receiptLineId:receiptLine['id'] as int,lotCode:'MILK-EARLY',quantity:4,expiryDate:'2026-12-01');
    final lotLate=await InventoryService.registerLot(db,actorUserId:adminId,receiptLineId:receiptLine['id'] as int,lotCode:'MILK-LATE',quantity:6,expiryDate:'2027-01-01');
    final requestId=await InventoryService.submitIssueRequest(db,actorUserId:adminId,destination:'قسم التحضير',reason:'اختبار FEFO',receiverName:'مشرف التحضير',quantities:{productId:7.0});
    final line=(await InventoryService.issueLines(db,actorUserId:adminId,requestId:requestId)).single;
    await InventoryService.approveAndIssue(db,actorUserId:adminId,requestId:requestId,issueQuantities:{line['id'] as int:7.0});
    var lots=await db.query('inventory_lots',where:'product_id=?',whereArgs:[productId],orderBy:'expiry_date');
    expect((lots[0]['quantity_remaining'] as num).toDouble(),0);
    expect((lots[1]['quantity_remaining'] as num).toDouble(),3);
    await InventoryService.recordIssueReturn(db,actorUserId:adminId,issueLineId:line['id'] as int,quantity:5,condition:'good',reason:'مواد سليمة غير مستخدمة',returnedBy:'مشرف التحضير');
    lots=await db.query('inventory_lots',where:'product_id=?',whereArgs:[productId],orderBy:'expiry_date');
    expect((lots[0]['quantity_remaining'] as num).toDouble(),4);
    expect((lots[1]['quantity_remaining'] as num).toDouble(),4);
    final returnOne=await InventoryService.submitSupplierReturn(db,actorUserId:adminId,receiptLineId:receiptLine['id'] as int,lotId:lotEarly,quantity:1,reason:'إرجاع جزء من الدفعة');
    await InventoryService.reviewSupplierReturn(db,actorUserId:adminId,returnId:returnOne,approve:true,note:'موافقة أولى');
    final returnTwo=await InventoryService.submitSupplierReturn(db,actorUserId:adminId,receiptLineId:receiptLine['id'] as int,lotId:lotLate,quantity:1,reason:'إرجاع جزء ثان');
    await InventoryService.reviewSupplierReturn(db,actorUserId:adminId,returnId:returnTwo,approve:true,note:'موافقة ثانية');
    await expectLater(()=>InventoryService.reviewSupplierReturn(db,actorUserId:adminId,returnId:returnTwo,approve:true,note:'تكرار'),throwsA(anything));
    lots=await db.query('inventory_lots',where:'product_id=?',whereArgs:[productId],orderBy:'expiry_date');
    expect((lots[0]['quantity_remaining'] as num).toDouble(),3);
    expect((lots[1]['quantity_remaining'] as num).toDouble(),3);
    final balance=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((balance['approved_qty'] as num).toDouble(),6);
    final supplierLedger=await db.query('supplier_ledger',where:"supplier_id=? AND entry_type='supplier_return'",whereArgs:[supplierId]);
    expect(supplierLedger.length,2);
    final journal=await db.rawQuery("SELECT COUNT(*) AS n FROM journal_entries WHERE source_type='inventory_supplier_return'");
    expect((journal.single['n'] as num).toInt(),2);
    await app.closeForTesting();
    await deleteDatabase(path);
  });

  test('expired lots are excluded from FEFO issue allocation', () async {
    final app=AppDatabase.instance;
    await app.closeForTesting();
    final path=p.join(await getDatabasesPath(),'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin=await app.login('admin','123456');
    final adminId=admin!['id'] as int;
    final db=await app.database;
    await InventorySchema.ensure(db);
    final supplierId=await app.saveSupplier(actorUserId:adminId,name:'Expired Supplier');
    final productId=await app.saveCatalogProduct(actorUserId:adminId,names:{'ar':'لبن منتهي'},baseUnit:'L',productType:'ingredient',categoryId:null);
    final receiptId=await app.submitPurchaseReceipt(actorUserId:adminId,supplierId:supplierId,invoiceNo:'EXP-001',lines:[{'productId':productId,'quantity':2.0}]);
    final receiptLine=(await app.purchaseReceiptLines(actorUserId:adminId,receiptId:receiptId)).single;
    await app.approvePurchaseReceipt(actorUserId:adminId,receiptId:receiptId,unitCosts:{receiptLine['id'] as int:2.0});
    await InventoryService.registerLot(db,actorUserId:adminId,receiptLineId:receiptLine['id'] as int,lotCode:'EXPIRED',quantity:2,expiryDate:'2026-11-14');
    final requestId=await InventoryService.submitIssueRequest(db,actorUserId:adminId,destination:'المطبخ',reason:'اختبار منع المنتهي',receiverName:'الشيف',quantities:{productId:1.0});
    final line=(await InventoryService.issueLines(db,actorUserId:adminId,requestId:requestId)).single;
    await expectLater(()=>InventoryService.approveAndIssue(db,actorUserId:adminId,requestId:requestId,issueQuantities:{line['id'] as int:1.0}),throwsA(anything));
    final balance=(await db.query('stock_balances',where:'product_id=?',whereArgs:[productId])).single;
    expect((balance['approved_qty'] as num).toDouble(),2);
    await app.closeForTesting();
    await deleteDatabase(path);
  });

  test('kitchen manager can request replenishment but cannot issue to other departments', () async {
    final app=AppDatabase.instance;
    await app.closeForTesting();
    final path=p.join(await getDatabasesPath(),'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    await app.ensureDefaultAdmin();
    final admin=await app.login('admin','123456');
    final adminId=admin!['id'] as int;
    final db=await app.database;
    await InventorySchema.ensure(db);
    final productId=await app.saveCatalogProduct(actorUserId:adminId,names:{'ar':'أرز','en':'Rice','fr':'Riz'},baseUnit:'kg',productType:'ingredient',categoryId:null);
    final kitchenId=await app.createEmployee(actorUserId:adminId,username:'chef_test',name:'مسؤول المطبخ',pin:'123456',role:'kitchen');
    final storekeeperId=await app.createEmployee(actorUserId:adminId,username:'storekeeper_test',name:'أمين المخزن',pin:'123456',role:'storekeeper');
    expect(await app.kitchenOrders(actorUserId:kitchenId),isEmpty);

    // A start-of-day handover is created by the Storekeeper, not by the kitchen.
    final morningHandoverId=await InventoryService.submitIssueRequest(db,actorUserId:storekeeperId,destination:'المطبخ',destinationType:'kitchen',reason:'تجهيز بداية اليوم',receiverName:'مسؤول المطبخ',quantities:{productId:8.0});
    var requests=await InventoryService.kitchenRequests(db,actorUserId:kitchenId);
    expect(requests.length,1);
    expect(requests.single['id'],morningHandoverId);

    // Kitchen replenishment requests must also remain visible in the same destination ledger.
    final requestId=await InventoryService.submitIssueRequest(db,actorUserId:kitchenId,destination:'المطبخ',destinationType:'kitchen',reason:'نقص أثناء التشغيل',receiverName:'مسؤول المطبخ',quantities:{productId:5.0});
    requests=await InventoryService.kitchenRequests(db,actorUserId:kitchenId);
    expect(requests.length,2);
    expect(requests.map((r)=>r['id']),containsAll([morningHandoverId,requestId]));
    final kitchenRequest=requests.firstWhere((r)=>r['id']==requestId);
    expect(kitchenRequest['line_count'],1);
    expect(kitchenRequest['lines_summary'].toString(),contains('5.0 / 0.0'));
    final stock=await InventoryService.kitchenStockItems(db,actorUserId:kitchenId);
    expect(stock.single['id'],productId);
    expect((stock.single['kitchen_qty'] as num).toDouble(),0.0);
    await expectLater(
      InventoryService.submitIssueRequest(db,actorUserId:kitchenId,destination:'قسم آخر',destinationType:'department',reason:'غير مسموح',receiverName:'مسؤول القسم',quantities:{productId:1.0}),
      throwsA(anything),
    );
    await app.closeForTesting();
    await deleteDatabase(path);
  });

  test('version 15 migration preserves existing employees and accepts kitchen role', () async {
    final app=AppDatabase.instance;
    await app.closeForTesting();
    final path=p.join(await getDatabasesPath(),'naeemsoft_restaurant.db');
    await deleteDatabase(path);
    final legacy=await openDatabase(path,version:14,onCreate:(db,version) async {
      await db.execute("CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('admin','cashier','storekeeper')), pin_salt TEXT NOT NULL, pin_hash TEXT NOT NULL, must_change_pin INTEGER NOT NULL DEFAULT 0, preferred_language TEXT NOT NULL DEFAULT 'ar', is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)");
      await db.execute("CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, expiry_tracked INTEGER NOT NULL DEFAULT 0)");
      await db.insert('users',{'id':7,'username':'admin','display_name':'المدير','role':'admin','pin_salt':'salt','pin_hash':'hash','must_change_pin':0,'preferred_language':'ar','is_active':1,'created_at':'2026-01-01T00:00:00Z'});
      await db.insert('products',{'id':3,'expiry_tracked':0});
    });
    await legacy.close();
    final db=await app.database;
    final retained=await db.query('users',where:'id=?',whereArgs:[7]);
    expect(retained.single['username'],'admin');
    await db.insert('users',{'username':'chef_migration','display_name':'مسؤول المطبخ','role':'kitchen','pin_salt':'salt','pin_hash':'hash','must_change_pin':0,'preferred_language':'ar','is_active':1,'created_at':'2026-01-01T00:00:00Z'});
    final productColumns=await db.rawQuery('PRAGMA table_info(products)');
    expect(productColumns.any((c)=>c['name']=='preparation_required'),isTrue);
    expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
    await app.closeForTesting();
    await deleteDatabase(path);
  });

}
