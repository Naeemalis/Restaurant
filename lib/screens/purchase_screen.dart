import 'package:flutter/material.dart';
import '../data/app_database.dart';
import '../data/inventory_service.dart';
import '../services/document_service.dart';

class PurchaseScreen extends StatefulWidget {
  final Map<String,Object?> user;
  const PurchaseScreen({super.key,required this.user});
  @override State<PurchaseScreen> createState()=>_PurchaseScreenState();
}
class _PurchaseScreenState extends State<PurchaseScreen>{
  List<Map<String,Object?>> suppliers=[],products=[],pending=[];
  final invoice=TextEditingController();
  final qty=<int,TextEditingController>{};
  final unitOptions=<int,List<Map<String,Object?>>>{};
  final selectedUnitIds=<int,int>{};
  int? supplierId,lastSubmittedReceiptId; bool loading=true,busy=false;
  String get language=>(widget.user['preferred_language']??'ar').toString();
  int get actorId=>widget.user['id'] as int;
  bool get admin=>widget.user['role']=='admin';
  @override void initState(){super.initState();load();}
  void msg(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
  Future<void> load() async{
    setState(()=>loading=true);
    try{
      final d=AppDatabase.instance;
      final a=await d.listSuppliers(actorUserId:actorId);
      final b=await d.purchaseableProducts(actorUserId:actorId);
      final c=admin?await d.pendingPurchaseReceipts(actorUserId:actorId):<Map<String,Object?>>[];
      final database=await d.database;
      final options=<int,List<Map<String,Object?>>>{};
      for(final product in b){final id=product['id'] as int;options[id]=await InventoryService.productUnits(database,actorUserId:actorId,productId:id,language:language,forPurchase:true);}
      if(!mounted)return;
      setState(() { suppliers=a; products=b; pending=c; unitOptions.addAll(options); });
      for(final p in products){final id=p['id'] as int;qty.putIfAbsent(id,()=>TextEditingController());selectedUnitIds.putIfAbsent(id,()=>0);}
    }catch(e){if(mounted)msg(e.toString());}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> submit() async{
    final lines=<Map<String,Object?>>[];
    for(final p in products){
      final raw=qty[p['id'] as int]!.text.trim();
      if(raw.isEmpty)continue;
      final n=double.tryParse(raw.replaceAll(',','.'));
      if(n==null||!n.isFinite||n<=0){msg('كمية غير صحيحة: '+p['name_ar'].toString());return;}
      final productId=p['id'] as int;
      try{
        final baseQuantity=await InventoryService.toBaseQuantity(await AppDatabase.instance.database,actorUserId:actorId,productId:productId,quantity:n,unitId:selectedUnitIds[productId]??0,forPurchase:true);
        final unit=(unitOptions[productId]??[]).firstWhere((u)=>(u['id'] as int)==(selectedUnitIds[productId]??0));
        lines.add({'productId':productId,'quantity':baseQuantity,'enteredQuantity':n,'enteredUnitName':unit['unit_name'].toString(),'conversionToBase':(unit['conversion_to_base'] as num).toDouble()});
      }catch(e){msg(e.toString());return;}
    }
    if(supplierId==null||invoice.text.trim().isEmpty||lines.isEmpty){msg('حدد المورد ورقم الفاتورة والكمية');return;}
    setState(()=>busy=true);
    try{
      final id=await AppDatabase.instance.submitPurchaseReceipt(actorUserId:actorId,supplierId:supplierId!,invoiceNo:invoice.text,lines:lines);
      invoice.clear();for(final c in qty.values){c.clear();}
      await load();if(mounted){setState(()=>lastSubmittedReceiptId=id);msg('تم تسجيل الاستلام رقم '+id.toString()+' ككمية فعلية غير معتمدة؛ لا تدخل البيع أو التكلفة حتى اعتماد المدير.');}
    }catch(e){if(mounted)msg(e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> approve(Map<String,Object?> r) async{
    final id=r['id'] as int;
    final lines=await AppDatabase.instance.purchaseReceiptLines(actorUserId:actorId,receiptId:id);
    final costs=<int,TextEditingController>{for(final l in lines)l['id'] as int:TextEditingController()};
    if(!mounted)return;
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text('اعتماد فاتورة '+r['invoice_no'].toString()),
      content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('المورد: '+r['supplier_name'].toString()),
        for(final l in lines)Row(children:[
          Expanded(child:Text(l['name_ar'].toString()+'\n'+(l['entered_qty']??l['received_qty']).toString()+' '+((l['entered_unit_name']??'').toString().isEmpty?l['base_unit'].toString():l['entered_unit_name'].toString())+' = '+l['received_qty'].toString()+' '+l['base_unit'].toString())),
          SizedBox(width:110,child:TextField(controller:costs[l['id'] as int],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'تكلفة الوحدة'))),
        ]),
        const Text('الكميات الفعلية مسجلة مسبقاً كغير معتمدة. عند الاعتماد تُحوّل إلى رصيد معتمد ويُحدّث متوسط التكلفة وحساب المورد دون مضاعفة الكمية الفعلية.'),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('رجوع')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('اعتماد'))],
    ));
    if(ok==true){
      try{
        final map=<int,double>{};
        for(final l in lines){final lid=l['id'] as int;final v=double.tryParse(costs[lid]!.text.replaceAll(',','.'));if(v==null||!v.isFinite||v<0)throw ArgumentError('تكلفة غير صحيحة');map[lid]=v;}
        await AppDatabase.instance.approvePurchaseReceipt(actorUserId:actorId,receiptId:id,unitCosts:map);
        await load();if(mounted)msg('تم الاعتماد وتحديث المخزون.');
      }catch(e){if(mounted)msg(e.toString());}
    }
    for(final c in costs.values){c.dispose();}
  }
  Future<void> reject(Map<String,Object?> r) async{
    final reason=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('سبب رفض الاستلام'),content:TextField(controller:reason),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('رجوع')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('رفض'))]));
    if(ok==true){try{await AppDatabase.instance.rejectPurchaseReceipt(actorUserId:actorId,receiptId:r['id'] as int,reason:reason.text);await load();}catch(e){if(mounted)msg(e.toString());}}
    reason.dispose();
  }
  @override void dispose(){invoice.dispose();for(final c in qty.values){c.dispose();}super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('كاشير التوريد')),body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(12),children:[
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Text('تسجيل استلام المورد',style:Theme.of(context).textTheme.titleLarge),
      DropdownButtonFormField<int>(value:supplierId,decoration:const InputDecoration(labelText:'المورد'),items:[for(final s in suppliers)DropdownMenuItem(value:s['id'] as int,child:Text(s['name'].toString()))],onChanged:(v)=>setState(()=>supplierId=v)),
      TextField(controller:invoice,decoration:const InputDecoration(labelText:'رقم فاتورة المورد')),
      const Text('اختر وحدة الشراء المناسبة لكل صنف. يحوّل النظام الكمية تلقائياً إلى وحدة الأساس قبل تسجيل الاستلام؛ التكلفة التي يدخلها المدير عند الاعتماد تكون لكل وحدة أساس.'),
      for(final p in products)Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(p['name_ar'].toString(),style:const TextStyle(fontWeight:FontWeight.w600)),
        Text('الرصيد بالوحدة الأساسية '+p['base_unit'].toString()+': '+p['on_hand'].toString()+' • المعتمد: '+p['approved_qty'].toString()+' • معلق: '+p['unapproved_qty'].toString()),
        Row(children:[Expanded(child:DropdownButtonFormField<int>(value:selectedUnitIds[p['id'] as int]??0,decoration:const InputDecoration(labelText:'وحدة الاستلام'),items:[for(final u in unitOptions[p['id'] as int]??[])DropdownMenuItem(value:u['id'] as int,child:Text(u['unit_name'].toString()+' × '+u['conversion_to_base'].toString()+' '+p['base_unit'].toString()))],onChanged:(v)=>setState(()=>selectedUnitIds[p['id'] as int]=v??0))),const SizedBox(width:8),SizedBox(width:110,child:TextField(controller:qty[p['id'] as int],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الكمية')))]),
      ])),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:submit,child:Text(busy?'جارٍ الإرسال':'إرسال للمدير'))),
    ]))),
    if(lastSubmittedReceiptId!=null)Wrap(spacing:8,children:[OutlinedButton.icon(onPressed:()=>DocumentService.printInventoryDocument('receipt',lastSubmittedReceiptId!,language:language),icon:const Icon(Icons.print),label:const Text('طباعة سند الاستلام')),OutlinedButton.icon(onPressed:()=>DocumentService.shareInventoryDocument('receipt',lastSubmittedReceiptId!,language:language),icon:const Icon(Icons.share),label:const Text('مشاركة سند الاستلام'))]),
    if(admin)Text('استلامات بانتظار الاعتماد ('+pending.length.toString()+')',style:Theme.of(context).textTheme.titleLarge),
    if(admin)for(final r in pending)Card(child:ListTile(title:Text('فاتورة '+r['invoice_no'].toString()+' • '+r['supplier_name'].toString()),subtitle:Text('الأصناف: '+r['line_count'].toString()),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='a')approve(r);if(v=='r')reject(r);if(v=='p')DocumentService.printInventoryDocument('receipt',r['id'] as int,language:language);if(v=='s')DocumentService.shareInventoryDocument('receipt',r['id'] as int,language:language);},itemBuilder:(_)=>const[PopupMenuItem(value:'a',child:Text('مراجعة واعتماد')),PopupMenuItem(value:'r',child:Text('رفض')),PopupMenuItem(value:'p',child:Text('طباعة سند الاستلام')),PopupMenuItem(value:'s',child:Text('مشاركة سند الاستلام'))]))),
  ]));
}
