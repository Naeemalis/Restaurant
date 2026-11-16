import 'package:flutter/material.dart';
import '../data/app_database.dart';

class CatalogManagementScreen extends StatefulWidget {
  final Map<String, Object?> user;
  const CatalogManagementScreen({super.key, required this.user});
  @override
  State<CatalogManagementScreen> createState() => _CatalogManagementScreenState();
}

class _CatalogManagementScreenState extends State<CatalogManagementScreen> {
  List<Map<String, Object?>> products = [];
  List<Map<String, Object?>> categories = [];
  bool loading = true;
  int get actorId => widget.user['id'] as int;

  @override
  void initState() { super.initState(); load(); }

  void message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final result = await Future.wait([
        AppDatabase.instance.catalogProducts(actorUserId: actorId),
        AppDatabase.instance.listCategories(actorUserId: actorId),
      ]);
      if (mounted) setState(() { products = result[0]; categories = result[1]; });
    } catch (e) {
      if (mounted) message(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addCategory([Map<String, Object?>? category]) async {
    final code = TextEditingController(text: category?['code']?.toString() ?? '');
    final ar = TextEditingController();
    final en = TextEditingController();
    final fr = TextEditingController();
    if (category != null) {
      final translations = await (await AppDatabase.instance.database).query('category_translations', where: 'category_id=?', whereArgs: [category['id']]);
      for (final row in translations) {
        if (row['language_code'] == 'ar') ar.text = row['name'].toString();
        if (row['language_code'] == 'en') en.text = row['name'].toString();
        if (row['language_code'] == 'fr') fr.text = row['name'].toString();
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(category == null ? 'إضافة فئة' : 'تعديل الفئة'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: code, decoration: const InputDecoration(labelText: 'رمز الفئة (اختياري)')),
          TextField(controller: ar, decoration: const InputDecoration(labelText: 'اسم الفئة بالعربية')),
          TextField(controller: en, decoration: const InputDecoration(labelText: 'Category name in English')),
          TextField(controller: fr, decoration: const InputDecoration(labelText: 'Nom de catégorie en français')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ الفئة')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await AppDatabase.instance.saveCategory(actorUserId: actorId, categoryId: category?['id'] as int?, code: code.text, names: {'ar': ar.text, 'en': en.text, 'fr': fr.text});
        await load();
        if (mounted) message(category == null ? 'تمت إضافة الفئة' : 'تم تعديل الفئة');
      } catch (e) { if (mounted) message(e.toString()); }
    }
    code.dispose(); ar.dispose(); en.dispose(); fr.dispose();
  }

  Future<void> deactivateCategory(Map<String, Object?> category) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('إيقاف الفئة'),
      content: Text('سيتم إيقاف الفئة «${category['display_name']}» عن الاستخدام الجديد، مع الاحتفاظ بالأصناف والفواتير التاريخية.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد الإيقاف'))],
    ));
    if (ok == true) {
      try { await AppDatabase.instance.deactivateCategory(actorUserId: actorId, categoryId: category['id'] as int); await load(); }
      catch (e) { if (mounted) message(e.toString()); }
    }
  }

  Future<void> editProduct([Map<String, Object?>? product]) async {
    final ar = TextEditingController(text: product?['name_ar']?.toString() ?? '');
    final en = TextEditingController();
    final fr = TextEditingController();
    final code = TextEditingController(text: product?['code']?.toString() ?? '');
    final unit = TextEditingController(text: product?['base_unit']?.toString() ?? 'كيلو');
    final price = TextEditingController(text: product?['sale_price']?.toString() ?? '0');
    int? categoryId = product?['category_id'] as int?;
    String type = product?['product_type']?.toString() ?? 'ingredient';
    bool preparationRequired = product?['preparation_required'] == 1;
    if (product != null) {
      final translations = await (await AppDatabase.instance.database).query('product_translations', where: 'product_id=?', whereArgs: [product['id']]);
      if (!mounted) return;
      for (final row in translations) {
        final language = row['language_code'];
        if (language == 'ar') ar.text = row['name'].toString();
        if (language == 'en') en.text = row['name'].toString();
        if (language == 'fr') fr.text = row['name'].toString();
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(product == null ? 'إضافة صنف' : 'تعديل الصنف'),
          content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, decoration: const InputDecoration(labelText: 'رمز الصنف (اختياري)')),
            TextField(controller: ar, decoration: const InputDecoration(labelText: 'اسم الصنف بالعربية')),
            TextField(controller: en, decoration: const InputDecoration(labelText: 'Product name in English')),
            TextField(controller: fr, decoration: const InputDecoration(labelText: 'Nom du produit en français')),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'الوحدة الأساسية (كيلو، لتر، حبة...)')),
            TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر البيع')), 
            DropdownButtonFormField<int?>(
              value: categoryId,
              decoration: const InputDecoration(labelText: 'الفئة'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('بدون فئة')),
                for (final c in categories) DropdownMenuItem<int?>(value: c['id'] as int, child: Text(c['display_name'].toString())),
              ],
              onChanged: (value) => refresh(() => categoryId = value),
            ),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(labelText: 'نوع الصنف'),
              items: const [
                DropdownMenuItem(value: 'ingredient', child: Text('مادة مخزنية / مكون وصفة')),
                DropdownMenuItem(value: 'sellable', child: Text('منتج قابل للبيع مباشرة')),
                DropdownMenuItem(value: 'both', child: Text('مادة مخزنية وقابلة للبيع')),
              ],
              onChanged: (value) => refresh(() => type = value ?? 'ingredient'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('يتطلب تحضيراً في المطبخ'),
              subtitle: const Text('يُرسل الصنف تلقائياً إلى شاشة المطبخ بعد إصدار الفاتورة.'),
              value: preparationRequired,
              onChanged: (value) => refresh(() => preparationRequired = value),
            ),
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('تُحفظ الكمية بوحدة أساسية واحدة. تحويل وحدات الشراء سيضاف بعد اعتماد قواعد التحويل.', style: TextStyle(fontSize: 12))),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حفظ الصنف')),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await AppDatabase.instance.saveCatalogProduct(
          actorUserId: actorId,
          productId: product?['id'] as int?,
          names: {'ar': ar.text, 'en': en.text, 'fr': fr.text},
          baseUnit: unit.text,
          productType: type,
          categoryId: categoryId,
          code: code.text,
          salePrice: double.tryParse(price.text.replaceAll(',', '.')) ?? 0,
          preparationRequired: preparationRequired,
        );
        await load();
        if (mounted) message('تم حفظ بيانات الصنف');
      } catch (e) { if (mounted) message(e.toString()); }
    }
    ar.dispose(); en.dispose(); fr.dispose(); code.dispose(); unit.dispose(); price.dispose();
  }

  Future<void> deactivateProduct(Map<String, Object?> product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إيقاف الصنف'),
        content: Text('سيتم إيقاف "' + product['display_name'].toString() + '" عن الاستخدام الجديد مع الاحتفاظ بالفواتير والحركات التاريخية.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد الإيقاف')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await AppDatabase.instance.deactivateCatalogProduct(actorUserId: actorId, productId: product['id'] as int);
        await load();
      } catch (e) { if (mounted) message(e.toString()); }
    }
  }

  String typeLabel(Object? type) {
    switch (type) {
      case 'ingredient': return 'مادة مخزنية';
      case 'sellable': return 'بيع مباشر';
      case 'both': return 'مخزني وبيع مباشر';
      default: return type.toString();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة الأصناف والفئات')),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => editProduct(), icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        Card(child: ListTile(
          leading: const Icon(Icons.category),
          title: const Text('الفئات'),
          subtitle: Text('عدد الفئات: ' + categories.length.toString()),
          trailing: IconButton(onPressed: addCategory, icon: const Icon(Icons.add_circle_outline), tooltip: 'إضافة فئة'),
        )),
        for (final c in categories)
          ListTile(dense: true, leading: const Icon(Icons.folder_outlined), title: Text(c['display_name'].toString()), subtitle: Text('رمز: ' + (c['code']?.toString() ?? '—')), trailing: PopupMenuButton<String>(
            onSelected: (v) { if (v == 'edit') addCategory(c); if (v == 'off') deactivateCategory(c); },
            itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('تعديل')), PopupMenuItem(value: 'off', child: Text('حذف / إيقاف'))],
          )),
        const Divider(),
        Text('الأصناف (' + products.length.toString() + ')', style: Theme.of(context).textTheme.titleLarge),
        for (final p in products)
          Card(child: ListTile(
            title: Text(p['display_name'].toString()),
            subtitle: Text((p['category_name'].toString().isEmpty ? 'بدون فئة' : p['category_name'].toString()) + ' • ' + p['base_unit'].toString() + ' • ' + typeLabel(p['product_type'])),
            leading: CircleAvatar(child: Text(p['on_hand'].toString())),
            trailing: PopupMenuButton<String>(
              onSelected: (v) { if (v == 'edit') editProduct(p); if (v == 'off') deactivateProduct(p); },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('تعديل')),
                PopupMenuItem(value: 'off', child: Text('إيقاف')),
              ],
            ),
          )),
        if (products.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد أصناف بعد. أضف الفئات ثم الأصناف.', textAlign: TextAlign.center)),
      ]),
    ),
  );
}
