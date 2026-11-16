import 'package:flutter/material.dart';
import '../data/app_database.dart';

class CashScreen extends StatefulWidget {
  final Map<String,Object?> user;
  const CashScreen({super.key,required this.user});
  @override State<CashScreen> createState()=>_CashScreenState();
}
class _CashScreenState extends State<CashScreen>{
  Map<String,double> summary={'totalIn':0,'totalOut':0,'balance':0};
  List<Map<String,Object?>> transactions=[],suppliers=[],accounts=[],journal=[];
  Map<String,double> journalTotals={'debit':0,'credit':0};
  Map<String,double> pnl={'revenue':0,'cogs':0,'grossProfit':0,'expenses':0,'netProfit':0};
  final expenseAmount=TextEditingController();
  final expenseCategory=TextEditingController();
  final expenseNote=TextEditingController();
  final supplierAmount=TextEditingController();
  final supplierNote=TextEditingController();
  final openingAmount=TextEditingController();
  final openingNote=TextEditingController();
  int? supplierId;
  bool loading=true,busy=false;
  int get actorId=>widget.user['id'] as int;
  String money(Object? v)=>(v as num? ?? 0).toStringAsFixed(2);
  @override void initState(){super.initState();load();}
  void message(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> load()async{
    setState(()=>loading=true);
    try{
      final db=AppDatabase.instance;
      final values=await db.cashSummary(actorUserId:actorId);
      final rows=await db.cashTransactions(actorUserId:actorId);
      final vendors=await db.listSuppliers(actorUserId:actorId);
      final accountRows=await db.accountBalances(actorUserId:actorId);
      final journalRows=await db.recentJournalEntries(actorUserId:actorId);
      final totals=await db.journalTotals(actorUserId:actorId);
      final profit=await db.profitAndLoss(actorUserId:actorId);
      if(!mounted)return;
      setState(() { summary=values; transactions=rows; suppliers=vendors; accounts=accountRows; journal=journalRows; journalTotals=totals; pnl=profit; });
    }catch(e){message(e.toString());}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> saveOpeningBalance()async{
    final amount=double.tryParse(openingAmount.text.trim().replaceAll(',','.'));
    if(amount==null){message('أدخل رصيداً افتتاحياً صحيحاً');return;}
    setState(()=>busy=true);
    try{
      await AppDatabase.instance.recordOpeningCashBalance(actorUserId:actorId,amount:amount,note:openingNote.text);
      openingAmount.clear();openingNote.clear();await load();message('تم تسجيل رصيد بداية الصندوق');
    }catch(e){message(e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> saveExpense()async{
    final amount=double.tryParse(expenseAmount.text.trim().replaceAll(',','.'));
    if(amount==null){message('أدخل مبلغاً صحيحاً');return;}
    setState(()=>busy=true);
    try{
      await AppDatabase.instance.recordCashExpense(actorUserId:actorId,category:expenseCategory.text,amount:amount,note:expenseNote.text);
      expenseAmount.clear();expenseCategory.clear();expenseNote.clear();
      await load();message('تم تسجيل المصروف في الصندوق');
    }catch(e){message(e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> paySupplier()async{
    final amount=double.tryParse(supplierAmount.text.trim().replaceAll(',','.'));
    if(supplierId==null||amount==null){message('حدد المورد وأدخل مبلغاً صحيحاً');return;}
    setState(()=>busy=true);
    try{
      await AppDatabase.instance.paySupplier(actorUserId:actorId,supplierId:supplierId!,amount:amount,note:supplierNote.text);
      supplierAmount.clear();supplierNote.clear();
      await load();message('تم تسجيل دفعة المورد وتحديث الصندوق');
    }catch(e){message(e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override void dispose(){
    expenseAmount.dispose();expenseCategory.dispose();expenseNote.dispose();
    supplierAmount.dispose();supplierNote.dispose();openingAmount.dispose();openingNote.dispose();super.dispose();
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('الصندوق والحركة النقدية'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(12),children:[
      Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('رصيد الصندوق الحالي',style:Theme.of(context).textTheme.titleMedium),
        Text(money(summary['balance']),style:Theme.of(context).textTheme.headlineMedium),
        const Divider(),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('إجمالي المقبوضات: '+money(summary['totalIn'])),Text('إجمالي المدفوعات: '+money(summary['totalOut']))]),
      ]))),
      if(transactions.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('رصيد بداية الصندوق',style:Theme.of(context).textTheme.titleLarge),
        const Text('سجّل النقد الموجود فعلياً عند بدء استخدام النظام. يسمح بإدخاله مرة واحدة فقط.'),
        TextField(controller:openingNote,decoration:const InputDecoration(labelText:'بيان الرصيد الافتتاحي')),
        TextField(controller:openingAmount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المبلغ الموجود في الصندوق')),
        FilledButton(onPressed:busy?null:saveOpeningBalance,child:const Text('تسجيل رصيد البداية')),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('تسجيل مصروف',style:Theme.of(context).textTheme.titleLarge),
        TextField(controller:expenseCategory,decoration:const InputDecoration(labelText:'تصنيف المصروف')),
        TextField(controller:expenseNote,decoration:const InputDecoration(labelText:'البيان / السبب')),
        TextField(controller:expenseAmount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المبلغ')),
        FilledButton(onPressed:busy?null:saveExpense,child:const Text('حفظ المصروف')),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('دفع مستحقات مورد',style:Theme.of(context).textTheme.titleLarge),
        DropdownButtonFormField<int>(value:supplierId,decoration:const InputDecoration(labelText:'المورد'),items:[for(final s in suppliers)DropdownMenuItem(value:s['id'] as int,child:Text(s['name'].toString()))],onChanged:(v)=>setState(()=>supplierId=v)),
        TextField(controller:supplierNote,decoration:const InputDecoration(labelText:'بيان الدفع')),
        TextField(controller:supplierAmount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المبلغ')),
        FilledButton.tonal(onPressed:busy?null:paySupplier,child:const Text('تسجيل دفعة المورد')),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('ملخص الأرباح والخسائر منذ بداية النظام',style:Theme.of(context).textTheme.titleLarge),
        ListTile(dense:true,title:const Text('إيرادات المبيعات'),trailing:Text(money(pnl['revenue']))),
        ListTile(dense:true,title:const Text('تكلفة البضاعة المباعة'),trailing:Text(money(pnl['cogs']))),
        ListTile(dense:true,title:const Text('مجمل الربح'),trailing:Text(money(pnl['grossProfit']))),
        ListTile(dense:true,title:const Text('المصروفات التشغيلية'),trailing:Text(money(pnl['expenses']))),
        const Divider(),
        ListTile(title:const Text('صافي الربح / الخسارة'),trailing:Text(money(pnl['netProfit']),style:Theme.of(context).textTheme.titleLarge)),
        const Text('يعتمد التقرير على القيود المرحلة وتكلفة المخزون المرجحة. العمليات القديمة قبل تفعيل تكلفة المبيعات قد لا تحتوي على تكلفة تاريخية.'),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('المحاسبة المزدوجة وميزان المراجعة',style:Theme.of(context).textTheme.titleLarge),
        Text('إجمالي المدين: '+money(journalTotals['debit'])+' | إجمالي الدائن: '+money(journalTotals['credit'])),
        Text('حالة التوازن: '+(((journalTotals['debit']??0)-(journalTotals['credit']??0)).abs()<0.000001?'متوازن':'يوجد فرق يحتاج مراجعة')),
        const Divider(),
        for(final a in accounts)ListTile(dense:true,title:Text(a['name_ar'].toString()),subtitle:Text(a['code'].toString()+' • مدين '+money(a['debit'])+' • دائن '+money(a['credit'])),trailing:Text(money(a['balance']))),
        const Divider(),
        Text('آخر القيود اليومية',style:Theme.of(context).textTheme.titleMedium),
        for(final j in journal)ListTile(dense:true,title:Text(j['description'].toString()),subtitle:Text(j['entry_no'].toString()+' • '+j['created_at'].toString()),trailing:Text(money(j['debit']))),
      ]))),
      Text('آخر حركات الصندوق',style:Theme.of(context).textTheme.titleLarge),
      if(transactions.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('لا توجد حركات نقدية مسجلة بعد')),
      for(final t in transactions)Card(child:ListTile(
        leading:Icon(t['direction']=='in'?Icons.south_west:Icons.north_east,color:t['direction']=='in'?Colors.green:Colors.red),
        title:Text(t['category'].toString()+' • '+money(t['amount'])),
        subtitle:Text(t['note'].toString()+'\n'+t['created_at'].toString()),
        isThreeLine:true,
        trailing:Text(t['direction']=='in'?'قبض':'صرف'),
      )),
    ]),
  );
}
