import 'dart:typed_data';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'package:printing/printing.dart';
import '../data/app_database.dart';

class DocumentService {
  static Future<Uint8List> _pdf(String html) async => HtmlToPdfConverter().convertHtmlToPdfBytes(html:html);
  static String _e(Object? value) => (value?.toString() ?? '')
      .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
      .replaceAll('"','&quot;').replaceAll("'","&#39;");

  static String _page(String title,String body,{String language='ar'}) {
    final isArabic=language=='ar';
    final direction=isArabic?'rtl':'ltr';
    final footer=isArabic
      ? 'تم إنشاء المستند من سجلات النظام. الأرقام المعروضة مطابقة للبيانات المسجلة.'
      : language=='fr'
        ? 'Document généré à partir des enregistrements du système. Les chiffres correspondent aux données enregistrées.'
        : 'This document was generated from system records. Figures match the recorded data.';
    return '''
<!doctype html><html lang="${_e(language)}" dir="$direction"><head><meta charset="utf-8">
<style>
@page{size:A4;margin:14mm}body{font-family:Arial,"Noto Naskh Arabic",sans-serif;direction:$direction;color:#111;font-size:12px}
h1{text-align:center;font-size:21px;margin:0 0 8px}h2{font-size:15px;margin:14px 0 6px}
.meta{display:flex;justify-content:space-between;gap:12px;margin:12px 0}
table{width:100%;border-collapse:collapse;margin-top:10px}th,td{border:1px solid #777;padding:6px;text-align:start}
th{background:#eee}.totals{width:55%;margin-inline-start:auto;margin-top:14px}.muted{color:#555;font-size:10px}
</style></head><body><h1>NaeemSoft Restaurant</h1><h2 style="text-align:center">${_e(title)}</h2>$body
<p class="muted">${_e(footer)}</p>
</body></html>''';
  }

  static Future<String> _saleHtml(int saleId) async {
    final db=await AppDatabase.instance.database;
    final head=await db.rawQuery("SELECT s.*,c.name AS customer_name,u.display_name AS cashier_name FROM sales s LEFT JOIN customers c ON c.id=s.customer_id LEFT JOIN users u ON u.id=s.cashier_user_id WHERE s.id=?",[saleId]);
    if(head.isEmpty)throw StateError('الفاتورة غير موجودة');
    final s=head.first;
    final lines=await db.query('sale_lines',where:'sale_id=?',whereArgs:[saleId],orderBy:'id');
    final rows=lines.map((l)=>'<tr><td>${_e(l['product_name_snapshot'])}</td><td>${_e(l['quantity'])} ${_e(l['unit_snapshot'])}</td><td>${_e(l['unit_price'])}</td><td>${_e(l['line_total'])}</td></tr>').join();
    final body='''
<div class="meta"><div>رقم الفاتورة: <b>${_e(s['invoice_no'])}</b><br>التاريخ: ${_e(s['created_at'])}</div>
<div>الزبون: ${_e(s['customer_name']??'زبون نقدي')}<br>الكاشير: ${_e(s['cashier_name'])}</div></div>
<table><thead><tr><th>الصنف</th><th>الكمية</th><th>سعر الوحدة</th><th>الإجمالي</th></tr></thead><tbody>$rows</tbody></table>
<table class="totals"><tr><th>الإجمالي قبل الخصم</th><td>${_e(s['subtotal'])}</td></tr><tr><th>الخصم</th><td>${_e(s['discount'])}</td></tr><tr><th>الصافي</th><td><b>${_e(s['total'])}</b></td></tr><tr><th>المدفوع</th><td>${_e(s['paid'])}</td></tr><tr><th>المتبقي</th><td>${_e(s['balance'])}</td></tr></table>''';
    return _page('فاتورة مبيعات',body);
  }

  static Future<String> _stockHtml() async {
    final db=await AppDatabase.instance.database;
    final rows=await db.rawQuery("SELECT p.name_ar,p.base_unit,COALESCE(b.approved_qty,0) AS qty,COALESCE(b.unapproved_qty,0) AS pending,COALESCE(b.weighted_average_cost,0) AS cost FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id WHERE p.is_active=1 AND p.is_stock_item=1 ORDER BY p.name_ar");
    final body='<p>تاريخ التقرير: ${_e(DateTime.now().toLocal())}</p><table><thead><tr><th>الصنف</th><th>الوحدة</th><th>الرصيد المعتمد</th><th>قيد الاعتماد</th><th>متوسط التكلفة</th><th>قيمة الرصيد</th></tr></thead><tbody>${rows.map((r){final q=(r['qty'] as num).toDouble();final c=(r['cost'] as num).toDouble();return '<tr><td>${_e(r['name_ar'])}</td><td>${_e(r['base_unit'])}</td><td>${q}</td><td>${_e(r['pending'])}</td><td>${c.toStringAsFixed(2)}</td><td>${(q*c).toStringAsFixed(2)}</td></tr>';}).join()}</tbody></table>';
    return _page('تقرير أرصدة المخزون',body);
  }


