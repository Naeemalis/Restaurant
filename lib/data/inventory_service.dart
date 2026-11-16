import 'package:sqflite/sqflite.dart';

/// Storekeeper operations. Financial values and supplier balances are not exposed.
class InventoryService {
  InventoryService._();
  static String _now() => DateTime.now().toUtc().toIso8601String();

  static Future<void> _role(DatabaseExecutor tx, int id, List<String> roles) async {
    final rows = await tx.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty || rows.first['is_active'] != 1 || !roles.contains(rows.first['role'])) {
      throw StateError('ليست لديك صلاحية تنفيذ هذه العملية');
    }
  }


  static Future<void> _postWriteoffJournal(DatabaseExecutor tx, {
    required int actorUserId, required String sourceType,
    required int sourceId, required String description, required double amount,
  }) async {
    if (!amount.isFinite || amount < 0) throw ArgumentError('قيمة تسوية المخزون غير صحيحة');
    if (amount <= 0.000001) return;
    final existing = await tx.query('journal_entries', columns:['id'],
        where:'source_type=? AND source_id=?', whereArgs:[sourceType,sourceId], limit:1);
    if (existing.isNotEmpty) return;
    final expense = await tx.query('accounts', columns:['id'],
        where:"code='EXPENSE' AND is_active=1", limit:1);
    final inventory = await tx.query('accounts', columns:['id'],
        where:"code='INVENTORY' AND is_active=1", limit:1);
    if (expense.isEmpty || inventory.isEmpty) throw StateError('حساب المصروفات أو المخزون غير موجود');
    final now = _now();
    final entryId = await tx.insert('journal_entries', {
      'entry_no':'J-INV-' + DateTime.now().microsecondsSinceEpoch.toString(),
      'source_type':sourceType, 'source_id':sourceId,
      'description':description, 'actor_user_id':actorUserId, 'created_at':now,
    });
    await tx.insert('journal_lines', {
      'entry_id':entryId, 'account_id':expense.first['id'],
      'debit':amount, 'credit':0.0,
    });
    await tx.insert('journal_lines', {
      'entry_id':entryId, 'account_id':inventory.first['id'],
      'debit':0.0, 'credit':amount,
    });
  }

  static Future<List<Map<String, Object?>>> stockOverview(Database db, {required int actorUserId, String language='ar'}) async {
    final a = await db.query('users', columns: ['role', 'is_active'], where: 'id=?', whereArgs: [actorUserId], limit: 1);
    if (a.isEmpty || a.first['is_active'] != 1 || !['admin', 'storekeeper'].contains(a.first['role'])) throw StateError('ليست لديك صلاحية عرض المخزون');
    return db.rawQuery('''
      SELECT p.id,p.category_id,COALESCE((SELECT ct.name FROM category_translations ct WHERE ct.category_id=p.category_id AND ct.language_code=?),(SELECT cta.name FROM category_translations cta WHERE cta.category_id=p.category_id AND cta.language_code='ar'),'غير مصنف') AS category_name,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code='ar'),p.name_ar) AS name_ar,p.base_unit,COALESCE(b.on_hand,0) AS on_hand,COALESCE(kb.quantity,0) AS kitchen_qty,
      COALESCE(b.approved_qty,0) AS approved_qty,COALESCE(b.unapproved_qty,0) AS unapproved_qty,
      COALESCE(q.blocked_qty,0) AS quarantined_qty,COALESCE(rr.minimum_qty,0) AS minimum_qty,
      COALESCE(rr.reorder_qty,0) AS reorder_qty
      FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id
      LEFT JOIN kitchen_stock_balances kb ON kb.product_id=p.id
      LEFT JOIN (SELECT product_id,SUM(quantity) AS blocked_qty FROM inventory_quarantine WHERE status='blocked' GROUP BY product_id) q ON q.product_id=p.id
      LEFT JOIN inventory_reorder_rules rr ON rr.product_id=p.id
      WHERE p.is_active=1 AND p.is_stock_item=1 ORDER BY name_ar
    ''',[language,language]);
  }

  static Future<int> submitIssueRequest(Database db, {required int actorUserId, required String destination, String destinationType = 'department', required String reason, required String receiverName, required Map<int, double> quantities, Map<int,double>? enteredQuantities, Map<int,String>? enteredUnits, Map<int,double>? conversionFactors}) async {
    if (destination.trim().isEmpty || !['kitchen','department'].contains(destinationType) || reason.trim().isEmpty || receiverName.trim().isEmpty || quantities.isEmpty || quantities.values.any((q) => !q.isFinite || q <= 0)) throw ArgumentError('حدد الجهة والمستلم والسبب وأدخل كميات صحيحة');
    return db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin', 'storekeeper','kitchen']);
      final requester=await tx.query('users',columns:['role'],where:'id=?',whereArgs:[actorUserId],limit:1);
      if(requester.first['role']=='kitchen' && destinationType!='kitchen') throw StateError('مسؤول المطبخ يستطيع طلب تزويد عهدة المطبخ فقط');
      final now = _now();
      final doc = 'ISS-' + DateTime.now().microsecondsSinceEpoch.toString();
      final id = await tx.insert('stock_issue_requests', {'document_no': doc, 'status': 'submitted', 'destination': destination.trim(), 'destination_type': destinationType, 'reason': reason.trim(), 'requested_by': actorUserId, 'received_by_name': receiverName.trim(), 'requested_at': now});
      for (final e in quantities.entries) {
        final p = await tx.query('products', columns: ['base_unit'], where: 'id=? AND is_active=1 AND is_stock_item=1', whereArgs: [e.key], limit: 1);
        if (p.isEmpty) throw StateError('أحد الأصناف غير صالح');
        final entered=(enteredQuantities?[e.key]??e.value);
        final factor=(conversionFactors?[e.key]??1.0);
        if(!entered.isFinite || entered<=0 || !factor.isFinite || factor<=0 || (entered*factor-e.value).abs()>0.000001) throw ArgumentError('بيانات وحدة الصرف غير متطابقة مع الكمية الأساسية');
        await tx.insert('stock_issue_lines', {'request_id': id, 'product_id': e.key, 'requested_qty': e.value, 'issued_qty': 0, 'unit_snapshot': p.first['base_unit'],'entered_qty':entered,'entered_unit_name':enteredUnits?[e.key]??p.first['base_unit'],'conversion_to_base_snapshot':factor});
      }
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'stock_issue_requested', 'entity_type': 'stock_issue', 'entity_id': id, 'details': 'Request submitted: ' + doc, 'created_at': now});
      return id;
    });
  }

  /// Materials visible to the kitchen user, with the kitchen's own custody balance.
  static Future<List<Map<String,Object?>>> kitchenStockItems(Database db,{required int actorUserId,String language='ar'}) async {
    await _role(db,actorUserId,['admin','kitchen']);
    return db.rawQuery('''
      SELECT p.id,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code='ar'),p.name_ar) AS name_ar,p.base_unit,COALESCE(k.quantity,0) AS kitchen_qty
      FROM products p LEFT JOIN kitchen_stock_balances k ON k.product_id=p.id
      WHERE p.is_active=1 AND p.is_stock_item=1 ORDER BY name_ar
    ''',[language]);
  }

  /// Only the requesting kitchen account can inspect its own replenishment requests.
  static Future<List<Map<String,Object?>>> kitchenRequests(Database db,{required int actorUserId,String language='ar'}) async {
    await _role(db,actorUserId,['admin','kitchen']);
    return db.rawQuery('''
      SELECT r.id,r.document_no,r.status,r.reason,r.requested_at,
        (SELECT COUNT(*) FROM stock_issue_lines l WHERE l.request_id=r.id) AS line_count,
        (SELECT group_concat(COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),p.name_ar) || ' — ' || l.requested_qty || ' / ' || l.issued_qty || ' ' || l.unit_snapshot,'؛ ')
          FROM stock_issue_lines l JOIN products p ON p.id=l.product_id WHERE l.request_id=r.id) AS lines_summary
      FROM stock_issue_requests r
      WHERE r.destination_type='kitchen'
      ORDER BY r.id DESC LIMIT 30
    ''',[language]);
  }

  static Future<List<Map<String, Object?>>> issueRequests(Database db, {required int actorUserId, bool pendingOnly = false}) async {
    await _role(db, actorUserId, ['admin', 'storekeeper']);
    final filter = pendingOnly ? "WHERE r.status IN ('submitted','partially_issued')" : '';
    return db.rawQuery('SELECT r.*,u.display_name AS requester_name,(SELECT COUNT(*) FROM stock_issue_lines l WHERE l.request_id=r.id) AS line_count FROM stock_issue_requests r LEFT JOIN users u ON u.id=r.requested_by ' + filter + ' ORDER BY r.id DESC');
  }

  static Future<List<Map<String, Object?>>> issueLines(Database db, {required int actorUserId, required int requestId, String language='ar'}) async {
    await _role(db, actorUserId, ['admin', 'storekeeper']);
    return db.rawQuery('''
      SELECT l.*,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code='ar'),p.name_ar) AS name_ar,COALESCE(b.approved_qty,0) AS available_qty,
      COALESCE((SELECT SUM(x.quantity) FROM stock_return_records x WHERE x.issue_line_id=l.id),0) AS returned_qty
      FROM stock_issue_lines l JOIN products p ON p.id=l.product_id
      LEFT JOIN stock_balances b ON b.product_id=p.id WHERE l.request_id=? ORDER BY l.id
    ''', [language,requestId]);
  }

  /// issueQuantities are incremental quantities for this approval, not cumulative totals.
  static Future<void> approveAndIssue(Database db, {required int actorUserId, required int requestId, required Map<int, double> issueQuantities, String note = ''}) async {
    if (issueQuantities.isEmpty || issueQuantities.values.any((q) => !q.isFinite || q < 0)) throw ArgumentError('كميات الصرف غير صحيحة');
    await db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin','storekeeper']);
      final rs = await tx.query('stock_issue_requests', where: "id=? AND status IN ('submitted','partially_issued')", whereArgs: [requestId], limit: 1);
      if (rs.isEmpty) throw StateError('إذن الصرف غير معلق أو تمت معالجته');
      final actorRows=await tx.query('users',columns:['role'],where:'id=?',whereArgs:[actorUserId],limit:1);
      if(actorRows.first['role']=='storekeeper' && rs.first['destination_type']!='kitchen') {
        throw StateError('أمين المخزن مخوّل بتأكيد تسليم عهدة المطبخ فقط؛ صرف الأقسام الأخرى يحتاج اعتماد المدير');
      }
      final lines = await tx.query('stock_issue_lines', where: 'request_id=?', whereArgs: [requestId]);
      if (lines.isEmpty || lines.any((l) => !issueQuantities.containsKey(l['id'] as int))) throw StateError('راجع كمية كل صنف في الطلب');
      final now = _now();
      var count = 0;
      var complete = true;
      for (final l in lines) {
        final lid = l['id'] as int, pid = l['product_id'] as int;
        final qty = issueQuantities[lid]!;
        final requested = (l['requested_qty'] as num).toDouble();
        final already = (l['issued_qty'] as num).toDouble();
        if (qty > requested - already + 0.0000001) throw StateError('كمية الصرف تتجاوز الكمية المتبقية المطلوبة');
        if (qty > 0) {
          final kitchenHandover = rs.first['destination_type'] == 'kitchen';
          if (kitchenHandover) {
            await consumeLotsFefo(tx, productId:pid, quantity:qty, actorUserId:actorUserId, source:'stock_issue:$requestId:$lid');
            final mainRows=await tx.query('stock_balances',columns:['on_hand','approved_qty','weighted_average_cost'],where:'product_id=?',whereArgs:[pid],limit:1);
            if(mainRows.isEmpty) throw StateError('رصيد الصنف غير موجود في المخزن الرئيسي');
            final transferCost=(mainRows.first['weighted_average_cost'] as num).toDouble();
            final changed = await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand-?,approved_qty=approved_qty-?,updated_at=? WHERE product_id=? AND approved_qty>=? AND on_hand>=?', [qty, qty, now, pid, qty, qty]);
            if (changed != 1) throw StateError('الرصيد الرئيسي المعتمد غير كافٍ للتسليم للمطبخ');
            final kitchenRows=await tx.query('kitchen_stock_balances',where:'product_id=?',whereArgs:[pid],limit:1);
            await tx.rawInsert('INSERT INTO kitchen_stock_balances(product_id,quantity,weighted_average_cost,updated_at) VALUES(?,?,?,?) ON CONFLICT(product_id) DO UPDATE SET quantity=quantity+excluded.quantity,weighted_average_cost=CASE WHEN quantity+excluded.quantity<=0 THEN 0 ELSE ((quantity*weighted_average_cost)+(excluded.quantity*excluded.weighted_average_cost))/(quantity+excluded.quantity) END,updated_at=excluded.updated_at',[pid,qty,transferCost,now]);
            await tx.insert('kitchen_stock_movements', {'product_id':pid,'quantity_delta':qty,'movement_type':'handover_in','source_type':'stock_issue','source_id':requestId,'idempotency_key':'kitchen-handover:$requestId:$lid:$already','actor_user_id':actorUserId,'note':'تسليم من المخزن الرئيسي: '+qty.toString(),'created_at':now});
          } else {
            await consumeLotsFefo(tx, productId:pid, quantity:qty, actorUserId:actorUserId, source:'stock_issue:$requestId:$lid');
            final changed = await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand-?,approved_qty=approved_qty-?,updated_at=? WHERE product_id=? AND approved_qty>=? AND on_hand>=?', [qty, qty, now, pid, qty, qty]);
            if (changed != 1) throw StateError('الرصيد المعتمد غير كافٍ؛ ألغيت العملية');
          }
          await tx.insert('stock_movements', {'product_id': pid, 'movement_type': kitchenHandover ? 'kitchen_handover' : 'issue', 'quantity_delta': -qty, 'source_type': 'stock_issue', 'source_id': requestId, 'idempotency_key': 'stock-issue:$requestId:$lid:$already', 'actor_user_id': actorUserId, 'note': kitchenHandover ? 'تحويل فعلي من المخزن الرئيسي إلى عهدة المطبخ: ' + qty.toString() + ' ' + l['unit_snapshot'].toString() : (note.trim().isEmpty ? 'صرف إلى ' + rs.first['destination'].toString() : note.trim()), 'occurred_at': now});
          await tx.update('stock_issue_lines', {'issued_qty': already + qty}, where: 'id=?', whereArgs: [lid]);
          count++;
        }
        if (already + qty < requested - 0.0000001) complete = false;
      }
      if (count == 0) throw StateError('لم يتم صرف أي كمية جديدة');
      final status = complete ? 'issued' : 'partially_issued';
      await tx.update('stock_issue_requests', {'status': status, 'issued_by': actorUserId, 'reviewed_by': actorUserId, 'reviewed_at': now, 'review_note': note.trim()}, where: "id=? AND status IN ('submitted','partially_issued')", whereArgs: [requestId]);
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'stock_issue_posted', 'entity_type': 'stock_issue', 'entity_id': requestId, 'details': 'Issue posted; status=' + status, 'created_at': now});
    });
  }

  static Future<void> rejectIssue(Database db, {required int actorUserId, required int requestId, required String reason}) async {
    if (reason.trim().isEmpty) throw ArgumentError('سبب الرفض مطلوب');
    await db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin']);
      final changed = await tx.update('stock_issue_requests', {'status': 'rejected', 'reviewed_by': actorUserId, 'reviewed_at': _now(), 'review_note': reason.trim()}, where: "id=? AND status IN ('submitted','partially_issued')", whereArgs: [requestId]);
      if (changed != 1) throw StateError('طلب الصرف غير معلق');
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'stock_issue_rejected', 'entity_type': 'stock_issue', 'entity_id': requestId, 'details': reason.trim(), 'created_at': _now()});
    });
  }

  static Future<void> _restoreIssueReturnLots(DatabaseExecutor tx, {required int productId, required int issueLineId, required double quantity, required int actorUserId}) async {
    final products=await tx.query('products',columns:['expiry_tracked'],where:'id=?',whereArgs:[productId],limit:1);
    if(products.isEmpty || products.first['expiry_tracked']!=1) return;
    final issue=await tx.query('stock_issue_lines',columns:['request_id'],where:'id=?',whereArgs:[issueLineId],limit:1);
    if(issue.isEmpty) throw StateError('سطر الصرف غير موجود عند إعادة الدفعة');
    final source='stock_issue:${issue.first['request_id']}:$issueLineId';
    final allocations=await tx.rawQuery('''SELECT m.lot_id,SUM(-m.quantity_delta) AS consumed,l.expiry_date,l.quantity_remaining
      FROM inventory_lot_movements m JOIN inventory_lots l ON l.id=m.lot_id
      WHERE m.source_ref=? AND m.quantity_delta<0
      GROUP BY m.lot_id,l.expiry_date,l.quantity_remaining
      ORDER BY l.expiry_date ASC,m.lot_id ASC''',[source]);
    var remaining=quantity;
    for(final lot in allocations){
      if(remaining<=0.0000001) break;
      final prior=await tx.rawQuery('SELECT COALESCE(SUM(quantity_delta),0) AS restored FROM inventory_lot_movements WHERE lot_id=? AND source_ref=? AND quantity_delta>0',[lot['lot_id'],'issue_return:$issueLineId']);
      final original=(lot['consumed'] as num).toDouble();
      final restored=(prior.first['restored'] as num).toDouble();
      final available=original-restored;
      if(available<=0.0000001) continue;
      final putBack=available<remaining?available:remaining;
      await tx.rawUpdate("UPDATE inventory_lots SET quantity_remaining=quantity_remaining+?,status='active' WHERE id=?",[putBack,lot['lot_id']]);
      await tx.insert('inventory_lot_movements',{'lot_id':lot['lot_id'],'product_id':productId,'quantity_delta':putBack,'source_ref':'issue_return:$issueLineId','actor_user_id':actorUserId,'created_at':_now()});
      remaining-=putBack;
    }
    if(remaining>0.0000001) throw StateError('تعذر مطابقة الدفعة الأصلية للكمية المرتجعة؛ لم يتم ترحيل المرتجع');
  }

  static Future<int> recordIssueReturn(Database db, {required int actorUserId, required int issueLineId, required double quantity, required String condition, required String reason, required String returnedBy}) async {
    if (!quantity.isFinite || quantity <= 0 || !['good', 'damaged', 'quarantine'].contains(condition) || reason.trim().isEmpty || returnedBy.trim().isEmpty) throw ArgumentError('بيانات المرتجع أو حالته غير صحيحة');
    return db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin', 'storekeeper']);
      final rows = await tx.rawQuery('SELECT l.id,l.product_id,l.issued_qty,l.unit_snapshot,r.destination_type,COALESCE(kb.weighted_average_cost,b.weighted_average_cost,0) AS unit_cost FROM stock_issue_lines l JOIN stock_issue_requests r ON r.id=l.request_id LEFT JOIN stock_balances b ON b.product_id=l.product_id LEFT JOIN kitchen_stock_balances kb ON kb.product_id=l.product_id WHERE l.id=?', [issueLineId]);
      if (rows.isEmpty) throw StateError('بند الصرف غير موجود');
      final line = rows.first;
      final sums = await tx.rawQuery('SELECT COALESCE(SUM(quantity),0) AS returned FROM stock_return_records WHERE issue_line_id=?', [issueLineId]);
      final returned = (sums.first['returned'] as num).toDouble();
      final issued = (line['issued_qty'] as num).toDouble();
      if (quantity > issued - returned + 0.0000001) throw StateError('الكمية المرتجعة تتجاوز الكمية المصروفة المتبقية');
      final now = _now();
      int? movementId;
      final kitchenHandover = line['destination_type'] == 'kitchen';
      if (condition == 'good') {
        if (kitchenHandover) {
          final kitchenChanged=await tx.rawUpdate('UPDATE kitchen_stock_balances SET quantity=quantity-?,updated_at=? WHERE product_id=? AND quantity>=?',[quantity,now,line['product_id'],quantity]);
          if(kitchenChanged!=1) throw StateError('رصيد المطبخ لا يكفي لإرجاع هذه الكمية');
          await tx.insert('kitchen_stock_movements',{'product_id':line['product_id'],'quantity_delta':-quantity,'movement_type':'return_to_main_store','source_type':'stock_issue_return','source_id':issueLineId,'idempotency_key':'kitchen-return-main:$issueLineId:'+DateTime.now().microsecondsSinceEpoch.toString(),'actor_user_id':actorUserId,'note':reason.trim(),'created_at':now});
        }
        await _restoreIssueReturnLots(tx,productId:line['product_id'] as int,issueLineId:issueLineId,quantity:quantity,actorUserId:actorUserId);
        if(kitchenHandover) {
          final mainRows=await tx.query('stock_balances',columns:['on_hand','approved_qty','weighted_average_cost'],where:'product_id=?',whereArgs:[line['product_id']],limit:1);
          if(mainRows.isEmpty) throw StateError('رصيد المخزن الرئيسي غير موجود');
          final mainQty=(mainRows.first['approved_qty'] as num).toDouble();
          final mainCost=(mainRows.first['weighted_average_cost'] as num).toDouble();
          final returnedCost=(line['unit_cost'] as num).toDouble();
          final combinedQty=mainQty+quantity;
          final combinedCost=combinedQty<=0?0.0:((mainQty*mainCost)+(quantity*returnedCost))/combinedQty;
          await tx.update('stock_balances',{'on_hand':(mainRows.first['on_hand'] as num).toDouble()+quantity,'approved_qty':combinedQty,'weighted_average_cost':combinedCost,'updated_at':now},where:'product_id=?',whereArgs:[line['product_id']]);
        } else {
          final changed = await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand+?,approved_qty=approved_qty+?,updated_at=? WHERE product_id=?', [quantity, quantity, now, line['product_id']]);
          if (changed != 1) throw StateError('رصيد الصنف غير موجود');
        }
        movementId = await tx.insert('stock_movements', {'product_id': line['product_id'], 'movement_type': kitchenHandover ? 'kitchen_handover_return' : 'issue_return', 'quantity_delta': quantity, 'source_type': 'stock_issue_return', 'source_id': issueLineId, 'idempotency_key': 'issue-return:$issueLineId:' + DateTime.now().microsecondsSinceEpoch.toString(), 'actor_user_id': actorUserId, 'note': reason.trim(), 'occurred_at': now});
      } else if (kitchenHandover) {
        final changed = await tx.rawUpdate('UPDATE kitchen_stock_balances SET quantity=quantity-?,updated_at=? WHERE product_id=? AND quantity>=?', [quantity, now, line['product_id'], quantity]);
        if (changed != 1) throw StateError('رصيد المطبخ غير كافٍ لعزل المرتجع التالف');
        await tx.insert('kitchen_stock_movements',{'product_id':line['product_id'],'quantity_delta':-quantity,'movement_type':'damaged_return','source_type':'stock_issue_return','source_id':issueLineId,'idempotency_key':'kitchen-damaged-return:$issueLineId:'+DateTime.now().microsecondsSinceEpoch.toString(),'actor_user_id':actorUserId,'note':reason.trim(),'created_at':now});
        movementId = await tx.insert('stock_movements', {'product_id': line['product_id'], 'movement_type': 'kitchen_return_quarantine', 'quantity_delta': 0.0, 'source_type': 'stock_issue_return', 'source_id': issueLineId, 'idempotency_key': 'issue-return-quarantine:$issueLineId:' + DateTime.now().microsecondsSinceEpoch.toString(), 'actor_user_id': actorUserId, 'note': reason.trim(), 'occurred_at': now});
      }
      final id = await tx.insert('stock_return_records', {'issue_line_id': issueLineId, 'product_id': line['product_id'], 'quantity': quantity, 'unit_snapshot': line['unit_snapshot'], 'condition_code': condition, 'reason': reason.trim(), 'returned_by_name': returnedBy.trim(), 'recorded_by': actorUserId, 'movement_id': movementId, 'created_at': now});
      if (condition != 'good') {
        await tx.insert('inventory_quarantine', {'product_id': line['product_id'], 'quantity': quantity, 'unit_snapshot': line['unit_snapshot'], 'source_type': 'stock_issue_return', 'source_id': id, 'reason': reason.trim(), 'status': 'blocked', 'recorded_by': actorUserId, 'created_at': now, 'unit_cost_snapshot': line['unit_cost']});
      }
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'stock_issue_return_recorded', 'entity_type': 'stock_return', 'entity_id': id, 'details': 'condition=' + condition + '; quantity=' + quantity.toString(), 'created_at': now});
      return id;
    });
  }

  static Future<int> quarantineStock(Database db, {required int actorUserId, required int productId, required double quantity, required String reason}) async {
    if (!quantity.isFinite || quantity <= 0 || reason.trim().isEmpty) throw ArgumentError('الكمية وسبب الحجز مطلوبان');
    return db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin', 'storekeeper']);
      final p = await tx.query('products', columns: ['base_unit'], where: 'id=? AND is_active=1 AND is_stock_item=1', whereArgs: [productId], limit: 1);
      if (p.isEmpty) throw StateError('الصنف غير موجود');
      final now = _now();
      final balanceRows = await tx.query('stock_balances', columns:['weighted_average_cost'], where:'product_id=?', whereArgs:[productId], limit:1);
      if (balanceRows.isEmpty) throw StateError('رصيد الصنف غير موجود');
      final unitCost = (balanceRows.first['weighted_average_cost'] as num).toDouble();
      await consumeLotsFefo(tx,productId:productId,quantity:quantity,actorUserId:actorUserId,source:'quarantine:$productId:$now');
      final changed = await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand-?,approved_qty=approved_qty-?,updated_at=? WHERE product_id=? AND on_hand>=? AND approved_qty>=?', [quantity, quantity, now, productId, quantity, quantity]);
      if (changed != 1) throw StateError('الكمية المتاحة غير كافية للحجز');
      final id = await tx.insert('inventory_quarantine', {'product_id': productId, 'quantity': quantity, 'unit_snapshot': p.first['base_unit'], 'source_type': 'stock_quarantine', 'source_id': null, 'reason': reason.trim(), 'status': 'blocked', 'recorded_by': actorUserId, 'created_at': now, 'unit_cost_snapshot':unitCost});
      await tx.update('inventory_quarantine', {'source_id': id}, where: 'id=?', whereArgs: [id]);
      await tx.insert('stock_movements', {'product_id': productId, 'movement_type': 'quarantine_out', 'quantity_delta': -quantity, 'source_type': 'inventory_quarantine', 'source_id': id, 'idempotency_key': 'quarantine:$id', 'actor_user_id': actorUserId, 'note': reason.trim(), 'occurred_at': now});
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'inventory_quarantined', 'entity_type': 'inventory_quarantine', 'entity_id': id, 'details': 'Quantity=' + quantity.toString() + '; ' + reason.trim(), 'created_at': now});
      return id;
    });
  }

  static Future<void> resolveQuarantine(Database db, {required int actorUserId, required int quarantineId, required String resolution, required String note}) async {
    if (!['release', 'writeoff'].contains(resolution) || note.trim().isEmpty) throw ArgumentError('حدد قرار المعالجة واكتب الملاحظة');
    await db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin']);
      final rows = await tx.query('inventory_quarantine', where: "id=? AND status='blocked'", whereArgs: [quarantineId], limit: 1);
      if (rows.isEmpty) throw StateError('سجل الحجز تمت معالجته مسبقاً');
      final q = rows.first, now = _now();
      if (resolution == 'release') {
        final qty = (q['quantity'] as num).toDouble();
        final changed = await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand+?,approved_qty=approved_qty+?,updated_at=? WHERE product_id=?', [qty, qty, now, q['product_id']]);
        if (changed != 1) throw StateError('رصيد الصنف غير موجود');
        await tx.insert('stock_movements', {'product_id': q['product_id'], 'movement_type': 'quarantine_release', 'quantity_delta': qty, 'source_type': 'inventory_quarantine', 'source_id': quarantineId, 'idempotency_key': 'quarantine-release:$quarantineId', 'actor_user_id': actorUserId, 'note': note.trim(), 'occurred_at': now});
      }
      if (resolution == 'writeoff') {
        final cost = (q['quantity'] as num).toDouble() * (q['unit_cost_snapshot'] as num).toDouble();
        await _postWriteoffJournal(tx, actorUserId:actorUserId, sourceType:'inventory_quarantine_writeoff', sourceId:quarantineId, description:'إتلاف مخزون محجوز رقم ' + quarantineId.toString(), amount:cost);
      }
      await tx.update('inventory_quarantine', {'status': resolution == 'release' ? 'released' : 'written_off', 'reviewed_by': actorUserId, 'reviewed_at': now, 'reason': (q['reason'] as String) + ' | ' + note.trim()}, where: "id=? AND status='blocked'", whereArgs: [quarantineId]);
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': resolution == 'release' ? 'quarantine_released' : 'quarantine_written_off', 'entity_type': 'inventory_quarantine', 'entity_id': quarantineId, 'details': note.trim(), 'created_at': now});
    });
  }

  static Future<int> recordWaste(Database db, {required int actorUserId, required int productId, required double quantity, required String reason}) async {
    if (!quantity.isFinite || quantity <= 0 || reason.trim().isEmpty) throw ArgumentError('كمية الهدر وسببه مطلوبان');
    return db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin', 'storekeeper']);
      final p = await tx.query('products', columns: ['id'], where: 'id=? AND is_active=1 AND is_stock_item=1', whereArgs: [productId], limit: 1);
      if (p.isEmpty) throw StateError('الصنف غير موجود');
      final costRows = await tx.query('stock_balances', columns:['weighted_average_cost'], where:'product_id=?', whereArgs:[productId], limit:1);
      if (costRows.isEmpty) throw StateError('رصيد الصنف غير موجود');
      final unitCost = (costRows.first['weighted_average_cost'] as num).toDouble();
      final now = _now();
      await consumeLotsFefo(tx,productId:productId,quantity:quantity,actorUserId:actorUserId,source:'waste:$productId:$now');
      final changed = await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand-?,approved_qty=approved_qty-?,updated_at=? WHERE product_id=? AND on_hand>=? AND approved_qty>=?', [quantity, quantity, now, productId, quantity, quantity]);
      if (changed != 1) throw StateError('الرصيد المتاح غير كافٍ لتسجيل الهدر');
      final moveId = await tx.insert('stock_movements', {'product_id': productId, 'movement_type': 'waste', 'quantity_delta': -quantity, 'source_type': 'waste', 'source_id': null, 'idempotency_key': 'waste:' + DateTime.now().microsecondsSinceEpoch.toString(), 'actor_user_id': actorUserId, 'note': reason.trim(), 'occurred_at': now});
      final id = await tx.insert('waste_records', {'product_id': productId, 'quantity': quantity, 'reason_code': 'storekeeper_recorded', 'reason_note': reason.trim(), 'recorded_by': actorUserId, 'recorded_at': now, 'movement_id': moveId, 'unit_cost_snapshot':unitCost});
      await _postWriteoffJournal(tx, actorUserId:actorUserId, sourceType:'inventory_waste', sourceId:id, description:'هدر مخزون رقم ' + id.toString(), amount:quantity*unitCost);
      await tx.update('stock_movements', {'source_id': id}, where: 'id=?', whereArgs: [moveId]);
      await tx.insert('audit_logs', {'actor_user_id': actorUserId, 'action': 'stock_waste_recorded', 'entity_type': 'waste_record', 'entity_id': id, 'details': 'Quantity=' + quantity.toString() + '; ' + reason.trim(), 'created_at': now});
      return id;
    });
  }

  static Future<List<Map<String, Object?>>> quarantineRecords(Database db, {required int actorUserId, bool blockedOnly = false, String language='ar'}) async {
    await _role(db, actorUserId, ['admin', 'storekeeper']);
    final actor=await db.query('users',columns:['role'],where:'id=?',whereArgs:[actorUserId],limit:1);
    final columns=actor.first['role']=='admin'?'q.*':"q.id,q.product_id,q.quantity,q.unit_snapshot,q.source_type,q.source_id,q.reason,q.status,q.recorded_by,q.created_at,q.reviewed_by,q.reviewed_at";
    final filter = blockedOnly ? "WHERE q.status='blocked'" : '';
    return db.rawQuery('SELECT '+columns+',COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=\'ar\'),p.name_ar) AS name_ar FROM inventory_quarantine q JOIN products p ON p.id=q.product_id ' + filter + ' ORDER BY q.id DESC',[language]);
  }

  static Future<List<Map<String, Object?>>> wasteRecords(Database db, {required int actorUserId, String language='ar'}) async {
    await _role(db, actorUserId, ['admin', 'storekeeper']);
    final actor=await db.query('users',columns:['role'],where:'id=?',whereArgs:[actorUserId],limit:1);
    final columns=actor.first['role']=='admin'?'w.*':"w.id,w.product_id,w.quantity,w.reason_code,w.reason_note,w.recorded_by,w.recorded_at,w.movement_id";
    return db.rawQuery('SELECT '+columns+',COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=\'ar\'),p.name_ar) AS name_ar,p.base_unit,u.display_name FROM waste_records w JOIN products p ON p.id=w.product_id LEFT JOIN users u ON u.id=w.recorded_by ORDER BY w.id DESC LIMIT 200',[language]);
  }

  /// Register a traceable batch against an approved supplier receipt line.
  static Future<int> registerLot(Database db, {required int actorUserId, required int receiptLineId, required String lotCode, required double quantity, String? manufactureDate, required String expiryDate}) async {
    if (lotCode.trim().isEmpty || !quantity.isFinite || quantity <= 0) throw ArgumentError('رقم التشغيلة والكمية مطلوبان');
    final expiry = DateTime.tryParse(expiryDate);
    final manufacture = manufactureDate == null || manufactureDate.trim().isEmpty ? null : DateTime.tryParse(manufactureDate);
    if (expiry == null || (manufactureDate != null && manufactureDate.trim().isNotEmpty && manufacture == null) || (manufacture != null && manufacture.isAfter(expiry))) throw ArgumentError('تواريخ التشغيلة غير صحيحة');
    return db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin']);
      final lines = await tx.rawQuery("SELECT l.*,r.status FROM purchase_receipt_lines l JOIN purchase_receipts r ON r.id=l.receipt_id WHERE l.id=? AND r.status='approved'", [receiptLineId]);
      if (lines.isEmpty) throw StateError('لا يمكن ربط تشغيلة إلا بسطر توريد معتمد');
      final line = lines.first;
      final productId = line['product_id'] as int;
      final qty = (line['received_qty'] as num).toDouble();
      final existing = await tx.rawQuery('SELECT COALESCE(SUM(quantity_received),0) AS qty FROM inventory_lots WHERE receipt_line_id=?', [receiptLineId]);
      final already = (existing.first['qty'] as num).toDouble();
      if (already + quantity > qty + 0.0000001) throw StateError('إجمالي كميات التشغيلات يتجاوز كمية سطر التوريد');
      final id = await tx.insert('inventory_lots', {'product_id':productId,'receipt_line_id':receiptLineId,'lot_code':lotCode.trim(),'manufacture_date':manufacture?.toIso8601String().substring(0,10),'expiry_date':expiry.toIso8601String().substring(0,10),'quantity_received':quantity,'quantity_remaining':quantity,'status':'active','created_by':actorUserId,'created_at':_now()});
      await tx.insert('inventory_lot_movements',{'lot_id':id,'product_id':productId,'quantity_delta':quantity,'source_ref':'receipt:$receiptLineId','actor_user_id':actorUserId,'created_at':_now()});
      await tx.update('products', {'expiry_tracked':1}, where:'id=?', whereArgs:[productId]);
      await tx.insert('audit_logs', {'actor_user_id':actorUserId,'action':'inventory_lot_registered','entity_type':'inventory_lot','entity_id':id,'details':'Receipt line=$receiptLineId; lot=${lotCode.trim()}; expiry=$expiryDate','created_at':_now()});
      return id;
    });
  }

  /// Consume traceable batches by FEFO. Products without registered batches retain legacy stock behavior.
  static Future<void> consumeLotsFefo(DatabaseExecutor tx, {required int productId, required double quantity, required int actorUserId, required String source}) async {
    final product = await tx.query('products', columns:['expiry_tracked'], where:'id=?', whereArgs:[productId], limit:1);
    if (product.isEmpty || product.first['expiry_tracked'] != 1) return;
    final today = DateTime.now().toUtc().toIso8601String().substring(0,10);
    final lots = await tx.query('inventory_lots', where:"product_id=? AND status='active' AND expiry_date>=? AND quantity_remaining>0", whereArgs:[productId,today], orderBy:'expiry_date ASC,id ASC');
    var remaining = quantity;
    for (final lot in lots) {
      if (remaining <= 0.0000001) break;
      final available = (lot['quantity_remaining'] as num).toDouble();
      final take = available < remaining ? available : remaining;
      await tx.rawUpdate("UPDATE inventory_lots SET quantity_remaining=quantity_remaining-?, status=CASE WHEN quantity_remaining-?<=0.0000001 THEN 'depleted' ELSE status END WHERE id=? AND quantity_remaining>=?", [take,take,lot['id'],take]);
      remaining -= take;
      await tx.insert('inventory_lot_movements',{'lot_id':lot['id'],'product_id':productId,'quantity_delta':-take,'source_ref':source,'actor_user_id':actorUserId,'created_at':_now()});
    }
    if (remaining > 0.0000001) throw StateError('لا توجد كمية صالحة كافية حسب تواريخ الصلاحية؛ تم إلغاء الصرف');
    await tx.insert('audit_logs', {'actor_user_id':actorUserId,'action':'inventory_fefo_consumption','entity_type':'product','entity_id':productId,'details':'FEFO quantity=$quantity; source=$source','created_at':_now()});
  }

  static Future<List<Map<String, Object?>>> expiryAlerts(Database db, {required int actorUserId, int daysAhead = 30, String language='ar'}) async {
    if (daysAhead < 0 || daysAhead > 365) throw ArgumentError('فترة التنبيه غير صحيحة');
    await _role(db, actorUserId, ['admin','storekeeper']);
    final today = DateTime.now().toUtc();
    final until = today.add(Duration(days:daysAhead)).toIso8601String().substring(0,10);
    final day = today.toIso8601String().substring(0,10);
    return db.rawQuery('''SELECT l.id,l.product_id,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code='ar'),p.name_ar) AS name_ar,l.lot_code,l.expiry_date,l.quantity_remaining,
      CASE WHEN l.expiry_date<? THEN 'expired' WHEN l.expiry_date=? THEN 'expires_today' ELSE 'expiring_soon' END AS alert
      FROM inventory_lots l JOIN products p ON p.id=l.product_id
      WHERE l.status='active' AND l.quantity_remaining>0 AND l.expiry_date<=?
      ORDER BY l.expiry_date ASC,p.name_ar''',[language,day,day,until]);
  }

  static Future<int> submitSupplierReturn(Database db, {required int actorUserId, required int receiptLineId, int? lotId, required double quantity, required String reason}) async {
    if (!quantity.isFinite || quantity <= 0 || reason.trim().isEmpty) throw ArgumentError('حدد كمية صحيحة وسبب الإرجاع');
    return db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin','storekeeper']);
      final rows = await tx.rawQuery("SELECT l.product_id,l.unit_cost,l.received_qty,r.supplier_id,r.status AS receipt_status,p.expiry_tracked,b.approved_qty FROM purchase_receipt_lines l JOIN purchase_receipts r ON r.id=l.receipt_id JOIN products p ON p.id=l.product_id JOIN stock_balances b ON b.product_id=l.product_id WHERE l.id=?", [receiptLineId]);
      if (rows.isEmpty || rows.first['receipt_status'] != 'approved') throw StateError('سطر التوريد غير موجود أو غير معتمد');
      final line=rows.first, productId=line['product_id'] as int;
      final approved=(line['approved_qty'] as num).toDouble();
      if(quantity>approved+0.0000001) throw StateError('الكمية تتجاوز الرصيد المعتمد للصنف');
      final prior=await tx.rawQuery("SELECT COALESCE(SUM(quantity),0) AS qty FROM inventory_supplier_returns WHERE receipt_line_id=? AND status IN ('submitted','approved')",[receiptLineId]);
      final alreadyReturned=(prior.first['qty'] as num).toDouble();
      if(alreadyReturned+quantity>(line['received_qty'] as num).toDouble()+0.0000001) throw StateError('إجمالي الإرجاع يتجاوز كمية سطر التوريد الأصلي');
      int? resolvedLotId=lotId;
      if(line['expiry_tracked']==1) {
        List<Map<String,Object?>> lots;
        if(resolvedLotId==null) {
          lots=await tx.query('inventory_lots',where:"product_id=? AND receipt_line_id=? AND status='active' AND quantity_remaining>=?",whereArgs:[productId,receiptLineId,quantity],orderBy:'expiry_date ASC,id ASC',limit:1);
          if(lots.isEmpty) throw StateError('لا توجد دفعة صالحة بكمية كافية للإرجاع');
          resolvedLotId=lots.first['id'] as int;
        } else {
          lots=await tx.query('inventory_lots',where:"id=? AND product_id=? AND receipt_line_id=? AND status='active'",whereArgs:[resolvedLotId,productId,receiptLineId],limit:1);
          if(lots.isEmpty || (lots.first['quantity_remaining'] as num).toDouble()<quantity) throw StateError('كمية الدفعة المتاحة للإرجاع غير كافية');
        }
      }
      final doc='SRET-'+DateTime.now().microsecondsSinceEpoch.toString();
      final id=await tx.insert('inventory_supplier_returns',{'document_no':doc,'receipt_line_id':receiptLineId,'lot_id':resolvedLotId,'product_id':productId,'supplier_id':line['supplier_id'],'quantity':quantity,'unit_cost_snapshot':line['unit_cost'],'reason':reason.trim(),'status':'submitted','created_by':actorUserId,'created_at':_now()});
      await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'supplier_return_submitted','entity_type':'inventory_supplier_return','entity_id':id,'details':doc+' quantity='+quantity.toString(),'created_at':_now()});
      return id;
    });
  }

  static Future<List<Map<String,Object?>>> supplierReturns(Database db,{required int actorUserId,bool pendingOnly=false,String language='ar'}) async {
    await _role(db,actorUserId,['admin','storekeeper']);
    final actor=await db.query('users',columns:['role'],where:'id=?',whereArgs:[actorUserId],limit:1);
    final columns=actor.first['role']=='admin'?'x.*':"x.id,x.document_no,x.receipt_line_id,x.lot_id,x.product_id,x.supplier_id,x.quantity,x.reason,x.status,x.created_by,x.created_at,x.reviewed_by,x.reviewed_at,x.review_note";
    return db.rawQuery("SELECT "+columns+",COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code='ar'),p.name_ar) AS name_ar,s.name AS supplier_name FROM inventory_supplier_returns x JOIN products p ON p.id=x.product_id JOIN suppliers s ON s.id=x.supplier_id "+(pendingOnly?"WHERE x.status='submitted' ":"")+"ORDER BY x.id DESC LIMIT 200",[language]);
  }

  static Future<void> reviewSupplierReturn(Database db,{required int actorUserId,required int returnId,required bool approve,required String note}) async {
    if(note.trim().isEmpty) throw ArgumentError('ملاحظة المراجعة مطلوبة');
    await db.transaction((tx) async {
      await _role(tx,actorUserId,['admin']);
      final rows=await tx.query('inventory_supplier_returns',where:"id=? AND status='submitted'",whereArgs:[returnId],limit:1);
      if(rows.isEmpty) throw StateError('طلب إرجاع المورد تمت مراجعته مسبقاً');
      final r=rows.first,now=_now();
      if(approve) {
        final qty=(r['quantity'] as num).toDouble(),pid=r['product_id'] as int,lotId=r['lot_id'] as int?;
        final changed=await tx.rawUpdate('UPDATE stock_balances SET on_hand=on_hand-?,approved_qty=approved_qty-?,updated_at=? WHERE product_id=? AND on_hand>=? AND approved_qty>=?', [qty,qty,now,pid,qty,qty]);
        if(changed!=1) throw StateError('الرصيد المتاح غير كافٍ لتنفيذ إرجاع المورد');
        if(lotId!=null) {
          final lotChanged=await tx.rawUpdate("UPDATE inventory_lots SET quantity_remaining=quantity_remaining-?,status=CASE WHEN quantity_remaining-?<=0.0000001 THEN 'depleted' ELSE status END WHERE id=? AND status='active' AND quantity_remaining>=?",[qty,qty,lotId,qty]);
          if(lotChanged!=1) throw StateError('كمية الدفعة لم تعد متاحة للإرجاع');
          await tx.insert('inventory_lot_movements',{'lot_id':lotId,'product_id':pid,'quantity_delta':-qty,'source_ref':'supplier_return:$returnId','actor_user_id':actorUserId,'created_at':now});
        }
        final move=await tx.insert('stock_movements',{'product_id':pid,'movement_type':'supplier_return','quantity_delta':-qty,'source_type':'inventory_supplier_return','source_id':returnId,'idempotency_key':'supplier-return:$returnId','actor_user_id':actorUserId,'note':note.trim(),'occurred_at':now});
        final amount=qty*(r['unit_cost_snapshot'] as num).toDouble();
        await tx.insert('supplier_ledger',{'supplier_id':r['supplier_id'],'receipt_id':null,'entry_type':'supplier_return','debit':0.0,'credit':amount,'note':'إرجاع مورد '+r['document_no'].toString(),'actor_user_id':actorUserId,'created_at':now});
        if(amount>0) {
          final ap=await tx.query('accounts',columns:['id'],where:"code='AP' AND is_active=1",limit:1);
          final inv=await tx.query('accounts',columns:['id'],where:"code='INVENTORY' AND is_active=1",limit:1);
          if(ap.isEmpty||inv.isEmpty) throw StateError('حساب الموردين أو المخزون غير موجود');
          final entry=await tx.insert('journal_entries',{'entry_no':'J-SRET-'+returnId.toString(),'source_type':'inventory_supplier_return','source_id':returnId,'description':'اعتماد إرجاع مورد '+r['document_no'].toString(),'actor_user_id':actorUserId,'created_at':now});
          await tx.insert('journal_lines',{'entry_id':entry,'account_id':ap.first['id'],'debit':amount,'credit':0.0});
          await tx.insert('journal_lines',{'entry_id':entry,'account_id':inv.first['id'],'debit':0.0,'credit':amount});
        }
        await tx.update('inventory_supplier_returns',{'status':'approved','reviewed_by':actorUserId,'reviewed_at':now,'review_note':note.trim()},where:"id=? AND status='submitted'",whereArgs:[returnId]);
        await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'supplier_return_approved','entity_type':'inventory_supplier_return','entity_id':returnId,'details':'movement='+move.toString()+'; amount='+amount.toString(),'created_at':now});
      } else {
        await tx.update('inventory_supplier_returns',{'status':'rejected','reviewed_by':actorUserId,'reviewed_at':now,'review_note':note.trim()},where:"id=? AND status='submitted'",whereArgs:[returnId]);
        await tx.insert('audit_logs',{'actor_user_id':actorUserId,'action':'supplier_return_rejected','entity_type':'inventory_supplier_return','entity_id':returnId,'details':note.trim(),'created_at':now});
      }
    });
  }

  /// Returns the base unit plus configured product-specific units. Quantities in stock are always stored in the product base unit.
  static Future<List<Map<String,Object?>>> productUnits(Database db, {required int actorUserId, required int productId, String language='ar', bool forPurchase=false, bool forIssue=false}) async {
    await _role(db,actorUserId,['admin','storekeeper']);
    final products=await db.query('products',columns:['base_unit'],where:'id=? AND is_active=1 AND is_stock_item=1',whereArgs:[productId],limit:1);
    if(products.isEmpty) throw StateError('الصنف غير صالح');
    final base=products.first['base_unit'].toString();
    final rows=await db.query('inventory_product_units',where:'product_id=? AND is_active=1',whereArgs:[productId],orderBy:'conversion_to_base DESC');
    final result=<Map<String,Object?>>[
      {'id':0,'product_id':productId,'unit_name_ar':base,'unit_name_en':base,'unit_name_fr':base,'unit_name':base,'conversion_to_base':1.0,'is_purchase_unit':1,'is_issue_unit':1,'is_base_unit':1}
    ];
    for(final row in rows){
      if(forPurchase && row['is_purchase_unit']!=1) continue;
      if(forIssue && row['is_issue_unit']!=1) continue;
      final name=language=='en' && (row['unit_name_en'] as String).isNotEmpty?row['unit_name_en']:language=='fr' && (row['unit_name_fr'] as String).isNotEmpty?row['unit_name_fr']:row['unit_name_ar'];
      result.add({...row,'unit_name':name,'is_base_unit':0});
    }
    return result;
  }

  static Future<int> saveProductUnit(Database db, {required int actorUserId, required int productId, int? unitId, required String nameAr, required String nameEn, required String nameFr, required double conversionToBase, required bool purchaseEnabled, required bool issueEnabled}) async {
    if(nameAr.trim().isEmpty || !conversionToBase.isFinite || conversionToBase<=0 || (!purchaseEnabled && !issueEnabled)) throw ArgumentError('اسم الوحدة ومعامل التحويل والاستخدام غير صحيحة');
    return db.transaction((tx) async {
      await _role(tx,actorUserId,['admin']);
      final p=await tx.query('products',columns:['base_unit'],where:'id=? AND is_active=1 AND is_stock_item=1',whereArgs:[productId],limit:1);
      if(p.isEmpty) throw StateError('الصنف غير صالح');
      if(nameAr.trim()==p.first['base_unit'].toString()) throw ArgumentError('وحدة الأساس موجودة تلقائياً ولا تحتاج إلى إضافة');
      final now=_now();
      final existing=unitId==null?await tx.query('inventory_product_units',columns:['id'],where:'product_id=? AND unit_name_ar=?',whereArgs:[productId,nameAr.trim()],limit:1):await tx.query('inventory_product_units',columns:['id'],where:'id=? AND product_id=?',whereArgs:[unitId,productId],limit:1);
      if(unitId!=null && existing.isEmpty) throw StateError('وحدة القياس غير مرتبطة بهذا الصنف');
      final values={'unit_name_ar':nameAr.trim(),'unit_name_en':nameEn.trim(),'unit_name_fr':nameFr.trim(),'conversion_to_base':conversionToBase,'is_purchase_unit':purchaseEnabled?1:0,'is_issue_unit':issueEnabled?1:0,'is_active':1,'updated_at':now};
      if(existing.isNotEmpty){
        await tx.update('inventory_product_units',values,where:'id=?',whereArgs:[existing.first['id']]);
        return existing.first['id'] as int;
      }
      return tx.insert('inventory_product_units',{'product_id':productId,'unit_name_ar':nameAr.trim(),...values,'created_by':actorUserId,'created_at':now});
    });
  }

  static Future<void> deactivateProductUnit(Database db, {required int actorUserId, required int unitId}) async {
    await db.transaction((tx) async {
      await _role(tx,actorUserId,['admin']);
      final changed=await tx.update('inventory_product_units',{'is_active':0,'updated_at':_now()},where:'id=? AND is_active=1',whereArgs:[unitId]);
      if(changed!=1) throw StateError('وحدة القياس غير موجودة أو معطلة');
    });
  }

  static Future<double> toBaseQuantity(Database db, {required int actorUserId, required int productId, required double quantity, required int unitId, bool forPurchase=false, bool forIssue=false}) async {
    if(!quantity.isFinite || quantity<=0) throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');
    final units=await productUnits(db,actorUserId:actorUserId,productId:productId,forPurchase:forPurchase,forIssue:forIssue);
    final matches=units.where((u)=>(u['id'] as int)==unitId).toList();
    if(matches.isEmpty) throw StateError('وحدة القياس غير متاحة لهذا الاستخدام');
    final result=quantity*(matches.first['conversion_to_base'] as num).toDouble();
    if(!result.isFinite || result<=0) throw ArgumentError('نتيجة تحويل الكمية غير صحيحة');
    return result;
  }

  static Future<double> fromBaseQuantity(Database db, {required int actorUserId, required int productId, required double baseQuantity, required int unitId}) async {
    if(!baseQuantity.isFinite || baseQuantity<0) throw ArgumentError('رصيد المخزون غير صحيح');
    final units=await productUnits(db,actorUserId:actorUserId,productId:productId);
    final matches=units.where((u)=>(u['id'] as int)==unitId).toList();
    if(matches.isEmpty) throw StateError('وحدة القياس غير متاحة');
    return baseQuantity/(matches.first['conversion_to_base'] as num).toDouble();
  }

  static Future<void> setReorderRule(Database db, {required int actorUserId, required int productId, required double minimumQty, required double reorderQty}) async {
    if (!minimumQty.isFinite || minimumQty < 0 || !reorderQty.isFinite || reorderQty < 0) throw ArgumentError('حدود إعادة الطلب غير صحيحة');
    await db.transaction((tx) async {
      await _role(tx, actorUserId, ['admin']);
      final p = await tx.query('products', columns: ['id'], where: 'id=? AND is_active=1 AND is_stock_item=1', whereArgs: [productId], limit: 1);
      if (p.isEmpty) throw StateError('الصنف غير صالح');
      await tx.insert('inventory_reorder_rules', {'product_id': productId, 'minimum_qty': minimumQty, 'reorder_qty': reorderQty, 'updated_by': actorUserId, 'updated_at': _now()}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
