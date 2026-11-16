import 'package:flutter/material.dart';
import '../data/app_database.dart';

class RecipeManagementScreen extends StatefulWidget {
  final Map<String,Object?> user;
  const RecipeManagementScreen({super.key,required this.user});
  @override State<RecipeManagementScreen> createState()=>_RecipeManagementScreenState();
}

class _RecipeManagementScreenState extends State<RecipeManagementScreen>{
  List<Map<String,Object?>> meals=[],ingredients=[];
  bool loading=true, savingMeal=false;
  int get actorId=>widget.user['id'] as int;

  @override void initState(){super.initState();load();}
  void message(String value)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));

  Future<void> load()async{
    if(mounted)setState(()=>loading=true);
    try{
      final db=AppDatabase.instance;
      final m=await db.recipeProducts(actorUserId:actorId);
      final i=await db.ingredientProducts(actorUserId:actorId);
      if(mounted)setState((){meals=m;ingredients=i;});
    }catch(e){if(mounted)message(e.toString());}
    finally{if(mounted)setState(()=>loading=false);}
  }

  Future<void> addMeal()async{
    final name=TextEditingController();
    final price=TextEditingController(text:'0');
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('إضافة وجبة جديدة'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name, autofocus:true, decoration:const InputDecoration(labelText:'اسم الوجبة')),
        TextField(controller:price,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'سعر البيع')),
        const Padding(padding:EdgeInsets.only(top:8),child:Text('ستظهر الوجبة في القائمة السفلية، وبعد حفظها يمكنك تحديد مكونات الوصفة من المخزون.',style:TextStyle(fontSize:12))),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('إضافة الوجبة')),
      ],
    ));
    if(ok==true){
      final n=name.text.trim();
      final p=double.tryParse(price.text.trim().replaceAll(',','.'));
      if(n.isEmpty||p==null||!p.isFinite||p<0){message('أدخل اسم الوجبة وسعراً صحيحاً');}
      else{
        setState(()=>savingMeal=true);
        try{
          final id=await AppDatabase.instance.saveCatalogProduct(
            actorUserId:actorId,
            names:{'ar':n},
            baseUnit:'وجبة',
            productType:'sellable',
            categoryId:null,
            salePrice:p,
            preparationRequired:true,
          );
          await load();
          final created=meals.where((m)=>m['id']==id).toList();
          if(mounted){
            message('تمت إضافة الوجبة إلى القائمة السفلية. أضف الآن مكوناتها وكمياتها.');
            if(created.isNotEmpty)await editRecipe(created.first);
          }
        }catch(e){if(mounted)message(e.toString());}
        finally{if(mounted)setState(()=>savingMeal=false);}
      }
    }
    name.dispose();price.dispose();
  }

  Future<void> editRecipe(Map<String,Object?> meal)async{
    final mealId=meal['id'] as int;
    final existing=await AppDatabase.instance.recipeLines(actorUserId:actorId,productId:mealId);
    if(!mounted)return;
    final lines=<Map<String,Object?>>[for(final l in existing){
      'productId':l['ingredient_product_id'],
      'name':l['name_ar'],
      'unit':l['unit_snapshot'],
      'quantity':(l['quantity_per_meal'] as num).toDouble(),
    }];
    int? selectedIngredientId;
    final qty=TextEditingController();
    await showDialog<void>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(dialogContext,setDialogState)=>AlertDialog(
      title:Text('وصفة وجبة: '+meal['name_ar'].toString()),
      content:SizedBox(width:460,height:390,child:Column(children:[
        DropdownButtonFormField<int>(
          value:selectedIngredientId,
          decoration:const InputDecoration(labelText:'اختر مكوناً من المخزون'),
          items:[for(final p in ingredients)DropdownMenuItem(value:p['id'] as int,child:Text(p['name_ar'].toString()+' ('+p['base_unit'].toString()+')'))],
          onChanged:(v)=>setDialogState(()=>selectedIngredientId=v),
        ),
        Row(children:[
          Expanded(child:TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الكمية اللازمة لوجبة واحدة'))),
          IconButton(onPressed:(){
            if(selectedIngredientId==null){message('اختر المكون');return;}
            final amount=double.tryParse(qty.text.replaceAll(',','.'));
            if(amount==null||!amount.isFinite||amount<=0){message('أدخل كمية صحيحة أكبر من صفر');return;}
            if(lines.any((l)=>l['productId']==selectedIngredientId)){message('المكون مضاف بالفعل');return;}
            final p=ingredients.firstWhere((x)=>x['id']==selectedIngredientId);
            setDialogState(()=>lines.add({'productId':selectedIngredientId,'name':p['name_ar'],'unit':p['base_unit'],'quantity':amount}));
            qty.clear();
          },icon:const Icon(Icons.add_circle),tooltip:'إضافة المكون'),
        ]),
        const Divider(),
        Expanded(child:lines.isEmpty?const Center(child:Text('لم تتم إضافة مكونات لهذه الوجبة بعد')):ListView.builder(itemCount:lines.length,itemBuilder:(c,index){
          final l=lines[index];
          return ListTile(
            dense:true,
            title:Text(l['name'].toString()),
            subtitle:Text(l['quantity'].toString()+' '+l['unit'].toString()+' لكل وجبة'),
            trailing:IconButton(onPressed:()=>setDialogState(()=>lines.removeAt(index)),icon:const Icon(Icons.delete_outline)),
          );
        })),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('إلغاء')),
        FilledButton(onPressed:()async{
          if(lines.isEmpty){message('أضف مكوناً واحداً على الأقل');return;}
          try{
            await AppDatabase.instance.saveRecipe(actorUserId:actorId,productId:mealId,lines:[for(final l in lines){'productId':l['productId'],'quantity':l['quantity']}]);
            if(dialogContext.mounted)Navigator.pop(dialogContext);
            if(mounted)message('تم حفظ وصفة الوجبة وكميات مكوناتها. ستُخصم تلقائياً عند إصدار فاتورة الوجبة.');
          }catch(e){if(mounted)message(e.toString());}
        },child:const Text('حفظ الوصفة')),
      ],
    )));
    qty.dispose();
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('مركز إدارة الوجبات'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
    body:loading?const Center(child:CircularProgressIndicator()):Column(children:[
      Expanded(flex:5,child:Card(margin:const EdgeInsets.fromLTRB(10,8,10,5),child:Column(children:[
        Padding(padding:const EdgeInsets.all(10),child:Row(children:[
          const Icon(Icons.inventory_2_outlined),
          const SizedBox(width:8),
          Text('مكونات المخزون للوصفات',style:Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          Text(ingredients.length.toString()+' صنف'),
        ])),
        const Divider(height:1),
        Expanded(child:ingredients.isEmpty?const Center(child:Text('لا توجد مواد مخزنية. أضف المواد أولاً من إدارة الأصناف ثم سجّل توريدها.')):ListView.builder(itemCount:ingredients.length,itemBuilder:(c,i){
          final p=ingredients[i];
          return ListTile(
            dense:true,
            title:Text(p['name_ar'].toString()),
            subtitle:Text('الوحدة الأساسية: '+p['base_unit'].toString()),
            trailing:Text('المتاح: '+p['available_qty'].toString(),style:Theme.of(context).textTheme.titleMedium),
          );
        })),
      ]))),
      Expanded(flex:5,child:Card(margin:const EdgeInsets.fromLTRB(10,5,10,10),child:Column(children:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),child:Row(children:[
          const Icon(Icons.restaurant_menu),
          const SizedBox(width:8),
          Text('قائمة الوجبات',style:Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          Text(meals.length.toString()+' وجبة'),
          const SizedBox(width:8),
          FilledButton.tonalIcon(onPressed:savingMeal?null:addMeal,icon:const Icon(Icons.add),label:const Text('إضافة وجبة')),
        ])),
        const Divider(height:1),
        Expanded(child:meals.isEmpty?const Center(child:Text('لا توجد وجبات بعد. اضغط «إضافة وجبة» لإضافتها هنا مباشرة.')):GridView.builder(
          padding:const EdgeInsets.all(8),
          gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,childAspectRatio:2.4,crossAxisSpacing:8,mainAxisSpacing:8),
          itemCount:meals.length,
          itemBuilder:(c,i){
            final meal=meals[i];
            return Card(child:InkWell(onTap:()=>editRecipe(meal),child:Padding(padding:const EdgeInsets.all(8),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              Text(meal['name_ar'].toString(),textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w600)),
              const SizedBox(height:4),
              const Text('اضغط لإدارة الوصفة',style:TextStyle(fontSize:11)),
            ]))));
          },
        )),
      ]))),
    ]),
  );
}