  static String _docText(String ar,String language) {
    const values=<String,Map<String,String>>{
      'إذن صرف مخزني':{'en':'Stock Issue Voucher','fr':'Bon de sortie de stock'},
      'سند مرتجع من المطبخ':{'en':'Kitchen Return Voucher','fr':'Bon de retour de cuisine'},
      'محضر هدر / تلف':{'en':'Waste / Damage Report','fr':'Rapport de perte / dommage'},
      'سند حجز مخزون':{'en':'Stock Quarantine Voucher','fr':'Bon de mise en quarantaine'},
      'كشف جرد فعلي':{'en':'Physical Stocktake','fr':'Inventaire physique'},
      'سند إرجاع إلى المورد':{'en':'Supplier Return Voucher','fr':'Bon de retour fournisseur'},
      'الصنف':{'en':'Item','fr':'Article'},'الكمية':{'en':'Quantity','fr':'Quantité'},
      'الوحدة':{'en':'Unit','fr':'Unité'},'الحالة / البيان':{'en':'Status / Details','fr':'État / Détails'},
      'الكمية الفعلية':{'en':'Counted Quantity','fr':'Quantité comptée'},
      'النظام / الفرق':{'en':'System / Difference','fr':'Système / Écart'},
      'رقم المستند:':{'en':'Document No:','fr':'N° du document :'},
      'التاريخ:':{'en':'Date:','fr':'Date :'},'الحالة:':{'en':'Status:','fr':'État :'},
      'الجهة / المورد:':{'en':'Department / Supplier:','fr':'Service / Fournisseur :'},
      'السبب / الملاحظة:':{'en':'Reason / Note:','fr':'Motif / Note :'},
      'اعتماد / استلام:':{'en':'Approved / Received by:','fr':'Approuvé / Reçu par :'},
      'تقرير حركة المخزون':{'en':'Stock Movement Report','fr':'Rapport des mouvements de stock'},'رقم الحركة':{'en':'Movement No.','fr':'N° du mouvement'},'نوع الحركة':{'en':'Movement type','fr':'Type de mouvement'} ,'الملاحظة':{'en':'Note','fr':'Note'},'التاريخ':{'en':'Date','fr':'Date'},
      'النظام:':{'en':'System:','fr':'Système :'},'الفرق:':{'en':'Difference:','fr':'Écart :'},
      'submitted':{'en':'Submitted','fr':'Soumis'},'approved':{'en':'Approved','fr':'Approuvé'},'rejected':{'en':'Rejected','fr':'Rejeté'},'issued':{'en':'Issued','fr':'Sorti'},'partially_issued':{'en':'Partially issued','fr':'Partiellement sorti'},'good':{'en':'Good','fr':'Conforme'},'damaged':{'en':'Damaged','fr':'Endommagé'},'quarantine':{'en':'Quarantine','fr':'Quarantaine'},'blocked':{'en':'Blocked','fr':'Bloqué'},'released':{'en':'Released','fr':'Libéré'},'written_off':{'en':'Written off','fr':'Passé en perte'},
      "purchase_pending":{'en':"Pending receipt",'fr':"Réception en attente"},
      "purchase_approved":{'en':"Receipt approved",'fr':"Réception approuvée"},
      "purchase_rejected":{'en':"Receipt rejected",'fr':"Réception rejetée"},
      "sale":{'en':"Sale",'fr':"Vente"},
      "sale_return":{'en':"Sales return",'fr':"Retour de vente"},
      "issue":{'en':"Department issue",'fr':"Sortie vers service"},
      "kitchen_handover":{'en':"Kitchen handover",'fr':"Transfert à la cuisine"},
      "kitchen_handover_return":{'en':"Kitchen return",'fr':"Retour de cuisine"},
      "issue_return":{'en':"Issue return",'fr':"Retour de sortie"},
      "quarantine_out":{'en':"Quarantine",'fr':"Mise en quarantaine"},
      "quarantine_release":{'en':"Quarantine release",'fr':"Fin de quarantaine"},
      "waste":{'en':"Waste",'fr':"Perte"},
      "supplier_return":{'en':"Supplier return",'fr':"Retour fournisseur"},
      "count_adjustment":{'en':"Stocktake adjustment",'fr':"Ajustement d’inventaire"},
    };
    return values[ar]?[language]??ar;
  }

