import 'package:flutter/material.dart';
import '../data/app_database.dart';
import '../data/inventory_service.dart';

class KitchenScreen extends StatefulWidget {
  final Map<String,Object?> user;
  const KitchenScreen({super.key,required this.user});
  @override State<KitchenScreen> createState()=>_KitchenScreenState();
}
class _KitchenScreenState extends State<KitchenScreen>{
  List<Map<String,Object?>> orders=[], kitchenStock=[], replenishments=[];
  bool loading=true;
  bool get kitchenUser=>widget.user['role']=='kitchen';
  int get actorId=>widget.user['id'] as int;
  String tr(String ar){
    final lang=(widget.user['preferred_language']??'ar').toString();
    const words=<String,Map<String,String>>{
      'شاشة المطبخ':{'en':'Kitchen','fr':'Cuisine'},
      'جديد':{'en':'New','fr':'Nouveau'},
      'قيد التحضير':{'en':'Preparing','fr':'En préparation'},
      'جاهز':{'en':'Ready','fr':'Prêt'},
      'ملغي':{'en':'Cancelled','fr':'Annulé'},
      'إلغاء طلب المطبخ':{'en':'Cancel kitchen order','fr':'Annuler la commande cuisine'},
      'سبب الإلغاء (إلزامي)':{'en':'Cancellation reason (required)','fr':"Motif d'annulation (obligatoire)"},
      'رجوع':{'en':'Back','fr':'Retour'},
      'تأكيد الإلغاء':{'en':'Confirm cancellation','fr':"Confirmer l'annulation"},
      'تعديل كميات الوجبات':{'en':'Edit meal quantities','fr':'Modifier les quantités des plats'},
      'الزيادة تخصم المكونات الإضافية فقط، والنقص يعيد الفرق للمخزون.':{'en':'An increase consumes additional ingredients; a decrease returns the difference to kitchen custody.','fr':'Une augmentation consomme des ingrédients supplémentaires ; une diminution retourne la différence au stock cuisine.'},
      'حفظ التعديل':{'en':'Save changes','fr':'Enregistrer les modifications'},
      'تم تعديل الطلب وتحديث المخزون والفاتورة':{'en':'Order, stock and invoice updated','fr':'Commande, stock et facture mis à jour'},
      'أدخل كميات صحيحة غير سالبة':{'en':'Enter valid non-negative quantities','fr':'Saisissez des quantités valides et positives ou nulles'},
      'طلب تزويد من المخزن':{'en':'Request stock replenishment','fr':'Demander un réapprovisionnement'},
      'أدخل الكمية الإضافية المطلوبة بوحدة الصنف الأساسية. سيصل الطلب إلى أمين المخزن للمراجعة والصرف.':{'en':'Enter the additional quantity in the item base unit. The request will be sent to the Storekeeper for review and issue.','fr':'Saisissez la quantité supplémentaire dans l’unité de base. La demande sera envoyée au magasinier pour examen et sortie.'},
      'المطلوب':{'en':'Requested','fr':'Demandé'},
      'سبب طلب التزويد':{'en':'Replenishment reason','fr':'Motif de réapprovisionnement'},
      'إلغاء':{'en':'Cancel','fr':'Annuler'},
      'إرسال الطلب':{'en':'Submit request','fr':'Envoyer la demande'},
      'أدخل كميات موجبة وصحيحة':{'en':'Enter valid quantities greater than zero','fr':'Saisissez des quantités valides supérieures à zéro'},
      'حدد كمية صنف واحد على الأقل':{'en':'Enter a quantity for at least one item','fr':'Saisissez une quantité pour au moins un article'},
      'طلبات التزويد المرسلة':{'en':'Submitted replenishment requests','fr':'Demandes de réapprovisionnement envoyées'},
      'طلبات الوجبات':{'en':'Meal orders','fr':'Commandes de plats'},
      'لا توجد طلبات وجبات مرسلة للمطبخ':{'en':'No meal orders have been sent to the kitchen','fr':'Aucune commande de plat envoyée à la cuisine'},
      'عهدة المطبخ':{'en':'Kitchen custody','fr':'Stock de la cuisine'},
      'طلب تزويد إضافي من المخزن':{'en':'Request additional stock from store','fr':'Demander un complément au magasin'},
      'بدء التحضير':{'en':'Start preparation','fr':'Commencer la préparation'},
      'تحديد الطلب جاهز':{'en':'Mark order ready','fr':'Marquer la commande prête'},
      'إلغاء الطلب قبل بدء التحضير':{'en':'Cancel before preparation starts','fr':'Annuler avant le début de la préparation'},
      'فاتورة ': {'en':'Invoice ','fr':'Facture '},
      'بانتظار أمين المخزن':{'en':'Awaiting Storekeeper','fr':'En attente du magasinier'},
      'تم الصرف جزئياً':{'en':'Partially issued','fr':'Partiellement délivré'},
      'تم الصرف بالكامل':{'en':'Fully issued','fr':'Entièrement délivré'},
      'مرفوض':{'en':'Rejected','fr':'Rejeté'},
      'المتاح بالمطبخ: ': {'en':'Kitchen available: ','fr':'Disponible en cuisine : '},
      'نقص أثناء التشغيل':{'en':'Shortage during operations','fr':'Manque pendant le service'},
      'إلى أمين المخزن':{'en':'to the Storekeeper','fr':'au magasinier'},
      'تم إرسال طلب التزويد رقم ':{'en':'Replenishment request ','fr':'Demande de réapprovisionnement '},
      'تعديل كميات الطلب':{'en':'Edit order quantities','fr':'Modifier les quantités de la commande'},

    };
    return words[ar]?[lang]??ar;
  }
  @override void initState(){super.initState();load();}
  String statusName(String s)=>s=='new'?tr('جديد'):s=='preparing'?tr('قيد التحضير'):s=='ready'?tr('جاهز'):tr('ملغي');
  Future<void> load()async{
    setState(()=>loading=true);
    try{final r=await AppDatabase.instance.kitchenOrders(actorUserId:actorId); final db=await AppDatabase.instance.database; final stock=kitchenUser?await InventoryService.kitchenStockItems(db,actorUserId:actorId,language:(widget.user['preferred_language']??'ar').toString()):<Map<String,Object?>>[]; final requests=kitchenUser?await InventoryService.kitchenRequests(db,actorUserId:actorId,language:(widget.user['preferred_language']??'ar').toString()):<Map<String,Object?>>[]; if(mounted)setState((){orders=r;kitchenStock=stock;replenishments=requests;});}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> cancel(Map<String,Object?> order) async{
    final reason=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text(tr('إلغاء طلب المطبخ')),
      content:TextField(controller:reason,maxLines:3,decoration:InputDecoration(labelText:tr('سبب الإلغاء (إلزامي)'))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('رجوع'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('تأكيد الإلغاء')))],
    ));
    if(ok==true){
      try{await AppDatabase.instance.voidSale(actorUserId:actorId,saleId:order['sale_id'] as int,reason:reason.text);await load();}
      catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    }
    reason.dispose();
  }
  Future<void> editQuantities(Map<String,Object?> order) async {
    final orderId=order['kitchen_order_id'] as int;
    final lines=await AppDatabase.instance.kitchenOrderLines(actorUserId:actorId,kitchenOrderId:orderId);
    final fields=<int,TextEditingController>{
      for(final line in lines) line['sale_line_id'] as int: TextEditingController(text:line['quantity'].toString()),
    };
    try {
      final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
        title:Text(tr('تعديل كميات الوجبات')),
        content:SizedBox(width:360,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(tr('الزيادة تخصم المكونات الإضافية فقط، والنقص يعيد الفرق للمخزون.')),
          for(final line in lines) Row(children:[
            Expanded(child:Text(line['product_name_snapshot'].toString())),
            SizedBox(width:100,child:TextField(controller:fields[line['sale_line_id'] as int],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:line['unit_snapshot'].toString()))),
          ]),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('رجوع'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('حفظ التعديل')))],
      ));
      if(ok!=true)return;
      final values=<int,double>{};
      for(final entry in fields.entries){
        final value=double.tryParse(entry.value.text.trim().replaceAll(',','.'));
        if(value==null||!value.isFinite||value<0)throw ArgumentError('أدخل كميات صحيحة غير سالبة');
        values[entry.key]=value;
      }
      await AppDatabase.instance.updateKitchenOrderQuantities(actorUserId:actorId,kitchenOrderId:orderId,quantities:values);
      await load();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(tr('تم تعديل الطلب وتحديث المخزون والفاتورة'))));
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
    } finally {
      for(final field in fields.values){field.dispose();}
    }
  }
  Future<void> requestReplenishment() async {
    final fields=<int,TextEditingController>{
      for(final p in kitchenStock) p['id'] as int:TextEditingController(),
    };
    final reason=TextEditingController(text:tr('نقص أثناء التشغيل'));
    try {
      final ok=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
        title:Text(tr('طلب تزويد من المخزن')),
        content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(tr('أدخل الكمية الإضافية المطلوبة بوحدة الصنف الأساسية. سيصل الطلب إلى أمين المخزن للمراجعة والصرف.')),
          for(final p in kitchenStock) Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[
            Expanded(child:Text('${p['name_ar']} • المتاح بالمطبخ: ${p['kitchen_qty']} ${p['base_unit']}')),
            SizedBox(width:95,child:TextField(controller:fields[p['id'] as int],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('المطلوب')))),
          ])),
          TextField(controller:reason,maxLines:2,decoration:InputDecoration(labelText:tr('سبب طلب التزويد'))),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:Text(tr('إلغاء'))),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:Text(tr('إرسال الطلب')))],
      ));
      if(ok!=true)return;
      final quantities=<int,double>{};
      for(final entry in fields.entries){
        final raw=entry.value.text.trim();
        if(raw.isEmpty)continue;
        final qty=double.tryParse(raw.replaceAll(',','.'));
        if(qty==null||!qty.isFinite||qty<=0)throw ArgumentError('أدخل كميات موجبة وصحيحة');
        quantities[entry.key]=qty;
      }
      if(quantities.isEmpty)throw ArgumentError('حدد كمية صنف واحد على الأقل');
      final db=await AppDatabase.instance.database;
      final id=await InventoryService.submitIssueRequest(db,actorUserId:actorId,destination:'المطبخ',destinationType:'kitchen',reason:reason.text,receiverName:widget.user['display_name'].toString(),quantities:quantities);
      await load();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(tr('تم إرسال طلب التزويد رقم ')+id.toString()+' '+tr('إلى أمين المخزن'))));
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
    } finally {
      for(final field in fields.values){field.dispose();}
      reason.dispose();
    }
  }
  String replenishmentStatus(String s)=>s=='submitted'?tr('بانتظار أمين المخزن'):s=='partially_issued'?tr('تم الصرف جزئياً'):s=='issued'?tr('تم الصرف بالكامل'):s=='rejected'?tr('مرفوض'):'$s';
  Future<void> change(int id,String status)async{
    try{await AppDatabase.instance.updateKitchenOrderStatus(actorUserId:actorId,kitchenOrderId:id,status:status);await load();}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(tr('شاشة المطبخ')),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(10),children:[
      if(kitchenUser) Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(tr('عهدة المطبخ'),style:TextStyle(fontWeight:FontWeight.bold)),
        for(final p in kitchenStock) ListTile(dense:true,title:Text(p['name_ar'].toString()),trailing:Text('${p['kitchen_qty']} ${p['base_unit']}')),
        FilledButton.icon(onPressed:requestReplenishment,icon:const Icon(Icons.add_box_outlined),label:Text(tr('طلب تزويد إضافي من المخزن'))),
      ]))),
      if(kitchenUser) Padding(padding:const EdgeInsets.fromLTRB(4,12,4,4),child:Text(tr('طلبات التزويد المرسلة'),style:const TextStyle(fontWeight:FontWeight.bold))),
      if(kitchenUser) for(final r in replenishments) Card(child:ListTile(title:Text(r['document_no'].toString()),subtitle:Text('${r['reason']} • ${r['lines_summary']??''}'),trailing:Text(replenishmentStatus(r['status'].toString())))),
      Padding(padding:const EdgeInsets.fromLTRB(4,12,4,4),child:Text(tr('طلبات الوجبات'),style:const TextStyle(fontWeight:FontWeight.bold))),
      if(orders.isEmpty) Padding(padding:const EdgeInsets.all(20),child:Text(tr('لا توجد طلبات وجبات مرسلة للمطبخ'))),
      ...orders.asMap().entries.map((entry){final index=entry.key; final o=entry.value;
      final id=o['kitchen_order_id'] as int;final status=o['status'].toString();
      return Card(child:ExpansionTile(
        leading:CircleAvatar(child:Text((index+1).toString())),
        title:Text(tr('فاتورة ')+o['invoice_no'].toString()),
        subtitle:Text(statusName(status)+' • '+o['created_at'].toString()),
        children:[
          FutureBuilder<List<Map<String,Object?>>>(future:AppDatabase.instance.kitchenOrderLines(actorUserId:actorId,kitchenOrderId:id),builder:(c,s)=>s.connectionState!=ConnectionState.done?const Padding(padding:EdgeInsets.all(12),child:CircularProgressIndicator()):Column(children:[for(final l in s.data??[])ListTile(title:Text(l['product_name_snapshot'].toString()),trailing:Text(l['quantity'].toString()+' '+l['unit_snapshot'].toString()))])),
          if((widget.user['role']=='admin'||widget.user['role']=='cashier')&&(status=='new'||status=='preparing'))Padding(padding:const EdgeInsets.all(8),child:OutlinedButton.icon(onPressed:()=>editQuantities(o),icon:const Icon(Icons.edit),label:Text(tr('تعديل كميات الوجبات')))),
          if(status=='new')Padding(padding:const EdgeInsets.all(8),child:FilledButton(onPressed:()=>change(id,'preparing'),child:Text(tr('بدء التحضير')))),
          if(status=='preparing')Padding(padding:const EdgeInsets.all(8),child:FilledButton(onPressed:()=>change(id,'ready'),child:Text(tr('تحديد الطلب جاهز')))),
          if((widget.user['role']=='admin'||widget.user['role']=='cashier')&&status=='new')Padding(padding:const EdgeInsets.all(8),child:OutlinedButton.icon(onPressed:()=>cancel(o),icon:const Icon(Icons.cancel_outlined),label:Text(tr('إلغاء الطلب قبل بدء التحضير')))),
        ],
      );
      }).toList(),
    ]),
  );
}
