import 'package:flutter/material.dart';
import '../data/app_database.dart';
import '../services/document_service.dart';

class StockScreen extends StatefulWidget {
  final Map<String,Object?> user;
  const StockScreen({super.key,required this.user});
  @override State<StockScreen> createState()=>_StockScreenState();
}
class _StockScreenState extends State<StockScreen> with SingleTickerProviderStateMixin{
  List<Map<String,Object?>> balances=[],movements=[];
  bool loading=true,lowOnly=false;
  bool get admin=>widget.user['role']=='admin';
  double get totalValue=>balances.fold(0.0,(sum,p)=>sum+((p['approved_qty'] as num?)?.toDouble()??0)*((p['weighted_average_cost'] as num?)?.toDouble()??0));
  Future<void> load()async{
    setState(()=>loading=true);
    try{
      final db=await AppDatabase.instance.database;
      final costColumn=admin?",COALESCE(b.weighted_average_cost,0) AS weighted_average_cost":"";
      final p=await db.rawQuery("SELECT p.id,p.name_ar,p.base_unit,p.is_sellable,COALESCE(b.on_hand,0) AS on_hand,COALESCE(b.approved_qty,0) AS approved_qty,COALESCE(b.unapproved_qty,0) AS unapproved_qty"+costColumn+" FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id WHERE p.is_active=1 AND p.is_stock_item=1 ORDER BY p.name_ar");
      final m=await db.rawQuery("SELECT sm.id,sm.movement_type,sm.quantity_delta,sm.source_type,sm.source_id,sm.note,sm.occurred_at,p.name_ar,p.base_unit,u.display_name FROM stock_movements sm JOIN products p ON p.id=sm.product_id LEFT JOIN users u ON u.id=sm.actor_user_id ORDER BY sm.id DESC LIMIT 300");
      if(mounted)setState((){balances=p;movements=m;});
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر تحميل المخزون: $e')));}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>DefaultTabController(length:2,child:Scaffold(
    appBar:AppBar(title:const Text('إدارة المخزون'),actions:[if(admin)IconButton(onPressed:()async{try{await DocumentService.printStockReport();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذرت الطباعة: $e')));}},icon:const Icon(Icons.print),tooltip:'طباعة التقرير'),if(admin)IconButton(onPressed:()async{try{await DocumentService.shareStockReport();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذرت مشاركة التقرير: $e')));}},icon:const Icon(Icons.share),tooltip:'مشاركة PDF'),IconButton(onPressed:load,icon:const Icon(Icons.refresh),tooltip:'تحديث')],bottom:const TabBar(tabs:[Tab(text:'الأرصدة'),Tab(text:'حركة المخزون')])),
    body:loading?const Center(child:CircularProgressIndicator()):TabBarView(children:[
      Column(children:[
        Card(margin:const EdgeInsets.all(8),child:Padding(padding:const EdgeInsets.all(10),child:Row(children:[
          if(admin)Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('قيمة المخزون المعتمدة'),Text(totalValue.toStringAsFixed(2),style:Theme.of(context).textTheme.titleLarge)])),
          Column(crossAxisAlignment:CrossAxisAlignment.end,children:[Text('${balances.length} صنف'),Text('${balances.where((p)=>(p['approved_qty'] as num).toDouble()<=0).length} نافد')]),
        ]))),
        SwitchListTile(title:const Text('عرض الأصناف النافدة فقط'),value:lowOnly,onChanged:(v)=>setState(()=>lowOnly=v),dense:true),
        Expanded(child:balances.where((p)=>!lowOnly||(p['approved_qty'] as num).toDouble()<=0).isEmpty?const Center(child:Text('لا توجد أصناف مطابقة')):ListView.builder(itemCount:balances.where((p)=>!lowOnly||(p['approved_qty'] as num).toDouble()<=0).length,itemBuilder:(c,i){
          final p=balances.where((p)=>!lowOnly||(p['approved_qty'] as num).toDouble()<=0).toList()[i];
          final qty=(p['approved_qty'] as num).toDouble();
          return Card(margin:const EdgeInsets.symmetric(horizontal:8,vertical:3),child:ListTile(
            title:Text(p['name_ar'].toString()),
            subtitle:Text('الوحدة: ${p['base_unit']} | غير معتمد: ${p['unapproved_qty']}' + (admin ? ' | تكلفة الوحدة: ${((p['weighted_average_cost'] as num).toDouble()).toStringAsFixed(2)}' : '')),
            isThreeLine:true,
            trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[
              Text(qty.toString(),style:TextStyle(fontWeight:FontWeight.bold,color:qty<=0?Theme.of(context).colorScheme.error:null)),
              if(admin)Text('القيمة ${(qty*((p['weighted_average_cost'] as num).toDouble())).toStringAsFixed(2)}',style:const TextStyle(fontSize:11)),
            ]),
          ));
        })),
      ]),
      movements.isEmpty?const Center(child:Text('لا توجد حركات مخزون مسجلة')):ListView.builder(itemCount:movements.length,itemBuilder:(c,i){
        final m=movements[i];final delta=(m['quantity_delta'] as num).toDouble();
        return ListTile(
          leading:Icon(delta<0?Icons.arrow_downward:Icons.arrow_upward,color:delta<0?Colors.red:Colors.green),
          title:Text('${m['name_ar']}  |  ${delta>0?'+':''}${delta} ${m['base_unit']}'),
          subtitle:Text('${m['movement_type']} • ${m['source_type']} #${m['source_id']??'-'}\n${m['display_name']??'غير محدد'} • ${m['occurred_at']}\n${m['note']??''}'),
          isThreeLine:true,
        );
      }),
    ]),
  ));
}