  static Future<String> _inventoryHtml(String type,int id,String language) async {
    final db=await AppDatabase.instance.database;
    String title='';
    Map<String,Object?> head={};
    List<Map<String,Object?>> rows=[];
    String columns='<th>${_docText('الصنف',language)}</th><th>${_docText('الكمية',language)}</th><th>${_docText('الوحدة',language)}</th><th>${_docText('الحالة / البيان',language)}</th>';
    if(type=='receipt'){
      final h=await db.rawQuery('SELECT r.*,s.name AS supplier_name FROM purchase_receipts r JOIN suppliers s ON s.id=r.supplier_id WHERE r.id=?',[id]);
      if(h.isEmpty)throw StateError('سند الاستلام غير موجود');head=h.first;title='سند استلام توريد';
      rows=await db.rawQuery('SELECT COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=?),p.name_ar) AS name_ar,l.received_qty AS quantity,p.base_unit AS unit,l.entered_qty,l.entered_unit_name FROM purchase_receipt_lines l JOIN products p ON p.id=l.product_id WHERE l.receipt_id=?',[language,'ar',id]);
      rows=rows.map((r){final copy=Map<String,Object?>.from(r);copy['detail']=(r['entered_qty']??r['quantity']).toString()+' '+((r['entered_unit_name']??'').toString().isEmpty?r['unit'].toString():r['entered_unit_name'].toString());return copy;}).toList();
    }else if(type=='issue'){
      final h=await db.query('stock_issue_requests',where:'id=?',whereArgs:[id],limit:1);
      if(h.isEmpty)throw StateError('إذن الصرف غير موجود');head=h.first;title='إذن صرف مخزني';
      rows=await db.rawQuery('SELECT COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=?),p.name_ar) AS name_ar,l.issued_qty AS quantity,l.unit_snapshot AS unit,r.status AS detail FROM stock_issue_lines l JOIN products p ON p.id=l.product_id JOIN stock_issue_requests r ON r.id=l.request_id WHERE l.request_id=?',[language,'ar',id]);
    }else if(type=='return'){
      final h=await db.rawQuery('SELECT r.*,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=?),p.name_ar) AS name_ar FROM stock_return_records r JOIN products p ON p.id=r.product_id WHERE r.id=?',[language,'ar',id]);
      if(h.isEmpty)throw StateError('سجل المرتجع غير موجود');head=h.first;title='سند مرتجع من المطبخ';
      rows=[{'name_ar':head['name_ar'],'quantity':head['quantity'],'unit':head['unit_snapshot'],'detail':head['condition_code']}];
    }else if(type=='waste'){
      final h=await db.rawQuery('SELECT w.*,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=?),p.name_ar) AS name_ar,p.base_unit FROM waste_records w JOIN products p ON p.id=w.product_id WHERE w.id=?',[language,'ar',id]);
      if(h.isEmpty)throw StateError('سجل الهدر غير موجود');head=h.first;title='محضر هدر / تلف';
      rows=[{'name_ar':head['name_ar'],'quantity':head['quantity'],'unit':head['base_unit'],'detail':head['reason_note']}];
    }else if(type=='quarantine'){
      final h=await db.rawQuery('SELECT q.*,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=?),p.name_ar) AS name_ar FROM inventory_quarantine q JOIN products p ON p.id=q.product_id WHERE q.id=?',[language,'ar',id]);
      if(h.isEmpty)throw StateError('سجل الحجز غير موجود');head=h.first;title='سند حجز مخزون';
      rows=[{'name_ar':head['name_ar'],'quantity':head['quantity'],'unit':head['unit_snapshot'],'detail':head['reason']}];
    }else if(type=='stocktake'){
      final h=await db.query('stocktakes',where:'id=?',whereArgs:[id],limit:1);
      if(h.isEmpty)throw StateError('سجل الجرد غير موجود');head=h.first;title='كشف جرد فعلي';
      rows=await db.rawQuery('SELECT COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=?),p.name_ar) AS name_ar,p.base_unit AS unit,l.counted_qty AS quantity,l.system_qty,l.difference_qty FROM stocktake_lines l JOIN products p ON p.id=l.product_id WHERE l.stocktake_id=?',[language,'ar',id]);
      rows=rows.map((r){final copy=Map<String,Object?>.from(r);copy['detail']=_docText('النظام:',language)+' '+r['system_qty'].toString()+' • '+_docText('الفرق:',language)+' '+r['difference_qty'].toString();return copy;}).toList();
      columns='<th>${_docText('الصنف',language)}</th><th>${_docText('الكمية الفعلية',language)}</th><th>${_docText('الوحدة',language)}</th><th>${_docText('النظام / الفرق',language)}</th>';
    }else if(type=='supplier_return'){
      final h=await db.rawQuery('SELECT x.*,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=?),p.name_ar) AS name_ar,s.name AS supplier_name FROM inventory_supplier_returns x JOIN products p ON p.id=x.product_id JOIN suppliers s ON s.id=x.supplier_id WHERE x.id=?',[language,'ar',id]);
      if(h.isEmpty)throw StateError('طلب إرجاع المورد غير موجود');head=h.first;title='سند إرجاع إلى المورد';
      rows=[{'name_ar':head['name_ar'],'quantity':head['quantity'],'unit':'','detail':head['reason']}];
    }else{throw ArgumentError('نوع مستند مخزون غير معروف');}
    final trs=rows.map((r)=>'<tr><td>${_e(r['name_ar'])}</td><td>${_e(r['quantity'])}</td><td>${_e(r['unit'])}</td><td>${_e(r['detail'])}</td></tr>').join();
    final statusValue=_docText((head['status']??head['condition_code']??'').toString(),language);
    final body='<div class="meta"><div>${_docText('رقم المستند:',language)} <b>${_e(head['document_no']??id)}</b><br>${_docText('التاريخ:',language)} ${_e(head['created_at']??head['requested_at']??'')}</div><div>${_docText('الحالة:',language)} ${_e(statusValue)}<br>${_docText('الجهة / المورد:',language)} ${_e(head['destination']??head['supplier_name']??'')}</div></div><p>${_docText('السبب / الملاحظة:',language)} ${_e(head['reason']??head['review_note']??'')}</p><table><thead><tr>$columns</tr></thead><tbody>$trs</tbody></table><p>${_docText('اعتماد / استلام:',language)} ____________________</p>';
    return _page(_docText(title,language),body,language:language);
  }

