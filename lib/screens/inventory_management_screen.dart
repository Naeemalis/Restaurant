import 'package:flutter/material.dart';
import '../data/app_database.dart';
import '../data/inventory_service.dart';
import '../services/document_service.dart';
import 'purchase_screen.dart';

class InventoryManagementScreen extends StatefulWidget {
  final Map<String,Object?> user;
  const InventoryManagementScreen({super.key,required this.user});
  @override State<InventoryManagementScreen> createState()=>_InventoryManagementScreenState();
}
class _InventoryManagementScreenState extends State<InventoryManagementScreen> {
  List<Map<String,Object?>> balances=[],requests=[],products=[],quarantine=[],waste=[],expiry=[],supplierReturnRows=[],issueReturnRows=[],stocktakeRows=[],movementRows=[];
  bool loading=true;
  String itemQuery='',stockFilter='all',categoryFilter='all',movementTypeFilter='all',movementEmployeeQuery='';
  DateTime? movementFrom,movementTo;
  int pendingReceiptsCount=0,pendingStocktakesCount=0;
  List<Map<String,Object?>> get filteredBalances => balances.where((p){
    final name=(p['name_ar']??'').toString().toLowerCase();
    final approved=(p['approved_qty'] as num).toDouble();
    final pending=(p['unapproved_qty'] as num).toDouble();
    final minimum=(p['minimum_qty'] as num).toDouble();
    final blocked=(p['quarantined_qty'] as num).toDouble();
    if(itemQuery.trim().isNotEmpty && !name.contains(itemQuery.trim().toLowerCase())) return false;
    if(categoryFilter=='none' && p['category_id']!=null) return false;
    if(categoryFilter!='all' && categoryFilter!='none' && p['category_id'].toString()!=categoryFilter) return false;
    if(stockFilter=='low' && !(minimum>0 && approved<=minimum)) return false;
    if(stockFilter=='out' && approved>0) return false;
    if(stockFilter=='pending' && pending<=0) return false;
    if(stockFilter=='quarantined' && blocked<=0) return false;
    return true;
  }).toList();
  List<Map<String,Object?>> get filteredMovements => movementRows.where((m){
    if(movementTypeFilter!='all' && m['movement_type']!=movementTypeFilter) return false;
    final itemName=(m['name_ar']??'').toString().toLowerCase();
    if(itemQuery.trim().isNotEmpty && !itemName.contains(itemQuery.trim().toLowerCase())) return false;
    if(categoryFilter=='none' && m['category_id']!=null) return false;
    if(categoryFilter!='all' && categoryFilter!='none' && m['category_id'].toString()!=categoryFilter) return false;
    final employee=(m['display_name']??'').toString().toLowerCase();
    if(movementEmployeeQuery.trim().isNotEmpty && !employee.contains(movementEmployeeQuery.trim().toLowerCase())) return false;
    final date=DateTime.tryParse((m['occurred_at']??'').toString());
    if(date!=null && movementFrom!=null && date.isBefore(DateTime(movementFrom!.year,movementFrom!.month,movementFrom!.day))) return false;
    if(date!=null && movementTo!=null && date.isAfter(DateTime(movementTo!.year,movementTo!.month,movementTo!.day,23,59,59))) return false;
    return true;
  }).toList();
  int get actorId=>widget.user['id'] as int;
  String get language=>(widget.user['preferred_language']??'ar').toString();
  bool get admin=>widget.user['role']=='admin';
  String tr(String ar) {
    final language=Localizations.localeOf(context).languageCode;
    if(language=='ar') return ar;
    const translations=<String,Map<String,String>>{
      "إدارة المخزون وأمين المخزن":{'en':"Inventory & Storekeeper",'fr':"Gestion du stock"},
      "طلب صرف":{'en':"Issue Request",'fr':"Demande de sortie"},
      "الأرصدة والتنبيهات":{'en':"Balances & Alerts",'fr':"Soldes et alertes"},
      "أذونات الصرف":{'en':"Issue Vouchers",'fr':"Bons de sortie"},
      "المرتجعات":{'en':"Returns",'fr':"Retours"},
      "الهدر والحجز":{'en':"Waste & Quarantine",'fr':"Pertes et quarantaine"},
      "الجرد":{'en':"Stocktake",'fr':"Inventaire"},
      "عدد الأصناف: ":{'en':"Items: ",'fr':"Articles : "},
      "أصناف وصلت حد إعادة الطلب: ":{'en':"Items at reorder level: ",'fr':"Articles au seuil de réapprovisionnement : "},
      "تسجيل دفعة / تاريخ صلاحية":{'en':"Register Lot / Expiry",'fr':"Enregistrer lot / péremption"},
      "تنبيهات الصلاحية: ":{'en':"Expiry alerts: ",'fr':"Alertes de péremption : "},
      "يعرض الدفعات المنتهية أو التي تنتهي خلال 30 يوماً":{'en':"Expired lots or lots expiring within 30 days",'fr':"Lots expirés ou arrivant à expiration sous 30 jours"},
      "الانتهاء: ":{'en':"Expiry: ",'fr':"Péremption : "},
      " • المتبقي: ":{'en':" • Remaining: ",'fr':" • Restant : "},
      "منتهي":{'en':"Expired",'fr':"Expiré"},
      "ينتهي اليوم":{'en':"Expires today",'fr':"Expire aujourd’hui"},
      "قريب الانتهاء":{'en':"Expiring soon",'fr':"Expire bientôt"},
      "المعتمد: ":{'en':"Approved: ",'fr':"Approuvé : "},
      "عهدة المطبخ: ":{'en':"Kitchen custody: ",'fr':"Stock de la cuisine : "},
      "إعادة طلب":{'en':"Reorder",'fr':"Réapprovisionnement"},
      "إنشاء طلب صرف مواد":{'en':"Create Stock Issue Request",'fr':"Créer une demande de sortie"},
      "تسليم افتتاحي لعهدة المطبخ":{'en':"Opening kitchen handover",'fr':"Transfert initial à la cuisine"},
      "تحويل إلى عهدة المطبخ - ينقص المخزن الرئيسي ويزيد رصيد المطبخ":{'en':"Transfer to kitchen custody — reduce main store and increase kitchen stock",'fr':"Transfert vers la réserve cuisine — diminuer le stock principal et augmenter le stock cuisine"},
      "لا توجد أذونات صرف":{'en':"No issue vouchers",'fr':"Aucun bon de sortie"},
      "الحالة: ":{'en':"Status: ",'fr':"État : "},
      " • مقدم الطلب: ":{'en':" • Requested by: ",'fr':" • Demandé par : "},
      " أصناف\\n":{'en':" items\\n",'fr':" articles\\n"},
      "مراجعة واعتماد الصرف":{'en':"Review and approve issue",'fr':"Examiner et approuver la sortie"},
      "رفض الطلب":{'en':"Reject request",'fr':"Rejeter la demande"},
      "طباعة إذن الصرف":{'en':"Print issue voucher",'fr':"Imprimer le bon de sortie"},
      "مشاركة إذن الصرف":{'en':"Share issue voucher",'fr':"Partager le bon de sortie"},
      "اختر إذن صرف مسجلاً لتسجيل الكمية المعادة وحالتها.":{'en':"Select an issued voucher to record returned quantity and condition.",'fr':"Sélectionnez un bon de sortie pour enregistrer la quantité et l’état du retour."},
      "طلبات إرجاع الموردين":{'en':"Supplier Return Requests",'fr':"Demandes de retour fournisseur"},
      "المورد: ":{'en':"Supplier: ",'fr':"Fournisseur : "},
      " • الكمية: ":{'en':" • Quantity: ",'fr':" • Quantité : "},
      " • الحالة: ":{'en':" • Status: ",'fr':" • État : "},
      "اعتماد الإرجاع":{'en':"Approve return",'fr':"Approuver le retour"},
      "رفض الإرجاع":{'en':"Reject return",'fr':"Rejeter le retour"},
      "طباعة سند الإرجاع":{'en':"Print return voucher",'fr':"Imprimer le bon de retour"},
      "مشاركة سند الإرجاع":{'en':"Share return voucher",'fr':"Partager le bon de retour"},
      "المرتجعات المسجلة":{'en':"Recorded Returns",'fr':"Retours enregistrés"},
      "المستلم: ":{'en':"Received by: ",'fr':"Reçu par : "},
      "تسجيل مرتجع":{'en':"Record return",'fr':"Enregistrer le retour"},
      "تسجيل هدر":{'en':"Record waste",'fr':"Enregistrer une perte"},
      "عزل كمية":{'en':"Quarantine quantity",'fr':"Mettre en quarantaine"},
      "سجلات الحجز":{'en':"Quarantine Records",'fr':"Registres de quarantaine"},
      "آخر سجلات الهدر":{'en':"Recent Waste Records",'fr':"Pertes récentes"},
      "إنشاء جرد فعلي وإرساله للمراجعة":{'en':"Create physical stocktake and submit for review",'fr':"Créer un inventaire physique et le soumettre"},
      "مراجعة الجردات المعلقة":{'en':"Review pending stocktakes",'fr':"Examiner les inventaires en attente"},
      "طباعة تقرير الحركة":{'en':'Print movement report','fr':'Imprimer le rapport des mouvements'},
      "مشاركة تقرير الحركة":{'en':'Share movement report','fr':'Partager le rapport des mouvements'},
      "آخر حركات المخزون":{'en':"Recent Stock Movements",'fr':"Mouvements récents du stock"},
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
      "submitted":{'en':"Submitted",'fr':"Soumis"},
      "approved":{'en':"Approved",'fr':"Approuvé"},
      "rejected":{'en':"Rejected",'fr':"Rejeté"},
      "issued":{'en':"Issued",'fr':"Sorti"},
      "partially_issued":{'en':"Partially issued",'fr':"Partiellement sorti"},
      "good":{'en':"Good",'fr':"Conforme"},
      "damaged":{'en':"Damaged",'fr':"Endommagé"},
      "quarantine":{'en':"Quarantine",'fr':"Quarantaine"},
      "blocked":{'en':"Blocked",'fr':"Bloqué"},
      "released":{'en':"Released",'fr':"Libéré"},
      "written_off":{'en':"Written off",'fr':"Passé en perte"},
      "آخر عمليات الجرد":{'en':'Recent Stocktakes','fr':'Inventaires récents'},
      "ضوابط الجرد":{'en':"Stocktake Controls",'fr':"Règles d’inventaire"},
      "لا يتغير الرصيد عند الإرسال. يعتمد المدير الجرد بعد التأكد من عدم وجود حركة لاحقة على الأصناف.":{'en':"Submitting a stocktake does not change balances. Admin approval applies it only if no later stock movement exists.",'fr':"La soumission ne modifie pas les soldes. L’approbation applique l’inventaire uniquement en l’absence de mouvement ultérieur."},
      "تسجيل تشغيلة وتاريخ صلاحية":{'en':"Register Batch and Expiry",'fr':"Enregistrer un lot et sa péremption"},
      "سطر التوريد المعتمد":{'en':"Approved receipt line",'fr':"Ligne de réception approuvée"},
      "رقم التشغيلة / الدفعة":{'en':"Lot / Batch Number",'fr':"Numéro de lot"},
      "كمية هذه الدفعة":{'en':"Batch quantity",'fr':"Quantité du lot"},
      "تاريخ الإنتاج YYYY-MM-DD (اختياري)":{'en':"Manufacture date YYYY-MM-DD (optional)",'fr':"Date de fabrication AAAA-MM-JJ (facultatif)"},
      "تاريخ الانتهاء YYYY-MM-DD":{'en':"Expiry date YYYY-MM-DD",'fr':"Date de péremption AAAA-MM-JJ"},
      "حفظ التشغيلة":{'en':"Save batch",'fr':"Enregistrer le lot"},
      "طلب إرجاع إلى المورد":{'en':"Return to Supplier",'fr':"Retourner au fournisseur"},
      "الصنف / فاتورة التوريد / المورد":{'en':"Item / Receipt / Supplier",'fr':"Article / Réception / Fournisseur"},
      "الكمية المراد إرجاعها":{'en':"Quantity to return",'fr':"Quantité à retourner"},
      "سبب الإرجاع":{'en':"Return reason",'fr':"Motif du retour"},
      "إرسال للمراجعة":{'en':"Submit for review",'fr':"Soumettre pour examen"},
      "تسجيل مرتجع • ":{'en':"Record Return • ",'fr':"Enregistrer le retour • "},
      "بند الصرف":{'en':"Issue line",'fr':"Ligne de sortie"},
      "الكمية المرتجعة":{'en':"Returned quantity",'fr':"Quantité retournée"},
      "حالة المرتجع":{'en':"Return condition",'fr':"État du retour"},
      "سليم - يعود للمخزون":{'en':"Good - return to stock",'fr':"Bon - retour au stock"},
      "تالف - حجز":{'en':"Damaged - quarantine",'fr':"Endommagé - quarantaine"},
      "يحتاج فحص - حجز":{'en':"Needs inspection - quarantine",'fr':"À inspecter - quarantaine"},
      "الجهة المعيدة":{'en':"Returning department",'fr':"Service retournant"},
      "السبب / الملاحظات":{'en':"Reason / Notes",'fr':"Motif / Notes"},
      "حفظ المرتجع":{'en':"Save return",'fr':"Enregistrer le retour"},
      "تسجيل هدر / تلف":{'en':"Record Waste / Damage",'fr':"Enregistrer perte / dommage"},
      "الصنف":{'en':"Product",'fr':"Article"},
      "الكمية":{'en':"Quantity",'fr':"Quantité"},
      "سبب الهدر":{'en':"Waste reason",'fr':"Motif de perte"},
      "تسجيل الهدر":{'en':"Record waste",'fr':"Enregistrer la perte"},
      "عزل كمية من المخزون":{'en':"Quarantine Stock",'fr':"Mettre le stock en quarantaine"},
      "سبب العزل (انتهاء / اشتباه / تلف)":{'en':"Quarantine reason (expired / suspected / damaged)",'fr':"Motif de quarantaine (expiré / suspect / endommagé)"},
      "عزل الكمية":{'en':"Quarantine quantity",'fr':"Mettre en quarantaine"},
      "القرار":{'en':"Decision",'fr':"Décision"},
      "إعادة للمخزون المتاح":{'en':"Release back to stock",'fr':"Remettre en stock"},
      "إتلاف نهائي":{'en':"Write off",'fr':"Passer en perte"},
      "ملاحظة المدير":{'en':"Admin note",'fr':"Note de l’administrateur"},
      "تنفيذ القرار":{'en':"Apply decision",'fr':"Appliquer la décision"},
      "حد إعادة الطلب • ":{'en':"Reorder Rule • ",'fr':"Règle de réapprovisionnement • "},
      "الحد الأدنى":{'en':"Minimum level",'fr':"Seuil minimum"},
      "كمية إعادة الطلب":{'en':"Reorder quantity",'fr':"Quantité de réapprovisionnement"},
      "حفظ":{'en':"Save",'fr':"Enregistrer"},
      "جرد فعلي للمخزون":{'en':"Physical Stocktake",'fr':"Inventaire physique"},
      "سجّل الرصيد المعتمد القابل للصرف فقط. استبعد التوريدات غير المعتمدة والكميات المحجوزة.":{'en':"Count only approved stock available for issue. Exclude unapproved receipts and quarantined quantities.",'fr':"Comptez uniquement le stock approuvé disponible. Excluez les réceptions non approuvées et les quantités en quarantaine."},
      "الفعلي":{'en':"Counted",'fr':"Compté"},
      "ملاحظات الجرد":{'en':"Stocktake notes",'fr':"Notes d’inventaire"},
      "إرسال للمدير":{'en':"Submit to Admin",'fr':"Envoyer à l’administrateur"},
      "الجردات المعلقة":{'en':"Pending Stocktakes",'fr':"Inventaires en attente"},
      "إغلاق":{'en':"Close",'fr':"Fermer"},
      "مراجعة الجرد رقم ":{'en':"Review Stocktake #",'fr':"Examiner l’inventaire n°"},
      "سيُرفض الاعتماد تلقائياً إذا حدثت حركة مخزون بعد تسجيل الجرد.":{'en':"Approval is blocked if any stock movement occurred after the count was recorded.",'fr':"L’approbation est bloquée si un mouvement de stock a eu lieu après le comptage."},
      "طباعة كشف الجرد":{'en':"Print stocktake",'fr':"Imprimer l’inventaire"},
      "مشاركة كشف الجرد":{'en':"Share stocktake",'fr':"Partager l’inventaire"},
      "رفض":{'en':"Reject",'fr':"Rejeter"},
      "اعتماد":{'en':"Approve",'fr':"Approuver"},
      "تعذر تحميل إدارة المخزون: ":{'en':"Could not load inventory: ",'fr':"Impossible de charger le stock : "},
      "لا توجد أسطر توريد معتمدة لربط التشغيلات بها":{'en':"No approved receipt lines are available for batch registration",'fr':"Aucune ligne de réception approuvée pour enregistrer un lot"},
      " • كمية ":{'en':" • Qty ",'fr':" • Qté "},
      "إلغاء":{'en':"Cancel",'fr':"Annuler"},
      "أدخل كمية صحيحة":{'en':"Enter a valid quantity",'fr':"Saisissez une quantité valide"},
      "تم تسجيل الدفعة رقم ":{'en':"Batch registered: #",'fr':"Lot enregistré : n°"},
      " وربطها بالتوريد.":{'en':" and linked to the receipt.",'fr':" et lié à la réception."},
      "لا توجد فواتير توريد معتمدة للإرجاع":{'en':"No approved receipts available for return",'fr':"Aucune réception approuvée disponible pour retour"},
      "تم إرسال طلب إرجاع المورد رقم ":{'en':"Supplier return request submitted: #",'fr':"Demande de retour fournisseur envoyée : n°"},
      " لاعتماد المدير.":{'en':" for Admin approval.",'fr':" pour approbation de l’administrateur."},
      "اعتماد إرجاع المورد":{'en':"Approve supplier return",'fr':"Approuver le retour fournisseur"},
      "رفض إرجاع المورد":{'en':"Reject supplier return",'fr':"Rejeter le retour fournisseur"},
      "ملاحظة / سبب القرار":{'en':"Review note / reason",'fr':"Note / motif de décision"},
      "تأكيد":{'en':"Confirm",'fr':"Confirmer"},
      "تم اعتماد الإرجاع وتحديث المخزون وحساب المورد.":{'en':"Return approved; stock and supplier account updated.",'fr':"Retour approuvé ; stock et compte fournisseur mis à jour."},
      "تم رفض طلب الإرجاع.":{'en':"Return request rejected.",'fr':"Demande de retour rejetée."},
      "تعذر تجهيز المستند: ":{'en':"Could not prepare document: ",'fr':"Impossible de préparer le document : "},
      "طلب صرف مواد":{'en':"Stock issue request",'fr':"Demande de sortie de stock"},
      "اسم الجهة / المطبخ":{'en':"Department / Kitchen",'fr':"Service / Cuisine"},
      "نوع الحركة":{'en':"Movement type",'fr':"Type de mouvement"},
      "صرف استهلاكي - يخصم من المخزون":{'en':"Consumption issue - deducted from stock",'fr':"Sortie de consommation - déduite du stock"},
      "تحويل إلى عهدة المطبخ - ينقص المخزن الرئيسي ويزيد رصيد المطبخ":{'en':"Internal kitchen handover - deducted when recipe is consumed",'fr':"Transfert interne à la cuisine - déduit lors de la consommation de la recette"},
      "اسم المستلم":{'en':"Receiver name",'fr':"Nom du réceptionnaire"},
      "سبب الصرف":{'en':"Issue reason",'fr':"Motif de sortie"},
      "إرسال الطلب":{'en':"Submit request",'fr':"Envoyer la demande"},
      "أدخل كميات صحيحة أكبر من صفر":{'en':"Enter valid quantities greater than zero",'fr':"Saisissez des quantités valides supérieures à zéro"},
      "تم إرسال طلب الصرف رقم ":{'en':"Issue request submitted: #",'fr':"Demande de sortie envoyée : n°"},
      " للمراجعة. لم يتغير الرصيد بعد.":{'en':" for review. Stock has not changed yet.",'fr':" pour examen. Le stock n’a pas encore changé."},
      "مراجعة ":{'en':"Review ",'fr':"Examiner "},
      "الجهة: ":{'en':"Department: ",'fr':"Service : "},
      " • المستلم: ":{'en':" • Receiver: ",'fr':" • Réceptionnaire : "},
      "السبب: ":{'en':"Reason: ",'fr':"Motif : "},
      "\\nالمطلوب: ":{'en':"\\nRequested: ",'fr':"\\nDemandé : "},
      " • صُرف: ":{'en':" • Issued: ",'fr':" • Sorti : "},
      " • المتاح: ":{'en':" • Available: ",'fr':" • Disponible : "},
      "صرف الآن":{'en':"Issue now",'fr':"Sortir maintenant"},
      "ملاحظة الاعتماد":{'en':"Approval note",'fr':"Note d’approbation"},
      "رجوع":{'en':"Back",'fr':"Retour"},
      "اعتماد الصرف":{'en':"Approve issue",'fr':"Approuver la sortie"},
      "كميات الصرف غير صحيحة":{'en':"Invalid issue quantities",'fr':"Quantités de sortie invalides"},
      "تم تسجيل كمية الصرف الجديدة وتحديث الرصيد.":{'en':"New issue quantity recorded and stock updated.",'fr':"Nouvelle quantité sortie enregistrée et stock mis à jour."},
      "سبب الرفض":{'en':"Rejection reason",'fr':"Motif du rejet"},
      "تأكيد الرفض":{'en':"Confirm rejection",'fr':"Confirmer le rejet"},
      "تم رفض الطلب وتسجيل السبب.":{'en':"Request rejected and reason recorded.",'fr':"Demande rejetée et motif enregistré."},
      "لا توجد أصناف في إذن الصرف":{'en':"No items in this issue voucher",'fr':"Aucun article dans ce bon de sortie"},
      " | متبقي: ":{'en':" | Remaining: ",'fr':" | Restant : "},
      "تم تسجيل المرتجع؛ السليم عاد للرصيد والتالف عُزل.":{'en':"Return recorded; good items restored, damaged items quarantined.",'fr':"Retour enregistré ; les articles conformes sont réintégrés, les endommagés mis en quarantaine."},
      "حدد الصنف والكمية":{'en':"Select an item and quantity",'fr':"Sélectionnez un article et une quantité"},
      "تم تسجيل الهدر وخصمه من الرصيد.":{'en':"Waste recorded and deducted from stock.",'fr':"Perte enregistrée et déduite du stock."},
      "تم عزل الكمية وإخراجها من الرصيد القابل للبيع.":{'en':"Quantity quarantined and removed from available stock.",'fr':"Quantité mise en quarantaine et retirée du stock disponible."},
      "معالجة حجز ":{'en':"Resolve quarantine ",'fr':"Traiter la quarantaine "},
      "الكمية: ":{'en':"Quantity: ",'fr':"Quantité : "},
      "\\nالسبب: ":{'en':"\\nReason: ",'fr':"\\nMotif : "},
      "إعادة للمخزون أو إتلاف":{'en':"Release or write off",'fr':"Libérer ou passer en perte"},
      "تمت معالجة سجل الحجز.":{'en':"Quarantine record resolved.",'fr':"Dossier de quarantaine traité."},
      "أدخل أرقاماً صحيحة":{'en':"Enter valid numbers",'fr':"Saisissez des nombres valides"},
      "تم تحديث حد إعادة الطلب.":{'en':"Reorder rule updated.",'fr':"Règle de réapprovisionnement mise à jour."},
      "دفتر: ":{'en':"Book: ",'fr':"Comptabilisé : "},
      "كميات الجرد يجب أن تكون أرقاماً غير سالبة":{'en':"Stocktake quantities must be non-negative numbers",'fr':"Les quantités d’inventaire doivent être positives ou nulles"},
      "تم إرسال الجرد رقم ":{'en':"Stocktake submitted: #",'fr':"Inventaire soumis : n°"},
      " دون تغيير المخزون حتى اعتماد المدير.":{'en':". Stock will not change until Admin approval.",'fr':". Le stock ne changera pas avant l’approbation."},
      "لا توجد عمليات جرد معلقة":{'en':"No pending stocktakes",'fr':"Aucun inventaire en attente"},
      "جرد رقم ":{'en':"Stocktake #",'fr':"Inventaire n°"},
      "بواسطة ":{'en':"By ",'fr':"Par "},
      "النظام: ":{'en':"System: ",'fr':"Système : "},
      " • الفعلي: ":{'en':" • Counted: ",'fr':" • Compté : "},
      "الفرق: ":{'en':"Difference: ",'fr':"Écart : "},
      "اعتماد الجرد من إدارة المخزون":{'en':"Stocktake approved by inventory management",'fr':"Inventaire approuvé par la gestion du stock"},
      "رفض الجرد من إدارة المخزون":{'en':"Stocktake rejected by inventory management",'fr':"Inventaire rejeté par la gestion du stock"},
      "تم اعتماد الجرد وتعديل الأرصدة.":{'en':"Stocktake approved and balances adjusted.",'fr':"Inventaire approuvé et soldes ajustés."},
      "تم رفض الجرد.":{'en':"Stocktake rejected.",'fr':"Inventaire rejeté."},
      " • غير المعتمد: ":{'en':" • Pending approval: ",'fr':" • En attente : "},
      " • محجوز: ":{'en':" • Quarantined: ",'fr':" • En quarantaine : "},
      "\\nحد الطلب: ":{'en':"\\nReorder level: ",'fr':"\\nSeuil de réapprovisionnement : "},
      " • كمية إعادة الطلب: ":{'en':" • Reorder qty: ",'fr':" • Qté de réapprovisionnement : "},
      " • المعيد: ":{'en':" • Returned by: ",'fr':" • Retourné par : "},
      "رفض طلب الصرف":{'en':"Reject Issue Request",'fr':"Rejeter la demande de sortie"},
      "طباعة سند المرتجع":{'en':"Print Return Voucher",'fr':"Imprimer le bon de retour"},
      "مشاركة سند المرتجع":{'en':"Share Return Voucher",'fr':"Partager le bon de retour"},
      "طباعة سند الحجز":{'en':"Print Quarantine Voucher",'fr':"Imprimer le bon de quarantaine"},
      "مشاركة سند الحجز":{'en':"Share Quarantine Voucher",'fr':"Partager le bon de quarantaine"},
      "طباعة محضر الهدر":{'en':"Print Waste Report",'fr':"Imprimer le rapport de perte"},
      "مشاركة محضر الهدر":{'en':"Share Waste Report",'fr':"Partager le rapport de perte"},
      "عدد الأصناف":{'en':"Items",'fr':"Articles"},
      "مخزون منخفض":{'en':"Low stock",'fr':"Stock faible"},
      "نافد":{'en':"Out of stock",'fr':"Rupture de stock"},
      "استلامات معلقة":{'en':"Pending receipts",'fr':"Réceptions en attente"},
      "طلبات صرف معلقة":{'en':"Pending issues",'fr':"Sorties en attente"},
      "جردات معلقة":{'en':"Pending stocktakes",'fr':"Inventaires en attente"},
      "تنبيهات الصلاحية":{'en':"Expiry alerts",'fr':"Alertes de péremption"},
      "البحث عن صنف":{'en':"Search items",'fr':"Rechercher des articles"},
      "تصفية حالة المخزون":{'en':"Filter stock status",'fr':"Filtrer l’état du stock"},
      "كل الأصناف":{'en':"All items",'fr':"Tous les articles"},
      "كمية غير معتمدة":{'en':"Unapproved quantity",'fr':"Quantité non approuvée"},
      "كمية محجوزة":{'en':"Quarantined quantity",'fr':"Quantité en quarantaine"},
      "تصفية باسم الموظف":{'en':"Filter by employee",'fr':"Filtrer par employé"},
      "نوع حركة المخزون":{'en':"Movement type",'fr':"Type de mouvement"},
      "كل الحركات":{'en':"All movements",'fr':"Tous les mouvements"},
      "من تاريخ":{'en':"From",'fr':"Du"},
      "إلى تاريخ":{'en':"To",'fr':"Au"},
      "الكل":{'en':"All",'fr':"Tout"},
      "مسح التصفية":{'en':"Clear filters",'fr':"Effacer les filtres"},
      "غير محدد":{'en':"Unspecified",'fr':"Non spécifié"},
      "قبل الحركة":{'en':"Before",'fr':"Avant"},
      "بعد الحركة":{'en':"After",'fr':"Après"},
      "استلام التوريد":{'en':"Goods Receiving",'fr':"Réception des marchandises"},
      "استلامات بانتظار الاعتماد":{'en':"Receipts awaiting approval",'fr':"Réceptions en attente d’approbation"},
      "سجّل الكميات المستلمة فعلياً، ثم يتولى المدير مراجعة التكلفة والاعتماد المالي.":{'en':"Record physically received quantities; Admin reviews costs and financial approval.",'fr':"Enregistrez les quantités physiquement reçues ; l’administrateur vérifie les coûts et l’approbation financière."},
      "فتح شاشة استلام المورد":{'en':"Open supplier receiving",'fr':"Ouvrir la réception fournisseur"},


      "تصنيف الصنف":{'en':"Item category",'fr':"Catégorie d’article"},
      "كل التصنيفات":{'en':"All categories",'fr':"Toutes les catégories"},
      "مسح تصفية الأصناف":{'en':"Clear item filters",'fr':"Effacer les filtres d’articles"},
      "وحدة الصرف":{'en':"Issue unit",'fr':"Unité de sortie"},
      "وحدة الكمية":{'en':"Quantity unit",'fr':"Unité de quantité"},
      "وحدة المرتجع":{'en':"Return unit",'fr':"Unité de retour"},
      "إضافة وحدة للصنف":{'en':"Add product unit",'fr':"Ajouter une unité"},
      "تعديل وحدة الصنف":{'en':"Edit product unit",'fr':"Modifier l’unité"},
      "اسم الوحدة بالعربية":{'en':"Unit name (Arabic)",'fr':"Nom de l’unité (arabe)"},
      "اسم الوحدة بالإنجليزية":{'en':"Unit name (English)",'fr':"Nom de l’unité (anglais)"},
      "اسم الوحدة بالفرنسية":{'en':"Unit name (French)",'fr':"Nom de l’unité (français)"},
      "كم وحدة أساس داخل العبوة؟":{'en':"How many base units per package?",'fr':"Combien d’unités de base par emballage ?"},
      "تستخدم في الشراء":{'en':"Available for purchasing",'fr':"Disponible pour l’achat"},
      "تستخدم في الصرف":{'en':"Available for issuing",'fr':"Disponible pour la sortie"},
      "تحقق من الاسم ومعامل التحويل واستخدام الوحدة":{'en':"Check the unit name, conversion factor and usage",'fr':"Vérifiez le nom, le facteur de conversion et l’utilisation"},
      "تم حفظ وحدة القياس":{'en':"Unit saved",'fr':"Unité enregistrée"},
      "وحدات الصنف":{'en':"Product units",'fr':"Unités du produit"},
      "لا توجد وحدات إضافية":{'en':"No additional units",'fr':"Aucune unité supplémentaire"},
      "وحدة الأساس":{'en':"Base unit",'fr':"Unité de base"},
      "تعديل":{'en':"Edit",'fr':"Modifier"},
      "تعطيل":{'en':"Deactivate",'fr':"Désactiver"},
      "إضافة وحدة":{'en':"Add unit",'fr':"Ajouter une unité"},
      "غير مصنف":{'en':"Uncategorized",'fr':"Sans catégorie"},

    };
    return translations[ar]?[language]??ar;
  }

