import 'package:flutter/material.dart';
import '../data/app_database.dart';
import '../services/document_service.dart';

class CashierScreen extends StatefulWidget {
  final Map<String,Object?> user;
  const CashierScreen({super.key,required this.user});
  @override State<CashierScreen> createState()=>_CashierScreenState();
}
class _CashierScreenState extends State<CashierScreen>{
  List<Map<String,Object?>> products=[];
  List<Map<String,Object?>> customers=[];
  final Map<int,Map<String,Object?>> cart={};
  int? customerId, selectedProductId;
  String keypadBuffer='';
  final discount=TextEditingController(text:'0');
  final paid=TextEditingController(text:'0');
  final discountReason=TextEditingController();
  bool busy=false;
  int get actorId=>widget.user['id'] as int;
  double get subtotal=>cart.values.fold(0.0,(s,l)=>s+(l['quantity'] as double)*(l['unitPrice'] as double));
  double get total=>subtotal-(double.tryParse(discount.text.replaceAll(',','.'))??0);
  Future<void> load() async {
    try{final p=await AppDatabase.instance.sellableProducts(actorUserId:actorId);final c=await AppDatabase.instance.listCustomers(actorUserId:actorId);if(mounted)setState((){products=p;customers=c;});}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  @override void initState(){super.initState();load();}
  void add(Map<String,Object?> p){
    final id=p['id'] as int;
    setState((){
      final old=cart[id];
      if(old==null){cart[id]={'productId':id,'name':p['name_ar'],'unit':p['base_unit'],'quantity':1.0,'unitPrice':(p['sale_price'] as num).toDouble()};}
      else{old['quantity']=(old['quantity'] as double)+1;}
      selectedProductId=id;
    });
  }
  void key(String value){
    if(selectedProductId==null && cart.isNotEmpty)selectedProductId=cart.keys.last;
    setState((){
      if(value=='⌫'){if(keypadBuffer.isNotEmpty)keypadBuffer=keypadBuffer.substring(0,keypadBuffer.length-1);}
      else if(value=='مسح'){keypadBuffer='';}
      else if(value=='✓'){
        final q=double.tryParse(keypadBuffer.replaceAll(',','.'));
        if(q!=null&&q>0&&q.isFinite&&cart.containsKey(selectedProductId)){cart[selectedProductId]!['quantity']=q;keypadBuffer='';}
      }else if(value=='.'){if(!keypadBuffer.contains('.'))keypadBuffer+=keypadBuffer.isEmpty?'0.':'.';}
      else if(keypadBuffer.length<10){keypadBuffer+=value;}
    });
  }
  Future<void> checkout() async {
    if(cart.isEmpty)return;
    final d=double.tryParse(discount.text.replaceAll(',','.'))??0;
    final pay=double.tryParse(paid.text.replaceAll(',','.'))??0;
    setState(()=>busy=true);
    try{
      final id=await AppDatabase.instance.createSale(actorUserId:actorId,customerId:customerId,lines:cart.values.toList(),discount:d,paid:pay,discountReason:discountReason.text);
      final db=await AppDatabase.instance.database;
      final rows=await db.query('sales',where:'id=?',whereArgs:[id],limit:1);
      if(!mounted)return;
      setState((){cart.clear();selectedProductId=null;keypadBuffer='';discount.text='0';paid.text='0';discountReason.clear();});
      await load();
      if(mounted)showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('تم تسجيل الفاتورة'),content:Text('رقم الفاتورة: ${rows.first['invoice_no']}\nالإجمالي: ${rows.first['total']}\nالمدفوع: ${rows.first['paid']}\nالمتبقي: ${rows.first['balance']}'),actions:[TextButton(onPressed:()async{Navigator.pop(c);try{await DocumentService.shareSaleInvoice(id);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذرت مشاركة الفاتورة: $e')));}},child:const Text('مشاركة PDF')),TextButton(onPressed:()async{Navigator.pop(c);try{await DocumentService.printSaleInvoice(id);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذرت الطباعة: $e')));}},child:const Text('طباعة')),FilledButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))]));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Widget keypadButton(String label,{bool primary=false})=>FilledButton.tonal(
    style:FilledButton.styleFrom(padding:EdgeInsets.zero,minimumSize:const Size(0,32),visualDensity:VisualDensity.compact),
    onPressed:()=>key(label),
    child:Text(label,style:TextStyle(fontSize:primary?13:16,fontWeight:FontWeight.w600)),
  );
  @override void dispose(){discount.dispose();paid.dispose();discountReason.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('كاشير المبيعات')),
    body:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(8,4,8,2),child:DropdownButtonFormField<int?>(
        value:customerId,decoration:const InputDecoration(labelText:'الزبون (اتركه للبيع النقدي)',isDense:true,border:OutlineInputBorder()),
        items:[const DropdownMenuItem<int?>(value:null,child:Text('زبون نقدي')),for(final c in customers)DropdownMenuItem<int?>(value:c['id'] as int,child:Text(c['name'].toString()))],
        onChanged:(v)=>setState(()=>customerId=v),
      )),
      Expanded(flex:5,child:GridView.builder(
        padding:const EdgeInsets.all(5),
        gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:5,childAspectRatio:1,crossAxisSpacing:4,mainAxisSpacing:4),
        itemCount:products.length,
        itemBuilder:(c,i){
          final p=products[i];final id=p['id'] as int;final selected=selectedProductId==id;
          return Card(margin:EdgeInsets.zero,color:selected?Theme.of(context).colorScheme.primaryContainer:null,
            child:InkWell(onTap:()=>add(p),child:Padding(padding:const EdgeInsets.all(3),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              Text(p['name_ar'].toString(),textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600)),
              const SizedBox(height:2),
              Text('${p['sale_price']}',style:const TextStyle(fontSize:10)),
              Text(p['is_stock_item']==1?'متاح ${p['on_hand']}':(p['preparation_required']==1?'يتطلب تحضيراً':'جاهز للبيع'),style:const TextStyle(fontSize:9)),
            ]))),
          );
        },
      )),
      const Divider(height:1),
      SizedBox(height:112,child:Column(children:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),child:Row(children:[
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
            const Text('السلة',style:TextStyle(fontWeight:FontWeight.bold)),
            Text(selectedProductId==null?'اختر صنفاً ثم أدخل الكمية':(cart[selectedProductId]?['name'].toString()??''),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)),
          ])),
          const SizedBox(width:8),
          Container(
            width:116,
            constraints:const BoxConstraints(minHeight:38),
            alignment:Alignment.center,
            padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
            decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(8),border:Border.all(color:Theme.of(context).colorScheme.outline)),
            child:Text(keypadBuffer.isEmpty?'0':keypadBuffer,textDirection:TextDirection.ltr,maxLines:1,overflow:TextOverflow.visible,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:22)),
          ),
        ])),
        Expanded(child:cart.isEmpty?const Center(child:Text('اختر المنتجات من الشبكة أعلاه')):ListView(
          scrollDirection:Axis.horizontal,
          children:[for(final l in cart.values)
            Padding(padding:const EdgeInsets.symmetric(horizontal:3,vertical:2),child:ChoiceChip(
              selected:selectedProductId==l['productId'],
              label:Text('${l['name']}\n${l['quantity']} × ${l['unitPrice']}',textAlign:TextAlign.center,style:const TextStyle(fontSize:10)),
              onSelected:(_)=>setState(()=>selectedProductId=l['productId'] as int),
            )),
          ],
        )),
      ])),
      SizedBox(height:116,child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),child:GridView.count(
        physics:const NeverScrollableScrollPhysics(),crossAxisCount:4,mainAxisSpacing:3,crossAxisSpacing:4,childAspectRatio:2.15,
        children:[keypadButton('7'),keypadButton('8'),keypadButton('9'),keypadButton('⌫'),
          keypadButton('4'),keypadButton('5'),keypadButton('6'),keypadButton('مسح',primary:true),
          keypadButton('1'),keypadButton('2'),keypadButton('3'),keypadButton('✓',primary:true),
          keypadButton('0'),keypadButton('0'),keypadButton('.'),keypadButton('✓',primary:true)],
      ))),
      Padding(padding:const EdgeInsets.fromLTRB(8,2,8,8),child:Column(children:[
        Row(children:[Expanded(child:Text('الإجمالي: ${subtotal.toStringAsFixed(2)}')),SizedBox(width:112,child:TextField(controller:discount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الخصم',isDense:true),onChanged:(_)=>setState((){})))]),
        if((double.tryParse(discount.text.replaceAll(',','.'))??0)>0)TextField(controller:discountReason,decoration:const InputDecoration(labelText:'سبب الخصم (إلزامي)',isDense:true)),
        Row(children:[Expanded(child:Text('الصافي: ${total.toStringAsFixed(2)}')),SizedBox(width:112,child:TextField(controller:paid,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المدفوع',isDense:true)))]),
        SizedBox(width:double.infinity,height:38,child:FilledButton.icon(onPressed:busy?null:checkout,icon:const Icon(Icons.receipt_long),label:Text(busy?'جارٍ الحفظ...':'إصدار الفاتورة'))),
      ])),
    ]),
  );
}