  static Future<String> _inventoryMovementHtml(String language) async {
    final db=await AppDatabase.instance.database;
    final rows=await db.rawQuery("SELECT m.id,m.movement_type,m.quantity_delta,m.note,m.occurred_at,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=?),p.name_ar) AS name_ar FROM stock_movements m JOIN products p ON p.id=m.product_id ORDER BY m.id DESC LIMIT 500",[language,'ar']);
    final trs=rows.map((r){
      final type=(r['movement_type']??'').toString();
      final movement=_docText(type,language);
      return '<tr><td>${_e(r['id'])}</td><td>${_e(r['name_ar'])}</td><td>${_e(movement)}</td><td>${_e(r['quantity_delta'])}</td><td>${_e(r['note'])}</td><td>${_e(r['occurred_at'])}</td></tr>';
    }).join();
    final columns='<th>${_docText('رقم الحركة',language)}</th><th>${_docText('الصنف',language)}</th><th>${_docText('نوع الحركة',language)}</th><th>${_docText('الكمية',language)}</th><th>${_docText('الملاحظة',language)}</th><th>${_docText('التاريخ',language)}</th>';
    return _page(_docText('تقرير حركة المخزون',language),'<table><thead><tr>$columns</tr></thead><tbody>$trs</tbody></table>',language:language);
  }
  static Future<void> printInventoryMovementReport({String language='ar'}) async {
    final bytes=await _pdf(await _inventoryMovementHtml(language));
    await Printing.layoutPdf(name:'inventory-movements',onLayout:(_) async=>bytes);
  }
  static Future<void> shareInventoryMovementReport({String language='ar'}) async {
    final bytes=await _pdf(await _inventoryMovementHtml(language));
    await Printing.sharePdf(bytes:bytes,filename:'inventory-movements.pdf');
  }

  static Future<void> printInventoryDocument(String type,int id,{String language='ar'}) async {
    final bytes=await _pdf(await _inventoryHtml(type,id,language));
    await Printing.layoutPdf(name:'inventory-$type-$id',onLayout:(_) async=>bytes);
  }
  static Future<void> shareInventoryDocument(String type,int id,{String language='ar'}) async {
    final bytes=await _pdf(await _inventoryHtml(type,id,language));
    await Printing.sharePdf(bytes:bytes,filename:'inventory-$type-$id.pdf');
  }

  static Future<void> printSaleInvoice(int saleId) async {
    final html=await _saleHtml(saleId);
    final bytes=await _pdf(html);
    await Printing.layoutPdf(name:'Sales invoice',onLayout:(_) async => bytes);
  }
  static Future<void> shareSaleInvoice(int saleId) async {
    final html=await _saleHtml(saleId);
    final bytes=await _pdf(html);
    await Printing.sharePdf(bytes:bytes,filename:'sales-invoice-$saleId.pdf');
  }
  static Future<void> printStockReport() async {
    final html=await _stockHtml();
    final bytes=await _pdf(html);
    await Printing.layoutPdf(name:'Stock report',onLayout:(_) async => bytes);
  }
  static Future<void> shareStockReport() async {
    final html=await _stockHtml();
    final bytes=await _pdf(html);
    await Printing.sharePdf(bytes:bytes,filename:'stock-report.pdf');
  }
}
