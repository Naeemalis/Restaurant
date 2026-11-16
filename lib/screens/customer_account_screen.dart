import 'package:flutter/material.dart';
import '../data/app_database.dart';

class CustomerAccountScreen extends StatefulWidget {
  final Map<String,Object?> user;
  final Map<String,Object?> customer;
  const CustomerAccountScreen({super.key,required this.user,required this.customer});
  @override State<CustomerAccountScreen> createState()=>_CustomerAccountScreenState();
}
class _CustomerAccountScreenState extends State<CustomerAccountScreen>{
  List<Map<String,Object?>> entries=[];
  bool loading=true;
  int get actorId=>widget.user['id'] as int;
  int get customerId=>widget.customer['id'] as int;
  Future<void> load() async {
    try{final r=await AppDatabase.instance.customerStatement(actorUserId:actorId,customerId:customerId);if(mounted)setState(()=>entries=r);}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override void initState(){super.initState();load();}
  Future<void> collect() async {
    final amount=TextEditingController();
    final note=TextEditingController(text:'تحصيل من الزبون');
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('تسجيل تحصيل'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المبلغ')),
      TextField(controller:note,decoration:const InputDecoration(labelText:'البيان')),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('تسجيل'))]));
    if(ok==true){try{await AppDatabase.instance.receiveCustomerPayment(actorUserId:actorId,customerId:customerId,amount:double.parse(amount.text.replaceAll(',','.')),note:note.text);await load();}
      catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
    amount.dispose();note.dispose();
  }
  @override Widget build(BuildContext context){
    final debit=entries.fold<double>(0,(s,e)=>s+((e['debit'] as num?)?.toDouble()??0));
    final credit=entries.fold<double>(0,(s,e)=>s+((e['credit'] as num?)?.toDouble()??0));
    final balance=debit-credit;
    return Scaffold(appBar:AppBar(title:Text('كشف حساب: ${widget.customer['name']}')),floatingActionButton:FloatingActionButton.extended(onPressed:collect,icon:const Icon(Icons.payments),label:const Text('تحصيل')),body:loading?const Center(child:CircularProgressIndicator()):Column(children:[
      Card(margin:const EdgeInsets.all(12),child:Padding(padding:const EdgeInsets.all(16),child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[
        _amount('مدين',debit),_amount('دائن',credit),_amount(balance>0?'المتبقي':'الرصيد',balance.abs()),
      ]))),
      const ListTile(title:Text('التاريخ / المرجع / الحركة'),trailing:Text('مدين | دائن')),
      Expanded(child:ListView.separated(itemCount:entries.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(c,i){final e=entries[i];return ListTile(title:Text('${e['type']} • ${e['reference']}'),subtitle:Text(e['date'].toString()),trailing:Text('${e['debit']} | ${e['credit']}'));})),
      if(entries.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('لا توجد حركات حسابية لهذا الزبون')),
    ]));
  }
  Widget _amount(String label,double value)=>Column(children:[Text(label),Text(value.toStringAsFixed(2),style:const TextStyle(fontWeight:FontWeight.bold))]);
}
