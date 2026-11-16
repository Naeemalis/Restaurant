import 'package:flutter/material.dart';
import '../data/app_database.dart';
import 'customer_account_screen.dart';

class CustomerManagementScreen extends StatefulWidget {
  final Map<String,Object?> user;
  const CustomerManagementScreen({super.key,required this.user});
  @override State<CustomerManagementScreen> createState()=>_CustomerManagementScreenState();
}
class _CustomerManagementScreenState extends State<CustomerManagementScreen>{
  List<Map<String,Object?>> rows=[];
  int get actorId=>widget.user['id'] as int;
  Future<void> load() async { final r=await AppDatabase.instance.listCustomers(actorUserId:actorId); if(mounted)setState(()=>rows=r); }
  @override void initState(){super.initState();load();}
  Future<void> edit([Map<String,Object?>? row]) async {
    final n=TextEditingController(text:row?['name']?.toString()??'');
    final p=TextEditingController(text:row?['phone']?.toString()??'');
    final a=TextEditingController(text:row?['address']?.toString()??'');
    final notes=TextEditingController(text:row?['notes']?.toString()??'');
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(row==null?'إضافة زبون':'تعديل زبون'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:n,decoration:const InputDecoration(labelText:'اسم الزبون')),
      TextField(controller:p,decoration:const InputDecoration(labelText:'الهاتف'),keyboardType:TextInputType.phone),
      TextField(controller:a,decoration:const InputDecoration(labelText:'العنوان')),
      TextField(controller:notes,decoration:const InputDecoration(labelText:'ملاحظات')),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('حفظ'))]));
    if(ok==true){try{await AppDatabase.instance.saveCustomer(actorUserId:actorId,customerId:row?['id'] as int?,name:n.text,phone:p.text,address:a.text,notes:notes.text);await load();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
    n.dispose();p.dispose();a.dispose();notes.dispose();
  }

  Future<void> deactivateCustomerRow(Map<String,Object?> row) async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('إيقاف الزبون'),
      content:Text('سيتم إيقاف «${row['name']}» عن الاستخدام الجديد، مع الاحتفاظ بكشوف الحساب والفواتير والرصيد التاريخي.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('رجوع')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('تأكيد الإيقاف'))]));
    if(ok==true){try{await AppDatabase.instance.deactivateCustomer(actorUserId:actorId,customerId:row['id'] as int);await load();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
  }

  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('إدارة الزبائن')),floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.person_add),label:const Text('إضافة زبون')),body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(12),children:[
    for(final r in rows) Card(child:ListTile(title:Text(r['name'].toString()),subtitle:Text('الهاتف: ${r['phone']??'—'} • الرصيد: ${r['balance']}'),trailing:Wrap(children:[IconButton(tooltip:'كشف الحساب',icon:const Icon(Icons.receipt_long),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CustomerAccountScreen(user:widget.user,customer:r))).then((_)=>load())),PopupMenuButton<String>(onSelected:(v){if(v=='edit')edit(r);if(v=='off')deactivateCustomerRow(r);},itemBuilder:(_)=>const[PopupMenuItem(value:'edit',child:Text('تعديل')),PopupMenuItem(value:'off',child:Text('حذف / إيقاف'))])]))),
    if(rows.isEmpty) const Padding(padding:EdgeInsets.all(24),child:Text('لا يوجد زبائن مسجلون بعد',textAlign:TextAlign.center)),
  ])));
}
