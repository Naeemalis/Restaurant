import 'package:flutter/material.dart';
import '../data/app_database.dart';
import '../app_locale.dart';
import 'login_screen.dart';
import 'employee_management_screen.dart';
import 'catalog_management_screen.dart';
import 'supplier_management_screen.dart';
import 'customer_management_screen.dart';
import 'cashier_screen.dart';
import 'purchase_screen.dart';
import 'recipe_management_screen.dart';
import 'kitchen_screen.dart';
import 'cash_screen.dart';
import 'stock_screen.dart';
import 'inventory_management_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, Object?> user;
  const HomeScreen({super.key, required this.user});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, Object?>> items = [];
  bool get admin => widget.user['role'] == 'admin';
  bool get storekeeper => widget.user['role'] == 'storekeeper';
  bool get kitchenUser => widget.user['role'] == 'kitchen';

  @override
  void initState() { super.initState(); load(); }
  Future<void> setLanguage(String language) async {
    await (await AppDatabase.instance.database).update('users',{'preferred_language':language},where:'id=?',whereArgs:[widget.user['id']]);
    widget.user['preferred_language']=language;
    appLocale.value=Locale(language);
    if(mounted)setState((){});
  }
  Future<void> load() async {
    final result = await AppDatabase.instance.products();
    if (mounted) setState(() => items = result);
  }

  Future<void> configureShop() async {
    final profile = await AppDatabase.instance.businessProfile();
    final name = TextEditingController(text: (profile['shop_name'] ?? '').toString());
    final phone = TextEditingController(text: (profile['phone'] ?? '').toString());
    final address = TextEditingController(text: (profile['address'] ?? '').toString());
    try {
      final saved = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('بيانات المحل على الفواتير'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller:name, decoration:const InputDecoration(labelText:'اسم المحل *')),
          TextField(controller:phone, keyboardType:TextInputType.phone, decoration:const InputDecoration(labelText:'رقم الهاتف')),
          TextField(controller:address, decoration:const InputDecoration(labelText:'العنوان')),
        ])),
        actions: [
          TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('حفظ')),
        ],
      ));
      if(saved==true) {
        await AppDatabase.instance.saveBusinessProfile(shopName:name.text,phone:phone.text,address:address.text);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم حفظ بيانات المحل، وستظهر في الفواتير الجديدة والمستندات المطبوعة.')));
      }
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
    } finally { name.dispose(); phone.dispose(); address.dispose(); }
  }

  Future<void> addProduct() async {
    final n = TextEditingController();
    final u = TextEditingController(text: 'حبة');
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('إضافة مادة'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: n, decoration: const InputDecoration(labelText: 'اسم المادة')), TextField(controller: u, decoration: const InputDecoration(labelText: 'الوحدة'))]), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ'))]));
    if (ok == true && n.text.trim().isNotEmpty && u.text.trim().isNotEmpty) { await AppDatabase.instance.addProduct(n.text, u.text, actorUserId: widget.user['id'] as int); await load(); }
    n.dispose(); u.dispose();
  }

  Future<void> stocktake() async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد مواد للجرد')));
      return;
    }
    final fields = <int, TextEditingController>{
      for (final product in items) product['id'] as int: TextEditingController(),
    };
    final note = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('الجرد الفعلي'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('أدخل الكميات الفعلية المعتمدة القابلة للصرف فقط. استبعد التوريدات غير المعتمدة والكميات المحجوزة. لن يتغير المخزون عند الإرسال.'),
                for (final product in items)
                  Row(children: [
                    Expanded(child: Text('${product['name_ar']} (${product['base_unit']})')),
                    SizedBox(width: 100, child: TextField(
                      controller: fields[product['id'] as int],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'الفعلي'),
                    )),
                    Text('المعتمد: ${product['approved_qty']}'),
                  ]),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إرسال للمدير')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final counted = <int, double>{};
      for (final entry in fields.entries) {
        final raw = entry.value.text.trim();
        if (raw.isEmpty) continue;
        final qty = double.tryParse(raw.replaceAll(',', '.'));
        if (qty == null || !qty.isFinite || qty < 0) throw ArgumentError('أدخل كميات صحيحة غير سالبة');
        counted[entry.key] = qty;
      }
      await AppDatabase.instance.submitStocktake(
        actorUserId: widget.user['id'] as int,
        counted: counted,
        note: note.text,
      );
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الجرد للمدير دون تغيير الرصيد')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      for (final field in fields.values) { field.dispose(); }
      note.dispose();
    }
  }

  Future<void> reviewStocktake() async {
    final db = await AppDatabase.instance.database;
    final pending = await db.rawQuery("SELECT * FROM stocktakes WHERE status='submitted' ORDER BY id");
    if (pending.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد عمليات جرد بانتظار الاعتماد')));
      return;
    }
    final id = pending.first['id'] as int;
    final lines = await db.rawQuery(
      'SELECT l.*,p.name_ar,p.base_unit FROM stocktake_lines l JOIN products p ON p.id=l.product_id WHERE l.stocktake_id=?',
      [id],
    );
    if (!mounted) return;
    final approve = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('مراجعة الجرد رقم $id'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            const Text('سيمنع النظام الاعتماد إذا حدثت حركة على أي صنف بعد أخذ لقطة الجرد.'),
            for (final line in lines)
              ListTile(
                title: Text(line['name_ar'].toString()),
                subtitle: Text('المسجل: ${line['system_qty']} | الفعلي: ${line['counted_qty']} ${line['base_unit']}'),
                trailing: Text('الفرق: ${line['difference_qty']}'),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رفض')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('اعتماد')),
        ],
      ),
    );
    if (approve == null) return;
    try {
      await AppDatabase.instance.reviewStocktake(
        stocktakeId: id,
        actorUserId: widget.user['id'] as int,
        approve: approve,
      );
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'تم اعتماد الجرد' : 'تم رفض الجرد')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('NaeemSoft Restaurant'), actions: [PopupMenuButton<String>(tooltip:'Language / Langue / اللغة',initialValue:(widget.user['preferred_language']??'ar').toString(),onSelected:setLanguage,itemBuilder:(_)=>const [PopupMenuItem(value:'ar',child:Text('العربية')),PopupMenuItem(value:'en',child:Text('English')),PopupMenuItem(value:'fr',child:Text('Français'))],icon:const Icon(Icons.language)),IconButton(onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false), icon: const Icon(Icons.logout))]),
    body: RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(title: Text('مرحباً، ' + widget.user['display_name'].toString()), subtitle: Text('الدور: ' + widget.user['role'].toString()))),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (admin || widget.user['role'] == 'cashier') FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CashierScreen(user: widget.user))).then((_) => load()), icon: const Icon(Icons.point_of_sale), label: const Text('كاشير المبيعات')),
        if (admin) FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerManagementScreen(user: widget.user))), icon: const Icon(Icons.people_alt_outlined), label: const Text('إدارة الزبائن')), 
        if (admin) FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CatalogManagementScreen(user: widget.user))).then((_) => load()), icon: const Icon(Icons.inventory_2), label: const Text('إدارة الأصناف')),
        if (admin) FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierManagementScreen(user: widget.user))).then((_) => load()), icon: const Icon(Icons.local_shipping_outlined), label: const Text('إدارة الموردين')),
        if (admin || storekeeper) FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseScreen(user: widget.user))).then((_) => load()), icon: const Icon(Icons.add_shopping_cart), label: const Text('كاشير التوريد')),
        if (admin || storekeeper) FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockScreen(user: widget.user))), icon: const Icon(Icons.inventory), label: const Text('إدارة المخزون')),
        if (admin || storekeeper) FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryManagementScreen(user: widget.user))).then((_) => load()), icon: const Icon(Icons.warehouse_outlined), label: const Text('مهام أمين المخزن')),
        if (admin) FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeManagementScreen(user: widget.user))), icon: const Icon(Icons.restaurant_menu), label: const Text('إدارة الوجبات والوصفات')),
        if (admin || storekeeper || widget.user['role'] == 'cashier' || kitchenUser) FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => KitchenScreen(user: widget.user))), icon: const Icon(Icons.soup_kitchen), label: const Text('شاشة المطبخ')),
        if (admin) FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CashScreen(user: widget.user))).then((_) => load()), icon: const Icon(Icons.account_balance_wallet), label: const Text('الصندوق والحسابات النقدية')),
        if (admin) FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeeManagementScreen(user: widget.user))), icon: const Icon(Icons.manage_accounts), label: const Text('إدارة الموظفين')),
        if (admin) OutlinedButton.icon(onPressed: configureShop, icon: const Icon(Icons.store), label: const Text('بيانات المحل والفواتير')),
        if (admin || storekeeper) OutlinedButton.icon(onPressed: stocktake, icon: const Icon(Icons.fact_check), label: const Text('جرد فعلي')),
        if (admin) FilledButton.tonalIcon(onPressed: reviewStocktake, icon: const Icon(Icons.verified), label: const Text('مراجعة الجرد')),
      ]),
      if (admin || storekeeper) const SizedBox(height: 16),
      if (admin || storekeeper) Text('المخزون الموحد', style: Theme.of(context).textTheme.titleLarge),
      if (admin || storekeeper) for (final p in items) Card(child: ListTile(title: Text(p['name_ar'].toString()), subtitle: Text('الوحدة: ' + p['base_unit'].toString()), trailing: Text(p['on_hand'].toString()))),
      if ((admin || storekeeper) && items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('ابدأ بإضافة المواد من حساب المدير')),
      const Padding(padding: EdgeInsets.all(12), child: Text('نسخة أولية قيد البناء والاختبار؛ لا تستخدم بعد لإدارة الحسابات الفعلية.')),
    ])),
  );
}