  @override void initState(){super.initState();load();}
  void message(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> load() async {
    if(mounted)setState(()=>loading=true);
    try {
      final db=await AppDatabase.instance.database;
      final a=await InventoryService.stockOverview(db,actorUserId:actorId,language:language);
      final b=await InventoryService.issueRequests(db,actorUserId:actorId);
      final c=await AppDatabase.instance.purchaseableProducts(actorUserId:actorId,language:language);
      final d=await InventoryService.quarantineRecords(db,actorUserId:actorId,language:language);
      final e=await InventoryService.wasteRecords(db,actorUserId:actorId,language:language);
      final f=await InventoryService.expiryAlerts(db,actorUserId:actorId,language:language);
      final g=await InventoryService.supplierReturns(db,actorUserId:actorId,language:language);
      final h=await db.rawQuery('SELECT r.*,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code=?),p.name_ar) AS name_ar,p.base_unit FROM stock_return_records r JOIN products p ON p.id=r.product_id ORDER BY r.id DESC LIMIT 200',[language,'ar']);
      final st=await db.query('stocktakes',orderBy:'id DESC',limit:30);
      final pendingReceipts=await db.rawQuery("SELECT COUNT(*) AS total FROM purchase_receipts WHERE status='submitted'");
      final pendingStocktakes=await db.rawQuery("SELECT COUNT(*) AS total FROM stocktakes WHERE status='submitted'");
      final mv=await db.rawQuery('SELECT m.id,m.product_id,p.category_id,m.movement_type,m.quantity_delta,m.source_type,m.source_id,m.note,m.occurred_at,u.display_name,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),p.name_ar) AS name_ar FROM stock_movements m JOIN products p ON p.id=m.product_id LEFT JOIN users u ON u.id=m.actor_user_id ORDER BY m.id DESC LIMIT 500',[language]);
      final running=<int,double>{for(final p in a)p['id'] as int:(p['on_hand'] as num).toDouble()};
      for(final movement in mv){final pid=movement['product_id'] as int;final after=running[pid]??0.0;final delta=(movement['quantity_delta'] as num).toDouble();movement['balance_after']=after;movement['balance_before']=after-delta;running[pid]=after-delta;}
      if(mounted)setState((){balances=a;requests=b;products=c;quarantine=d;waste=e;expiry=f;supplierReturnRows=g;issueReturnRows=h;stocktakeRows=st;movementRows=mv;pendingReceiptsCount=(pendingReceipts.first['total'] as num).toInt();pendingStocktakesCount=(pendingStocktakes.first['total'] as num).toInt();});
    } catch(e){message(tr('تعذر تحميل إدارة المخزون: ')+e.toString());}
    finally{if(mounted)setState(()=>loading=false);}
  }

  Future<void> registerInventoryLot() async {
    final db=await AppDatabase.instance.database;
    final lines=await db.rawQuery("SELECT l.id,l.received_qty,l.product_id,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code='ar'),p.name_ar) AS name_ar,p.base_unit,r.invoice_no FROM purchase_receipt_lines l JOIN purchase_receipts r ON r.id=l.receipt_id JOIN products p ON p.id=l.product_id WHERE r.status='approved' ORDER BY l.id DESC LIMIT 100",[language]);
    if(lines.isEmpty){message(tr('لا توجد أسطر توريد معتمدة لربط التشغيلات بها'));return;}
    int? selected=lines.first['id'] as int;
    final code=TextEditingController(),qty=TextEditingController(),made=TextEditingController(),expiryDate=TextEditingController();
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setDialog)=>AlertDialog(
        title:Text(tr('تسجيل تشغيلة وتاريخ صلاحية')),
        content:SizedBox(width:440,child:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<int>(value:selected,decoration:InputDecoration(labelText:tr('سطر التوريد المعتمد')),items:lines.map((l)=>DropdownMenuItem(value:l['id'] as int,child:Text(l['name_ar'].toString()+' • '+l['invoice_no'].toString()+tr(' • كمية ')+l['received_qty'].toString()))).toList(),onChanged:(v)=>setDialog(()=>selected=v)),
          TextField(controller:code,decoration:InputDecoration(labelText:tr('رقم التشغيلة / الدفعة'))),
          TextField(controller:qty,keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('كمية هذه الدفعة'))),
          TextField(controller:made,decoration:InputDecoration(labelText:tr('تاريخ الإنتاج YYYY-MM-DD (اختياري)'))),
          TextField(controller:expiryDate,decoration:InputDecoration(labelText:tr('تاريخ الانتهاء YYYY-MM-DD'))),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('حفظ التشغيلة')))],
      )));
      if(ok!=true)return;
      final q=double.tryParse(qty.text.trim().replaceAll(',','.'));
      if(q==null)throw ArgumentError(tr('أدخل كمية صحيحة'));
      final id=await InventoryService.registerLot(db,actorUserId:actorId,receiptLineId:selected!,lotCode:code.text,quantity:q,manufactureDate:made.text,expiryDate:expiryDate.text);
      await load();message(tr('تم تسجيل الدفعة رقم ')+id.toString()+tr(' وربطها بالتوريد.'));
    }catch(e){message(e.toString());}
    finally{code.dispose();qty.dispose();made.dispose();expiryDate.dispose();}
  }

  Future<void> submitSupplierReturn() async {
    final db=await AppDatabase.instance.database;
    final lines=await db.rawQuery("SELECT l.id,l.product_id,l.received_qty,COALESCE((SELECT t.name FROM product_translations t WHERE t.product_id=p.id AND t.language_code=?),(SELECT ta.name FROM product_translations ta WHERE ta.product_id=p.id AND ta.language_code='ar'),p.name_ar) AS name_ar,p.base_unit,r.invoice_no,s.name AS supplier_name FROM purchase_receipt_lines l JOIN purchase_receipts r ON r.id=l.receipt_id JOIN products p ON p.id=l.product_id JOIN suppliers s ON s.id=r.supplier_id WHERE r.status='approved' ORDER BY l.id DESC LIMIT 100",[language]);
    if(lines.isEmpty){message(tr('لا توجد فواتير توريد معتمدة للإرجاع'));return;}
    int? selected=lines.first['id'] as int;
    final unitsByProduct=<int,List<Map<String,Object?>>>{for(final l in lines)l['product_id'] as int:await InventoryService.productUnits(db,actorUserId:actorId,productId:l['product_id'] as int,language:language,forPurchase:true)};
    final selectedUnits=<int,int>{for(final l in lines)l['product_id'] as int:0};
    final qty=TextEditingController(),reason=TextEditingController();
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setDialog)=>AlertDialog(
        title:Text(tr('طلب إرجاع إلى المورد')),
        content:SizedBox(width:430,child:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<int>(value:selected,decoration:InputDecoration(labelText:tr('الصنف / فاتورة التوريد / المورد')),items:lines.map((l)=>DropdownMenuItem(value:l['id'] as int,child:Text(l['name_ar'].toString()+' • '+l['supplier_name'].toString()+' • '+l['invoice_no'].toString()))).toList(),onChanged:(v){setDialog((){selected=v;if(v!=null){final line=lines.firstWhere((x)=>x['id']==v);selectedUnits[line['product_id'] as int]=0;}});}),
          DropdownButtonFormField<int>(value:selected==null?0:selectedUnits[lines.firstWhere((x)=>x['id']==selected)['product_id'] as int]??0,decoration:InputDecoration(labelText:tr('وحدة المرتجع')),items:[for(final u in unitsByProduct[lines.firstWhere((x)=>x['id']==selected)['product_id'] as int]??[])DropdownMenuItem(value:u['id'] as int,child:Text(u['unit_name'].toString()))],onChanged:(v){setDialog((){if(selected!=null){final line=lines.firstWhere((x)=>x['id']==selected);selectedUnits[line['product_id'] as int]=v??0;}});}),
          TextField(controller:qty,keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('الكمية المراد إرجاعها'))),
          TextField(controller:reason,decoration:InputDecoration(labelText:tr('سبب الإرجاع'))),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('إرسال للمراجعة')))],
      )));
      if(ok!=true)return;
      final q=double.tryParse(qty.text.trim().replaceAll(',','.'));
      if(q==null)throw ArgumentError(tr('أدخل كمية صحيحة'));
      final selectedLine=lines.firstWhere((l)=>l['id']==selected);
      final baseQty=await InventoryService.toBaseQuantity(db,actorUserId:actorId,productId:selectedLine['product_id'] as int,quantity:q,unitId:selectedUnits[selectedLine['product_id'] as int]??0,forPurchase:true);
      final id=await InventoryService.submitSupplierReturn(db,actorUserId:actorId,receiptLineId:selected!,quantity:baseQty,reason:reason.text);
      await load();message(tr('تم إرسال طلب إرجاع المورد رقم ')+id.toString()+tr(' لاعتماد المدير.'));
    }catch(e){message(e.toString());}finally{qty.dispose();reason.dispose();}
  }

  Future<void> reviewSupplierReturn(Map<String,Object?> row,bool approve) async {
    final note=TextEditingController();
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
        title:Text(approve?tr('اعتماد إرجاع المورد'):tr('رفض إرجاع المورد')),
        content:TextField(controller:note,decoration:InputDecoration(labelText:tr('ملاحظة / سبب القرار'))),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('تأكيد')))],
      ));
      if(ok!=true)return;
      await InventoryService.reviewSupplierReturn(await AppDatabase.instance.database,actorUserId:actorId,returnId:row['id'] as int,approve:approve,note:note.text);
      await load();message(approve?tr('تم اعتماد الإرجاع وتحديث المخزون وحساب المورد.'):tr('تم رفض طلب الإرجاع.'));
    }catch(e){message(e.toString());}finally{note.dispose();}
  }

  Future<void> editProductUnit(Map<String,Object?> product,{Map<String,Object?>? unit}) async {
    if(!admin)return;
    final ar=TextEditingController(text:(unit?['unit_name_ar']??'').toString());
    final en=TextEditingController(text:(unit?['unit_name_en']??'').toString());
    final fr=TextEditingController(text:(unit?['unit_name_fr']??'').toString());
    final factor=TextEditingController(text:unit==null?'':(unit['conversion_to_base']??'').toString());
    var purchase=unit==null?true:unit['is_purchase_unit']==1;
    var issue=unit==null?true:unit['is_issue_unit']==1;
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,refresh)=>AlertDialog(
        title:Text(unit==null?tr('إضافة وحدة للصنف'):tr('تعديل وحدة الصنف')),
        content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:ar,decoration:InputDecoration(labelText:tr('اسم الوحدة بالعربية'))),
          TextField(controller:en,decoration:InputDecoration(labelText:tr('اسم الوحدة بالإنجليزية'))),
          TextField(controller:fr,decoration:InputDecoration(labelText:tr('اسم الوحدة بالفرنسية'))),
          TextField(controller:factor,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('كم وحدة أساس داخل العبوة؟'))),
          CheckboxListTile(value:purchase,onChanged:(v)=>refresh(()=>purchase=v??false),title:Text(tr('تستخدم في الشراء'))),
          CheckboxListTile(value:issue,onChanged:(v)=>refresh(()=>issue=v??false),title:Text(tr('تستخدم في الصرف'))),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('حفظ')))],
      )));
      if(ok!=true)return;
      final n=double.tryParse(factor.text.trim().replaceAll(',','.'));
      if(n==null || !n.isFinite || n<=0 || ar.text.trim().isEmpty || (!purchase&&!issue)){message(tr('تحقق من الاسم ومعامل التحويل واستخدام الوحدة'));return;}
      await InventoryService.saveProductUnit(await AppDatabase.instance.database,actorUserId:actorId,productId:product['id'] as int,unitId:unit==null?null:unit['id'] as int,nameAr:ar.text,nameEn:en.text,nameFr:fr.text,conversionToBase:n,purchaseEnabled:purchase,issueEnabled:issue);
      await load();message(tr('تم حفظ وحدة القياس'));
    }catch(e){message(e.toString());}
    finally{ar.dispose();en.dispose();fr.dispose();factor.dispose();}
  }

  Future<void> manageProductUnits(Map<String,Object?> product) async {
    if(!admin)return;
    final db=await AppDatabase.instance.database;
    var units=await InventoryService.productUnits(db,actorUserId:actorId,productId:product['id'] as int);
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(c)=>StatefulBuilder(builder:(c,refresh)=>AlertDialog(
      title:Text(tr('وحدات الصنف')+' • '+product['name_ar'].toString()),
      content:SizedBox(width:440,child:units.isEmpty?Text(tr('لا توجد وحدات إضافية')):ListView(shrinkWrap:true,children:[
        for(final u in units)ListTile(title:Text(u['unit_name_ar'].toString()),subtitle:Text((u['is_base_unit']==1?tr('وحدة الأساس'):('1 '+u['unit_name_ar'].toString()+' = '+u['conversion_to_base'].toString()+' '+product['base_unit'].toString()))),trailing:u['id']==0?const Icon(Icons.lock_outline):PopupMenuButton<String>(onSelected:(v)async{
          if(v=='edit'){Navigator.pop(c);await editProductUnit(product,unit:u);}
          if(v=='disable'){await InventoryService.deactivateProductUnit(db,actorUserId:actorId,unitId:u['id'] as int);units=await InventoryService.productUnits(db,actorUserId:actorId,productId:product['id'] as int);refresh((){});}
        },itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(tr('تعديل'))),PopupMenuItem(value:'disable',child:Text(tr('تعطيل')))])),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(tr('إغلاق'))),FilledButton.icon(onPressed:()async{Navigator.pop(c);await editProductUnit(product);},icon:const Icon(Icons.add),label:Text(tr('إضافة وحدة')))],
    )));
  }

  Future<void> openReceivingScreen() async {
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>PurchaseScreen(user:widget.user)));
    if(mounted) await load();
  }

  Future<void> chooseMovementDate(bool from) async {
    final picked=await showDatePicker(context:context,initialDate:(from?movementFrom:movementTo)??DateTime.now(),firstDate:DateTime(2020),lastDate:DateTime(2100));
    if(picked!=null && mounted) setState((){if(from){movementFrom=picked;}else{movementTo=picked;}});
  }

  Future<void> openMovementReport(bool share) async {
    try {
      if(share){await DocumentService.shareInventoryMovementReport(language:language);}
      else{await DocumentService.printInventoryMovementReport(language:language);}
    } catch(e){message(tr('تعذر تجهيز المستند: ')+e.toString());}
  }
  Future<void> openInventoryDocument(String type,int id,bool share) async {
    try{
      if(share){await DocumentService.shareInventoryDocument(type,id,language:Localizations.localeOf(context).languageCode);}
      else{await DocumentService.printInventoryDocument(type,id,language:Localizations.localeOf(context).languageCode);}
    }catch(e){message(tr('تعذر تجهيز المستند: ')+e.toString());}
  }
  Future<void> newIssue({bool openingKitchenHandover=false}) async {
    final destination=TextEditingController(text:openingKitchenHandover?'المطبخ':'');
    final reason=TextEditingController(text:openingKitchenHandover?'تسليم افتتاحي لعهدة المطبخ':'');
    final receiver=TextEditingController();
    String destinationType=openingKitchenHandover?'kitchen':'department';
    final fields=<int,TextEditingController>{for(final p in products)p['id'] as int:TextEditingController()};
    final selectedUnits=<int,int>{};
    final unitOptions=<int,List<Map<String,Object?>>>{};
    final db=await AppDatabase.instance.database;
    for(final p in products){final pid=p['id'] as int;unitOptions[pid]=await InventoryService.productUnits(db,actorUserId:actorId,productId:pid,language:language,forIssue:true);selectedUnits[pid]=0;}
    try {
      final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setDialog)=>AlertDialog(
        title:Text(tr('طلب صرف مواد')),
        content:SizedBox(width:460,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:destination,decoration:InputDecoration(labelText:tr('اسم الجهة / المطبخ'))),
          DropdownButtonFormField<String>(value:destinationType,decoration:InputDecoration(labelText:tr('نوع الحركة')),items:[DropdownMenuItem(value:'department',child:Text(tr('صرف استهلاكي - يخصم من المخزون'))),DropdownMenuItem(value:'kitchen',child:Text(tr('تحويل إلى عهدة المطبخ - ينقص المخزن الرئيسي ويزيد رصيد المطبخ')))],onChanged:(v)=>setDialog(()=>destinationType=v??'department')),
          TextField(controller:receiver,decoration:InputDecoration(labelText:tr('اسم المستلم'))),
          TextField(controller:reason,decoration:InputDecoration(labelText:tr('سبب الصرف'))),
          const Divider(),
          for(final p in products)Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Expanded(flex:3,child:Text(p['name_ar'].toString()+' ('+p['base_unit'].toString()+')')),Expanded(flex:3,child:DropdownButtonFormField<int>(value:selectedUnits[p['id'] as int],decoration:InputDecoration(labelText:tr('وحدة الصرف')),items:[for(final u in unitOptions[p['id'] as int]??[])DropdownMenuItem(value:u['id'] as int,child:Text(u['unit_name'].toString()+' × '+u['conversion_to_base'].toString()))],onChanged:(v)=>setDialog(()=>selectedUnits[p['id'] as int]=v??0))),const SizedBox(width:6),Expanded(flex:2,child:TextField(controller:fields[p['id'] as int],keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('الكمية'))))])),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('إرسال الطلب')))],
      )));
      if(ok!=true)return;
      final quantities=<int,double>{},enteredQuantities=<int,double>{},conversionFactors=<int,double>{};
      final enteredUnits=<int,String>{};
      for(final e in fields.entries){final raw=e.value.text.trim();if(raw.isEmpty)continue;final n=double.tryParse(raw.replaceAll(',','.'));if(n==null||!n.isFinite||n<=0)throw ArgumentError(tr('أدخل كميات صحيحة أكبر من صفر'));final unit=(unitOptions[e.key]??[]).firstWhere((u)=>(u['id'] as int)==(selectedUnits[e.key]??0));final factor=(unit['conversion_to_base'] as num).toDouble();enteredQuantities[e.key]=n;enteredUnits[e.key]=unit['unit_name'].toString();conversionFactors[e.key]=factor;quantities[e.key]=await InventoryService.toBaseQuantity(db,actorUserId:actorId,productId:e.key,quantity:n,unitId:selectedUnits[e.key]??0,forIssue:true);}
      final id=await InventoryService.submitIssueRequest(db,actorUserId:actorId,destination:destination.text,destinationType:destinationType,reason:reason.text,receiverName:receiver.text,quantities:quantities,enteredQuantities:enteredQuantities,enteredUnits:enteredUnits,conversionFactors:conversionFactors);
      await load();message(tr('تم إرسال طلب الصرف رقم ')+id.toString()+tr(' للمراجعة. لم يتغير الرصيد بعد.'));
    }catch(e){message(e.toString());}
    finally{destination.dispose();reason.dispose();receiver.dispose();for(final f in fields.values){f.dispose();}}
  }

  Future<void> reviewIssue(Map<String,Object?> request) async {
    final db=await AppDatabase.instance.database;
    final lines=await InventoryService.issueLines(db,actorUserId:actorId,requestId:request['id'] as int,language:language);
    final fields=<int,TextEditingController>{for(final l in lines)l['id'] as int:TextEditingController(text:(((l['requested_qty'] as num).toDouble()-(l['issued_qty'] as num).toDouble()).clamp(0,double.infinity)).toString())};
    final note=TextEditingController();
    try {
      final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
        title:Text(tr('مراجعة ')+request['document_no'].toString()),
        content:SizedBox(width:430,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(tr('الجهة: ')+request['destination'].toString()+tr(' • المستلم: ')+request['received_by_name'].toString()),
          Text(tr('السبب: ')+request['reason'].toString()),Divider(),
          for(final l in lines)Row(children:[Expanded(child:Text(l['name_ar'].toString()+tr('\nالمطلوب: ')+l['requested_qty'].toString()+' '+l['unit_snapshot'].toString()+' ('+(l['entered_qty']??l['requested_qty']).toString()+' '+(l['entered_unit_name']??l['unit_snapshot']).toString()+')'+tr(' • صُرف: ')+l['issued_qty'].toString()+tr(' • المتاح: ')+l['available_qty'].toString())),SizedBox(width:90,child:TextField(controller:fields[l['id'] as int],keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('صرف الآن'))))]),
          TextField(controller:note,decoration:InputDecoration(labelText:tr('ملاحظة الاعتماد'))),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('رجوع'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('اعتماد الصرف')))],
      ));
      if(ok!=true)return;
      final values=<int,double>{};
      for(final e in fields.entries){final n=double.tryParse(e.value.text.trim().replaceAll(',','.'));if(n==null||!n.isFinite||n<0)throw ArgumentError(tr('كميات الصرف غير صحيحة'));values[e.key]=n;}
      await InventoryService.approveAndIssue(db,actorUserId:actorId,requestId:request['id'] as int,issueQuantities:values,note:note.text);
      await load();message(tr('تم تسجيل كمية الصرف الجديدة وتحديث الرصيد.'));
    }catch(e){message(e.toString());}
    finally{note.dispose();for(final f in fields.values){f.dispose();}}
  }

  Future<void> rejectIssue(Map<String,Object?> request) async {
    final reason=TextEditingController();
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(tr('رفض طلب الصرف')),content:TextField(controller:reason,decoration:InputDecoration(labelText:tr('سبب الرفض'))),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('تأكيد الرفض')))]));
      if(ok!=true)return;
      await InventoryService.rejectIssue(await AppDatabase.instance.database,actorUserId:actorId,requestId:request['id'] as int,reason:reason.text);
      await load();message(tr('تم رفض الطلب وتسجيل السبب.'));
    }catch(e){message(e.toString());}finally{reason.dispose();}
  }

  Future<void> recordReturn(Map<String,Object?> request) async {
    final db=await AppDatabase.instance.database;
    final lines=await InventoryService.issueLines(db,actorUserId:actorId,requestId:request['id'] as int,language:language);
    if(lines.isEmpty){message(tr('لا توجد أصناف في إذن الصرف'));return;}
    int? selected=lines.first['id'] as int;
    String condition='good';
    final unitsByProduct=<int,List<Map<String,Object?>>>{for(final l in lines)l['product_id'] as int:await InventoryService.productUnits(db,actorUserId:actorId,productId:l['product_id'] as int,language:language,forIssue:true)};
    final selectedUnits=<int,int>{for(final l in lines)l['product_id'] as int:0};
    final qty=TextEditingController(),reason=TextEditingController(),returnedBy=TextEditingController(text:request['destination'].toString());
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setDialog)=>AlertDialog(
        title:Text(tr('تسجيل مرتجع • ')+request['document_no'].toString()),
        content:SizedBox(width:430,child:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<int>(value:selected,decoration:InputDecoration(labelText:tr('بند الصرف')),items:lines.map((l)=>DropdownMenuItem(value:l['id'] as int,child:Text(l['name_ar'].toString()+tr(' | متبقي: ')+((l['issued_qty'] as num).toDouble()-(l['returned_qty'] as num).toDouble()).toString()))).toList(),onChanged:(v){setDialog((){selected=v;if(v!=null){final line=lines.firstWhere((x)=>x['id']==v);selectedUnits[line['product_id'] as int]=0;}});}),
          DropdownButtonFormField<int>(value:selected==null?0:selectedUnits[lines.firstWhere((x)=>x['id']==selected)['product_id'] as int]??0,decoration:InputDecoration(labelText:tr('وحدة المرتجع')),items:[for(final u in unitsByProduct[lines.firstWhere((x)=>x['id']==selected)['product_id'] as int]??[])DropdownMenuItem(value:u['id'] as int,child:Text(u['unit_name'].toString()))],onChanged:(v){setDialog((){if(selected!=null){final line=lines.firstWhere((x)=>x['id']==selected);selectedUnits[line['product_id'] as int]=v??0;}});}),
          TextField(controller:qty,keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('الكمية المرتجعة'))),
          DropdownButtonFormField<String>(value:condition,decoration:InputDecoration(labelText:tr('حالة المرتجع')),items:[DropdownMenuItem(value:'good',child:Text(tr('سليم - يعود للمخزون'))),DropdownMenuItem(value:'damaged',child:Text(tr('تالف - حجز'))),DropdownMenuItem(value:'quarantine',child:Text(tr('يحتاج فحص - حجز')))],onChanged:(v)=>setDialog(()=>condition=v??'good')),
          TextField(controller:returnedBy,decoration:InputDecoration(labelText:tr('الجهة المعيدة'))),
          TextField(controller:reason,decoration:InputDecoration(labelText:tr('السبب / الملاحظات'))),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('حفظ المرتجع')))],
      )));
      if(ok!=true)return;
      final q=double.tryParse(qty.text.trim().replaceAll(',','.'));
      if(q==null)throw ArgumentError(tr('أدخل كمية صحيحة'));
      final selectedLine=lines.firstWhere((l)=>l['id']==selected);
      final baseQty=await InventoryService.toBaseQuantity(db,actorUserId:actorId,productId:selectedLine['product_id'] as int,quantity:q,unitId:selectedUnits[selectedLine['product_id'] as int]??0,forIssue:true);
      await InventoryService.recordIssueReturn(db,actorUserId:actorId,issueLineId:selected!,quantity:baseQty,condition:condition,reason:reason.text,returnedBy:returnedBy.text);
      await load();message(tr('تم تسجيل المرتجع؛ السليم عاد للرصيد والتالف عُزل.'));
    }catch(e){message(e.toString());}
    finally{qty.dispose();reason.dispose();returnedBy.dispose();}
  }

  Future<void> recordWaste() async {
    int? productId=products.isEmpty?null:products.first['id'] as int;
    final qty=TextEditingController(),reason=TextEditingController();
    final db=await AppDatabase.instance.database;
    final units=<int,List<Map<String,Object?>>>{for(final p in products)p['id'] as int:await InventoryService.productUnits(db,actorUserId:actorId,productId:p['id'] as int,language:language,forIssue:true)};
    int selectedUnitId=0;
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setDialog)=>AlertDialog(
        title:Text(tr('تسجيل هدر / تلف')),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<int>(value:productId,decoration:InputDecoration(labelText:tr('الصنف')),items:products.map((p)=>DropdownMenuItem(value:p['id'] as int,child:Text(p['name_ar'].toString()))).toList(),onChanged:(v){setDialog((){productId=v;selectedUnitId=0;});}),
          DropdownButtonFormField<int>(value:selectedUnitId,decoration:InputDecoration(labelText:tr('وحدة الكمية')),items:[for(final u in units[productId]??[])DropdownMenuItem(value:u['id'] as int,child:Text(u['unit_name'].toString()))],onChanged:(v)=>setDialog(()=>selectedUnitId=v??0)),
          TextField(controller:qty,keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('الكمية'))),
          TextField(controller:reason,decoration:InputDecoration(labelText:tr('سبب الهدر'))),
        ]),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('تسجيل الهدر')))],
      )));
      if(ok!=true)return;
      final q=double.tryParse(qty.text.trim().replaceAll(',','.'));
      if(productId==null||q==null)throw ArgumentError(tr('حدد الصنف والكمية'));
      final baseQty=await InventoryService.toBaseQuantity(db,actorUserId:actorId,productId:productId!,quantity:q,unitId:selectedUnitId,forIssue:true);
      await InventoryService.recordWaste(db,actorUserId:actorId,productId:productId!,quantity:baseQty,reason:reason.text);
      await load();message(tr('تم تسجيل الهدر وخصمه من الرصيد.'));
    }catch(e){message(e.toString());}finally{qty.dispose();reason.dispose();}
  }

  Future<void> quarantineStock() async {
    int? productId=products.isEmpty?null:products.first['id'] as int;
    final qty=TextEditingController(),reason=TextEditingController();
    final db=await AppDatabase.instance.database;
    final units=<int,List<Map<String,Object?>>>{for(final p in products)p['id'] as int:await InventoryService.productUnits(db,actorUserId:actorId,productId:p['id'] as int,language:language,forIssue:true)};
    int selectedUnitId=0;
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setDialog)=>AlertDialog(
        title:Text(tr('عزل كمية من المخزون')),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<int>(value:productId,decoration:InputDecoration(labelText:tr('الصنف')),items:products.map((p)=>DropdownMenuItem(value:p['id'] as int,child:Text(p['name_ar'].toString()))).toList(),onChanged:(v){setDialog((){productId=v;selectedUnitId=0;});}),
          DropdownButtonFormField<int>(value:selectedUnitId,decoration:InputDecoration(labelText:tr('وحدة الكمية')),items:[for(final u in units[productId]??[])DropdownMenuItem(value:u['id'] as int,child:Text(u['unit_name'].toString()))],onChanged:(v)=>setDialog(()=>selectedUnitId=v??0)),
          TextField(controller:qty,keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('الكمية'))),
          TextField(controller:reason,decoration:InputDecoration(labelText:tr('سبب العزل (انتهاء / اشتباه / تلف)'))),
        ]),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('عزل الكمية')))],
      )));
      if(ok!=true)return;
      final q=double.tryParse(qty.text.trim().replaceAll(',','.'));
      if(productId==null||q==null)throw ArgumentError(tr('حدد الصنف والكمية'));
      final baseQty=await InventoryService.toBaseQuantity(db,actorUserId:actorId,productId:productId!,quantity:q,unitId:selectedUnitId,forIssue:true);
      await InventoryService.quarantineStock(db,actorUserId:actorId,productId:productId!,quantity:baseQty,reason:reason.text);
      await load();message(tr('تم عزل الكمية وإخراجها من الرصيد القابل للبيع.'));
    }catch(e){message(e.toString());}finally{qty.dispose();reason.dispose();}
  }

  Future<void> resolveQuarantine(Map<String,Object?> q) async {
    final note=TextEditingController();
    String decision='release';
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setDialog)=>AlertDialog(
        title:Text(tr('معالجة حجز ')+q['name_ar'].toString()),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(tr('الكمية: ')+q['quantity'].toString()+' '+q['unit_snapshot'].toString()+tr('\nالسبب: ')+q['reason'].toString()),
          DropdownButtonFormField<String>(value:decision,decoration:InputDecoration(labelText:tr('القرار')),items:[DropdownMenuItem(value:'release',child:Text(tr('إعادة للمخزون المتاح'))),DropdownMenuItem(value:'writeoff',child:Text(tr('إتلاف نهائي')))],onChanged:(v)=>setDialog(()=>decision=v??'release')),
          TextField(controller:note,decoration:InputDecoration(labelText:tr('ملاحظة المدير'))),
        ]),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('تنفيذ القرار')))],
      )));
      if(ok!=true)return;
      await InventoryService.resolveQuarantine(await AppDatabase.instance.database,actorUserId:actorId,quarantineId:q['id'] as int,resolution:decision,note:note.text);
      await load();message(tr('تمت معالجة سجل الحجز.'));
    }catch(e){message(e.toString());}finally{note.dispose();}
  }

  Future<void> editReorder(Map<String,Object?> p) async {
    final min=TextEditingController(text:p['minimum_qty'].toString()),reorder=TextEditingController(text:p['reorder_qty'].toString());
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(tr('حد إعادة الطلب • ')+p['name_ar'].toString()),content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:min,keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('الحد الأدنى'))),
        TextField(controller:reorder,keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('كمية إعادة الطلب'))),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('حفظ')))]));
      if(ok!=true)return;
      final a=double.tryParse(min.text.trim().replaceAll(',','.')),b=double.tryParse(reorder.text.trim().replaceAll(',','.'));
      if(a==null||b==null)throw ArgumentError(tr('أدخل أرقاماً صحيحة'));
      await InventoryService.setReorderRule(await AppDatabase.instance.database,actorUserId:actorId,productId:p['id'] as int,minimumQty:a,reorderQty:b);
      await load();message(tr('تم تحديث حد إعادة الطلب.'));
    }catch(e){message(e.toString());}finally{min.dispose();reorder.dispose();}
  }


  Future<void> submitStocktake() async {
    final fields=<int,TextEditingController>{for(final p in products)p['id'] as int:TextEditingController()};
    final note=TextEditingController();
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
        title:Text(tr('جرد فعلي للمخزون')),
        content:SizedBox(width:440,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(tr('سجّل الرصيد المعتمد القابل للصرف فقط. استبعد التوريدات غير المعتمدة والكميات المحجوزة.')),
          for(final p in products)Row(children:[
            Expanded(child:Text(p['name_ar'].toString()+' ('+p['base_unit'].toString()+')')),
            SizedBox(width:100,child:TextField(controller:fields[p['id'] as int],keyboardType:TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('الفعلي')))),
            Text(tr('دفتر: ')+p['on_hand'].toString()),
          ]),
          TextField(controller:note,decoration:InputDecoration(labelText:tr('ملاحظات الجرد'))),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('إرسال للمدير')))],
      ));
      if(ok!=true)return;
      final counted=<int,double>{};
      for(final e in fields.entries){
        final raw=e.value.text.trim();if(raw.isEmpty)continue;
        final q=double.tryParse(raw.replaceAll(',','.'));
        if(q==null||!q.isFinite||q<0)throw ArgumentError(tr('كميات الجرد يجب أن تكون أرقاماً غير سالبة'));
        counted[e.key]=q;
      }
      final id=await AppDatabase.instance.submitStocktake(actorUserId:actorId,counted:counted,note:note.text);
      message(tr('تم إرسال الجرد رقم ')+id.toString()+tr(' دون تغيير المخزون حتى اعتماد المدير.'));
      await load();
    }catch(e){message(e.toString());}
    finally{note.dispose();for(final x in fields.values){x.dispose();}}
  }

  Future<void> reviewStocktakes() async {
    try{
      final db=await AppDatabase.instance.database;
      final pending=await db.rawQuery("SELECT st.*,u.display_name FROM stocktakes st LEFT JOIN users u ON u.id=st.created_by WHERE st.status='submitted' ORDER BY st.id");
      if(pending.isEmpty){message(tr('لا توجد عمليات جرد معلقة'));return;}
      final selected=await showDialog<int>(context:context,builder:(c)=>AlertDialog(
        title:Text(tr('الجردات المعلقة')),
        content:SizedBox(width:420,child:ListView(shrinkWrap:true,children:[
          for(final s in pending)ListTile(title:Text(tr('جرد رقم ')+s['id'].toString()),subtitle:Text(tr('بواسطة ')+s['display_name'].toString()+' • '+s['created_at'].toString()),onTap:()=>Navigator.pop(c,s['id'] as int)),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(tr('إغلاق')))],
      ));
      if(selected==null)return;
      final lines=await db.rawQuery('SELECT l.*,p.name_ar,p.base_unit FROM stocktake_lines l JOIN products p ON p.id=l.product_id WHERE l.stocktake_id=? ORDER BY p.name_ar',[selected]);
      if(!mounted)return;
      final decision=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
        title:Text(tr('مراجعة الجرد رقم ')+selected.toString()),
        content:SizedBox(width:440,child:ListView(shrinkWrap:true,children:[
          Text(tr('سيُرفض الاعتماد تلقائياً إذا حدثت حركة مخزون بعد تسجيل الجرد.')),
          Wrap(children:[IconButton(tooltip:tr('طباعة كشف الجرد'),onPressed:()=>openInventoryDocument('stocktake',selected,false),icon:Icon(Icons.print_outlined)),IconButton(tooltip:tr('مشاركة كشف الجرد'),onPressed:()=>openInventoryDocument('stocktake',selected,true),icon:Icon(Icons.share_outlined))]),
          for(final l in lines)ListTile(title:Text(l['name_ar'].toString()),subtitle:Text(tr('النظام: ')+l['system_qty'].toString()+tr(' • الفعلي: ')+l['counted_qty'].toString()+' '+l['base_unit'].toString()),trailing:Text(tr('الفرق: ')+l['difference_qty'].toString())),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('رفض'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('اعتماد')))],
      ));
      if(decision==null)return;
      await AppDatabase.instance.reviewStocktake(stocktakeId:selected,actorUserId:actorId,approve:decision,note:decision?tr('اعتماد الجرد من إدارة المخزون'):tr('رفض الجرد من إدارة المخزون'));
      await load();message(decision?tr('تم اعتماد الجرد وتعديل الأرصدة.'):tr('تم رفض الجرد.'));
    }catch(e){message(e.toString());}
  }

  Widget _metric(String label,String value,IconData icon)=>SizedBox(width:145,child:ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:Icon(icon,size:20),title:Text(value,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(label,maxLines:2,overflow:TextOverflow.ellipsis)));

  @override Widget build(BuildContext context)=>DefaultTabController(length:6,child:Scaffold(
    appBar:AppBar(title:Text(tr('إدارة المخزون وأمين المخزن')),actions:[IconButton(onPressed:load,icon:Icon(Icons.refresh)),IconButton(onPressed:newIssue,icon:Icon(Icons.add_box_outlined),tooltip:tr('طلب صرف'))],bottom:TabBar(isScrollable:true,tabs:[Tab(text:tr('الأرصدة والتنبيهات')),Tab(text:tr('أذونات الصرف')),Tab(text:tr('المرتجعات')),Tab(text:tr('الهدر والحجز')),Tab(text:tr('الجرد')),Tab(text:tr('استلام التوريد'))])),
    body:loading?const Center(child:CircularProgressIndicator()):TabBarView(children:[
      RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(10),children:[
        Card(child:Padding(padding:const EdgeInsets.all(10),child:Wrap(spacing:10,runSpacing:8,children:[
          _metric(tr('عدد الأصناف'),balances.length.toString(),Icons.inventory_2),
          _metric(tr('مخزون منخفض'),balances.where((p)=>(p['minimum_qty'] as num).toDouble()>0&&(p['approved_qty'] as num).toDouble()<=(p['minimum_qty'] as num).toDouble()).length.toString(),Icons.trending_down),
          _metric(tr('نافد'),balances.where((p)=>(p['approved_qty'] as num).toDouble()<=0).length.toString(),Icons.remove_shopping_cart),
          _metric(tr('استلامات معلقة'),pendingReceiptsCount.toString(),Icons.move_to_inbox),
          _metric(tr('طلبات صرف معلقة'),requests.where((r)=>['submitted','partially_issued'].contains(r['status'])).length.toString(),Icons.outbox),
          _metric(tr('جردات معلقة'),pendingStocktakesCount.toString(),Icons.fact_check),
          _metric(tr('تنبيهات الصلاحية'),expiry.length.toString(),Icons.event_busy),
        ]))),
        TextField(decoration:InputDecoration(prefixIcon:Icon(Icons.search),labelText:tr('البحث عن صنف')),onChanged:(v)=>setState(()=>itemQuery=v)),
        DropdownButtonFormField<String>(value:stockFilter,decoration:InputDecoration(labelText:tr('تصفية حالة المخزون')),items:[DropdownMenuItem(value:'all',child:Text(tr('كل الأصناف'))),DropdownMenuItem(value:'low',child:Text(tr('مخزون منخفض'))),DropdownMenuItem(value:'out',child:Text(tr('نافد'))),DropdownMenuItem(value:'pending',child:Text(tr('كمية غير معتمدة'))),DropdownMenuItem(value:'quarantined',child:Text(tr('كمية محجوزة')))],onChanged:(v)=>setState(()=>stockFilter=v??'all')), 
        DropdownButtonFormField<String>(value:categoryFilter,decoration:InputDecoration(labelText:tr('تصنيف الصنف')),items:[DropdownMenuItem(value:'all',child:Text(tr('كل التصنيفات'))),DropdownMenuItem(value:'none',child:Text(tr('غير مصنف'))),...balances.where((p)=>p['category_id']!=null).map((p)=>MapEntry(p['category_id'].toString(),p['category_name'].toString())).toSet().map((entry)=>DropdownMenuItem(value:entry.key,child:Text(entry.value)))],onChanged:(v)=>setState(()=>categoryFilter=v??'all')), 
        Align(alignment:Alignment.centerRight,child:TextButton(onPressed:()=>setState((){itemQuery='';stockFilter='all';categoryFilter='all';}),child:Text(tr('مسح تصفية الأصناف')))),
        if(admin)Align(alignment:Alignment.centerRight,child:OutlinedButton.icon(onPressed:registerInventoryLot,icon:Icon(Icons.qr_code_2),label:Text(tr('تسجيل دفعة / تاريخ صلاحية')))),
        Card(child:ListTile(leading:Icon(Icons.event_busy),title:Text(tr('تنبيهات الصلاحية: ')+expiry.length.toString()),subtitle:Text(tr('يعرض الدفعات المنتهية أو التي تنتهي خلال 30 يوماً')))),
        for(final lot in expiry)Card(child:ListTile(title:Text(lot['name_ar'].toString()+' • '+lot['lot_code'].toString()),subtitle:Text(tr('الانتهاء: ')+lot['expiry_date'].toString()+tr(' • المتبقي: ')+lot['quantity_remaining'].toString()),trailing:Text(lot['alert']=='expired'?tr('منتهي'):lot['alert']=='expires_today'?tr('ينتهي اليوم'):tr('قريب الانتهاء'),style:TextStyle(color:lot['alert']=='expired'?Colors.red:Colors.orange)))),

        Text(tr('آخر حركات المخزون'),style:Theme.of(context).textTheme.titleMedium),
        Wrap(spacing:8,children:[OutlinedButton.icon(onPressed:()=>openMovementReport(false),icon:Icon(Icons.print_outlined),label:Text(tr('طباعة تقرير الحركة'))),OutlinedButton.icon(onPressed:()=>openMovementReport(true),icon:Icon(Icons.share_outlined),label:Text(tr('مشاركة تقرير الحركة')))]),
        TextField(decoration:InputDecoration(prefixIcon:Icon(Icons.person_search),labelText:tr('تصفية باسم الموظف')),onChanged:(v)=>setState(()=>movementEmployeeQuery=v)),
        DropdownButtonFormField<String>(value:movementTypeFilter,decoration:InputDecoration(labelText:tr('نوع حركة المخزون')),items:[DropdownMenuItem(value:'all',child:Text(tr('كل الحركات'))),...movementRows.map((m)=>m['movement_type'].toString()).toSet().map((v)=>DropdownMenuItem(value:v,child:Text(tr(v))))],onChanged:(v)=>setState(()=>movementTypeFilter=v??'all')),
        Wrap(spacing:8,children:[OutlinedButton(onPressed:()=>chooseMovementDate(true),child:Text(tr('من تاريخ')+': '+(movementFrom?.toIso8601String().substring(0,10)??tr('الكل')))),OutlinedButton(onPressed:()=>chooseMovementDate(false),child:Text(tr('إلى تاريخ')+': '+(movementTo?.toIso8601String().substring(0,10)??tr('الكل')))),TextButton(onPressed:()=>setState((){movementFrom=null;movementTo=null;movementTypeFilter='all';movementEmployeeQuery='';}),child:Text(tr('مسح التصفية')))]),
        for(final m in filteredMovements)Card(child:ListTile(title:Text(m['name_ar'].toString()+' • '+tr((m['movement_type']??'').toString())),subtitle:Text(m['occurred_at'].toString()+' • '+(m['display_name']??tr('غير محدد')).toString()+' • '+(m['source_type']??'').toString()+' #'+(m['source_id']??'-').toString()+'\\n'+(m['note']??'').toString()+'\\n'+tr('قبل الحركة')+': '+(m['balance_before'] as num).toString()+' → '+tr('بعد الحركة')+': '+(m['balance_after'] as num).toString()),isThreeLine:true,trailing:Text((m['quantity_delta'] as num).toDouble().toString(),style:TextStyle(fontWeight:FontWeight.bold,color:(m['quantity_delta'] as num).toDouble()<0?Colors.red:Colors.green)))),
        for(final p in filteredBalances)Card(child:ListTile(
          title:Text(p['name_ar'].toString()),
          subtitle:Text(tr('المعتمد: ')+p['approved_qty'].toString()+' '+p['base_unit'].toString()+tr(' • عهدة المطبخ: ')+(p['kitchen_qty']??0).toString()+tr(' • غير المعتمد: ')+p['unapproved_qty'].toString()+tr(' • محجوز: ')+p['quarantined_qty'].toString()+tr('\nحد الطلب: ')+p['minimum_qty'].toString()+tr(' • كمية إعادة الطلب: ')+p['reorder_qty'].toString()),
          isThreeLine:true,
          onTap:admin?()=>editReorder(p):null,
          trailing:Row(mainAxisSize:MainAxisSize.min,children:[Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(p['on_hand'].toString(),style:Theme.of(context).textTheme.titleMedium),if((p['minimum_qty'] as num).toDouble()>0&&(p['approved_qty'] as num).toDouble()<=(p['minimum_qty'] as num).toDouble())Text(tr('إعادة طلب'),style:TextStyle(color:Colors.red,fontSize:11))]),if(admin)IconButton(tooltip:tr('وحدات الصنف'),onPressed:()=>manageProductUnits(p),icon:const Icon(Icons.straighten))]),
        )),
      ])),
      ListView(padding:const EdgeInsets.all(10),children:[
        FilledButton.icon(onPressed:newIssue,icon:Icon(Icons.add),label:Text(tr('إنشاء طلب صرف مواد'))),
        if(widget.user['role']=='storekeeper'||admin) Padding(padding:const EdgeInsets.only(top:8),child:OutlinedButton.icon(onPressed:()=>newIssue(openingKitchenHandover:true),icon:const Icon(Icons.wb_sunny_outlined),label:Text(tr('تسليم افتتاحي لعهدة المطبخ')))),
        if(requests.isEmpty)Center(child:Padding(padding:EdgeInsets.all(30),child:Text(tr('لا توجد أذونات صرف')))),
        for(final r in requests)Card(child:ListTile(
          title:Text(r['document_no'].toString()+' • '+r['destination'].toString()),
          subtitle:Text(tr('الحالة: ')+r['status'].toString()+tr(' • مقدم الطلب: ')+r['requester_name'].toString()+' • '+r['line_count'].toString()+tr(' أصناف\n')+r['reason'].toString()),
          isThreeLine:true,
          trailing:Wrap(children:[if((admin||(widget.user['role']=='storekeeper'&&r['destination_type']=='kitchen'))&&['submitted','partially_issued'].contains(r['status']))IconButton(icon:Icon(Icons.fact_check),tooltip:tr('مراجعة واعتماد الصرف'),onPressed:()=>reviewIssue(r)),if(admin&&['submitted','partially_issued'].contains(r['status']))IconButton(icon:Icon(Icons.cancel_outlined),tooltip:tr('رفض الطلب'),onPressed:()=>rejectIssue(r)),IconButton(icon:Icon(Icons.print_outlined),tooltip:tr('طباعة إذن الصرف'),onPressed:()=>openInventoryDocument('issue',r['id'] as int,false)),IconButton(icon:Icon(Icons.share_outlined),tooltip:tr('مشاركة إذن الصرف'),onPressed:()=>openInventoryDocument('issue',r['id'] as int,true))]),
        )),
      ]),
      ListView(padding:const EdgeInsets.all(10),children:[
        Text(tr('اختر إذن صرف مسجلاً لتسجيل الكمية المعادة وحالتها.')),
        const SizedBox(height:8),
        FilledButton.icon(onPressed:submitSupplierReturn,icon:Icon(Icons.local_shipping_outlined),label:Text(tr('طلب إرجاع إلى المورد'))),
        const Divider(),
        Text(tr('طلبات إرجاع الموردين'),style:Theme.of(context).textTheme.titleMedium),
        for(final r in supplierReturnRows)Card(child:ListTile(title:Text(r['document_no'].toString()+' • '+r['name_ar'].toString()),subtitle:Text(tr('المورد: ')+r['supplier_name'].toString()+tr(' • الكمية: ')+r['quantity'].toString()+tr(' • الحالة: ')+r['status'].toString()+'\n'+r['reason'].toString()),isThreeLine:true,trailing:Wrap(children:[if(admin&&r['status']=='submitted')IconButton(icon:Icon(Icons.check_circle_outline),tooltip:tr('اعتماد الإرجاع'),onPressed:()=>reviewSupplierReturn(r,true)),if(admin&&r['status']=='submitted')IconButton(icon:Icon(Icons.cancel_outlined),tooltip:tr('رفض الإرجاع'),onPressed:()=>reviewSupplierReturn(r,false)),IconButton(icon:Icon(Icons.print_outlined),tooltip:tr('طباعة سند الإرجاع'),onPressed:()=>openInventoryDocument('supplier_return',r['id'] as int,false)),IconButton(icon:Icon(Icons.share_outlined),tooltip:tr('مشاركة سند الإرجاع'),onPressed:()=>openInventoryDocument('supplier_return',r['id'] as int,true))]))),
        const Divider(),
        Text(tr('المرتجعات المسجلة'),style:Theme.of(context).textTheme.titleMedium),
        for(final r in issueReturnRows)Card(child:ListTile(title:Text(r['name_ar'].toString()+' • '+r['quantity'].toString()+' '+r['unit_snapshot'].toString()),subtitle:Text(tr('الحالة: ')+r['condition_code'].toString()+tr(' • المعيد: ')+r['returned_by_name'].toString()+'\\n'+r['reason'].toString()),isThreeLine:true,trailing:Wrap(children:[IconButton(icon:Icon(Icons.print_outlined),tooltip:tr('طباعة سند المرتجع'),onPressed:()=>openInventoryDocument('return',r['id'] as int,false)),IconButton(icon:Icon(Icons.share_outlined),tooltip:tr('مشاركة سند المرتجع'),onPressed:()=>openInventoryDocument('return',r['id'] as int,true))]))),
        const Divider(),

        for(final r in requests.where((r)=>['issued','partially_issued','rejected'].contains(r['status'])))Card(child:ListTile(title:Text(r['document_no'].toString()+' • '+r['destination'].toString()),subtitle:Text(tr('المستلم: ')+r['received_by_name'].toString()),trailing:IconButton(icon:Icon(Icons.assignment_return),tooltip:tr('تسجيل مرتجع'),onPressed:()=>recordReturn(r)))),
      ]),
      ListView(padding:const EdgeInsets.all(10),children:[
        Wrap(spacing:8,runSpacing:8,children:[FilledButton.icon(onPressed:recordWaste,icon:Icon(Icons.delete_outline),label:Text(tr('تسجيل هدر'))),OutlinedButton.icon(onPressed:quarantineStock,icon:Icon(Icons.health_and_safety_outlined),label:Text(tr('عزل كمية')))]),
        const Divider(),
        Text(tr('سجلات الحجز'),style:Theme.of(context).textTheme.titleMedium),
        for(final q in quarantine)Card(child:ListTile(title:Text(q['name_ar'].toString()+' • '+q['quantity'].toString()+' '+q['unit_snapshot'].toString()),subtitle:Text(tr('الحالة: ')+q['status'].toString()+'\n'+q['reason'].toString()),isThreeLine:true,trailing:Wrap(children:[if(admin&&q['status']=='blocked')IconButton(icon:Icon(Icons.rule),tooltip:tr('إعادة للمخزون أو إتلاف'),onPressed:()=>resolveQuarantine(q)),IconButton(icon:Icon(Icons.print_outlined),tooltip:tr('طباعة سند الحجز'),onPressed:()=>openInventoryDocument('quarantine',q['id'] as int,false)),IconButton(icon:Icon(Icons.share_outlined),tooltip:tr('مشاركة سند الحجز'),onPressed:()=>openInventoryDocument('quarantine',q['id'] as int,true))]))),
        const Divider(),
        Text(tr('آخر سجلات الهدر'),style:Theme.of(context).textTheme.titleMedium),
        for(final w in waste)ListTile(title:Text(w['name_ar'].toString()+' • '+w['quantity'].toString()+' '+w['base_unit'].toString()),subtitle:Text(w['reason_note'].toString()+' • '+w['recorded_at'].toString()),trailing:Wrap(children:[IconButton(icon:Icon(Icons.print_outlined),tooltip:tr('طباعة محضر الهدر'),onPressed:()=>openInventoryDocument('waste',w['id'] as int,false)),IconButton(icon:Icon(Icons.share_outlined),tooltip:tr('مشاركة محضر الهدر'),onPressed:()=>openInventoryDocument('waste',w['id'] as int,true))])),
      ]),
      ListView(padding:const EdgeInsets.all(10),children:[
        FilledButton.icon(onPressed:submitStocktake,icon:Icon(Icons.fact_check),label:Text(tr('إنشاء جرد فعلي وإرساله للمراجعة'))),
        if(admin)FilledButton.tonalIcon(onPressed:reviewStocktakes,icon:Icon(Icons.verified),label:Text(tr('مراجعة الجردات المعلقة'))),
        Text(tr('آخر عمليات الجرد'),style:Theme.of(context).textTheme.titleMedium),
        for(final st in stocktakeRows)Card(child:ListTile(title:Text(tr('جرد رقم ')+st['id'].toString()+' • '+tr((st['status']??'').toString())),subtitle:Text(st['created_at'].toString()+' • '+(st['note']??'').toString()),trailing:Wrap(children:[IconButton(tooltip:tr('طباعة كشف الجرد'),onPressed:()=>openInventoryDocument('stocktake',st['id'] as int,false),icon:Icon(Icons.print_outlined)),IconButton(tooltip:tr('مشاركة كشف الجرد'),onPressed:()=>openInventoryDocument('stocktake',st['id'] as int,true),icon:Icon(Icons.share_outlined))]))),
        ListTile(leading:Icon(Icons.info_outline),title:Text(tr('ضوابط الجرد')),subtitle:Text(tr('لا يتغير الرصيد عند الإرسال. يعتمد المدير الجرد بعد التأكد من عدم وجود حركة لاحقة على الأصناف.'))),
      ]),
      ListView(padding:const EdgeInsets.all(16),children:[
        Card(child:ListTile(leading:Icon(Icons.move_to_inbox),title:Text(tr('استلامات بانتظار الاعتماد')+': '+pendingReceiptsCount.toString()),subtitle:Text(tr('سجّل الكميات المستلمة فعلياً، ثم يتولى المدير مراجعة التكلفة والاعتماد المالي.')))),
        FilledButton.icon(onPressed:openReceivingScreen,icon:Icon(Icons.add_business),label:Text(tr('فتح شاشة استلام المورد'))),
      ]),
    ]),
  ));
}
