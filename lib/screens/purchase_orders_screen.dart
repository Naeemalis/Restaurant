import 'package:flutter/material.dart';
import '../data/app_database.dart';

class PurchaseOrdersScreen extends StatefulWidget {
  final Map<String,Object?> user;
  const PurchaseOrdersScreen({super.key,required this.user});
  @override State<PurchaseOrdersScreen> createState()=>_PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen>{
  List<Map<String,Object?>> suppliers=[],products=[],orders=[];
  final quantities=<int,TextEditingController>{};
  final invoice=TextEditingController();
  int? supplierId;
  bool loading=true,busy=false;
  int get actorId=>widget.user['id'] as int;
  String get language=>(widget.user['preferred_language']??'ar').toString();

  @override void initState(){super.initState();load();}
  @override void dispose(){for(final c in quantities.values){c.dispose();}invoice.dispose();super.dispose();}
  void message(String value)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));

  Future<void> load() async{
    setState(()=>loading=true);
    try{
      final db=AppDatabase.instance;
      final a=await db.listSuppliers(actorUserId:actorId);
      final b=await db.purchaseableProducts(actorUserId:actorId,language:language);
      final c=await db.purchaseOrders(actorUserId:actorId);
      for(final p in b){quantities.putIfAbsent(p['id'] as int,()=>TextEditingController());}
      if(!mounted)return;
      setState(()=>{suppliers=a,products=b,orders=c});
    }catch(e){if(mounted)message(e.toString());}
    finally{if(mounted)setState(()=>loading=false);}
  }

  Future<void> createOrder() async{
    if(supplierId==null){message('اختر المورد أولاً');return;}
    final lines=<Map<String,Object?>>[];
    for(final p in products){
      final raw=quantities[p['id'] as int]!.text.trim();
      if(raw.isEmpty)continue;
      final q=double.tryParse(raw.replaceAll(',','.'));
      if(q==null||!q.isFinite||q<=0){message('كمية غير صحيحة للصنف '+p['name_ar'].toString());return;}
      lines.add({'productId':p['id'],'quantity':q,'enteredQuantity':q,'enteredUnitName':p['base_unit'],'conversionToBase':1.0});
    }
    if(lines.isEmpty){message('أدخل كمية لصنف واحد على الأقل');return;}
    setState(()=>busy=true);
    try{
      final id=await AppDatabase.instance.createPurchaseOrder(actorUserId:actorId,supplierId:supplierId!,notes:'',lines:lines);
      for(final c in quantities.values){c.clear();}
      await load();
      if(mounted)message('تم إنشاء طلب التوريد رقم '+id.toString()+' دون تغيير رصيد المخزن.');
    }catch(e){if(mounted)message(e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> receiveOrder(Map<String,Object?> order) async{
    final id=order['id'] as int;
    final lines=await AppDatabase.instance.purchaseOrderLines(actorUserId:actorId,orderId:id,language:language);
    final eligible=lines.where((l)=>(l['remaining_to_receive'] as num).toDouble()>0.000001).toList();
    if(eligible.isEmpty){message('لا توجد كميات متبقية للاستلام');return;}
    final received={for(final l in eligible)l['id'] as int:TextEditingController(text:(l['remaining_to_receive'] as num).toString())};
    invoice.clear();
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text('استلام طلب '+order['document_no'].toString()),
      content:SizedBox(width:460,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('المورد: '+order['supplier_name'].toString()),
        TextField(controller:invoice,decoration:const InputDecoration(labelText:'رقم فاتورة المورد')),
        for(final l in eligible)Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Row(children:[
          Expanded(child:Text(l['name_ar'].toString()+'\nالمتبقي: '+l['remaining_to_receive'].toString()+' '+l['base_unit'].toString())),
          SizedBox(width:105,child:TextField(controller:received[l['id'] as int],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'المستلم ('+l['base_unit'].toString()+')'))),
        ])),
        const Text('أدخل الكمية التي وصلت فعلياً. يمكن ترك الصنف دون استلام، ويمكن استلام الطلب على دفعات.'),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('تسجيل الاستلام'))],
    ));
    if(ok==true){
      if(invoice.text.trim().isEmpty){message('أدخل رقم فاتورة المورد');}
      else{
        final receiptLines=<Map<String,Object?>>[];final orderLineIds=<int,int>{};
        for(final l in eligible){
          final raw=received[l['id'] as int]!.text.trim();
          if(raw.isEmpty)continue;
          final q=double.tryParse(raw.replaceAll(',','.'));
          if(q==null||!q.isFinite||q<=0){message('كمية استلام غير صحيحة');return;}
          final productId=l['product_id'] as int;
          receiptLines.add({'productId':productId,'quantity':q,'enteredQuantity':q,'enteredUnitName':l['base_unit'],'conversionToBase':1.0});
          orderLineIds[productId]=l['id'] as int;
        }
        if(receiptLines.isEmpty){message('أدخل كمية مستلمة واحدة على الأقل');}
        else{
          setState(()=>busy=true);
          try{
            final receiptId=await AppDatabase.instance.submitPurchaseReceipt(actorUserId:actorId,supplierId:order['supplier_id'] as int,invoiceNo:invoice.text,lines:receiptLines,purchaseOrderId:id,orderLineIds:orderLineIds);
            if(mounted)message('سُجل الاستلام رقم '+receiptId.toString()+' بانتظار اعتماد المدير.');
            await load();
          }catch(e){if(mounted)message(e.toString());}
          finally{if(mounted)setState(()=>busy=false);}
        }
      }
    }
    for(final c in received.values){c.dispose();}
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('طلبات التوريد'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(12),children:[
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('إنشاء طلب توريد جديد',style:Theme.of(context).textTheme.titleLarge),
        DropdownButtonFormField<int>(value:supplierId,decoration:const InputDecoration(labelText:'المورد'),items:[for(final s in suppliers)DropdownMenuItem(value:s['id'] as int,child:Text(s['name'].toString()))],onChanged:(v)=>setState(()=>supplierId=v)),
        const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('اختر الأصناف من مركز الأصناف وأدخل الكمية المطلوبة بوحدة الأساس. لا يتغير المخزون عند إنشاء الطلب.')),
        for(final p in products)Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[
          Expanded(child:Text(p['name_ar'].toString()+' • '+p['base_unit'].toString())),
          SizedBox(width:110,child:TextField(controller:quantities[p['id'] as int],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الكمية المطلوبة'))),
        ])),
        FilledButton(onPressed:busy?null:createOrder,child:Text(busy?'جارٍ الحفظ':'حفظ طلب التوريد')),
      ]))),
      Text('طلبات التوريد المفتوحة ('+orders.length.toString()+')',style:Theme.of(context).textTheme.titleLarge),
      if(orders.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('لا توجد طلبات توريد مفتوحة.')),
      for(final o in orders)Card(child:ListTile(
        title:Text(o['document_no'].toString()+' • '+o['supplier_name'].toString()),
        subtitle:Text('الأصناف: '+o['line_count'].toString()+' • الحالة: '+(o['status']=='partially_received'?'استلام جزئي':'بانتظار الاستلام')+'\nالمطلوب: '+o['ordered_total'].toString()+' • المستلم: '+o['received_total'].toString()),
        isThreeLine:true,
        trailing:IconButton(tooltip:'تسجيل استلام',onPressed:busy?null:()=>receiveOrder(o),icon:const Icon(Icons.move_to_inbox)),
      )),
    ]),
  );
}
