import 'package:flutter/material.dart';
import '../data/app_database.dart';

class SupplierManagementScreen extends StatefulWidget {
  final Map<String, Object?> user;
  const SupplierManagementScreen({super.key, required this.user});
  @override
  State<SupplierManagementScreen> createState() => _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen> {
  List<Map<String, Object?>> suppliers = [];
  bool loading = true;
  int get actorId => widget.user['id'] as int;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final rows = await AppDatabase.instance.listSuppliers(actorUserId: actorId);
      if (mounted) setState(() => suppliers = rows);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> editSupplier([Map<String, Object?>? supplier]) async {
    final name = TextEditingController(text: supplier?['name']?.toString() ?? '');
    final phone = TextEditingController(text: supplier?['phone']?.toString() ?? '');
    final address = TextEditingController(text: supplier?['address']?.toString() ?? '');
    final notes = TextEditingController(text: supplier?['notes']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(supplier == null ? 'إضافة مورد' : 'تعديل بيانات المورد'),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المورد *')),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
          TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'ملاحظات')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await AppDatabase.instance.saveSupplier(
          actorUserId: actorId,
          supplierId: supplier?['id'] as int?,
          name: name.text,
          phone: phone.text,
          address: address.text,
          notes: notes.text,
        );
        await load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    name.dispose(); phone.dispose(); address.dispose(); notes.dispose();
  }

  Future<void> deactivateSupplierEntry(Map<String, Object?> supplier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إيقاف المورد'),
        content: Text('سيتم إيقاف المورد «${supplier['name']}» عن الاستخدام الجديد، مع الاحتفاظ بسجلاته التاريخية.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد الإيقاف')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await AppDatabase.instance.deactivateSupplier(actorUserId: actorId, supplierId: supplier['id'] as int);
        await load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة الموردين')),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => editSupplier(), icon: const Icon(Icons.person_add_alt_1), label: const Text('إضافة مورد')),
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        Card(child: ListTile(leading: const Icon(Icons.local_shipping_outlined), title: const Text('الموردون النشطون'), subtitle: Text('العدد: ${suppliers.length}'))),
        for (final s in suppliers)
          Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.storefront)),
            title: Text(s['name'].toString()),
            subtitle: Text([s['phone'], s['address']].where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ').isEmpty ? 'لا توجد بيانات اتصال' : [s['phone'], s['address']].where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ')),
            trailing: PopupMenuButton<String>(
              onSelected: (v) { if (v == 'edit') editSupplier(s); if (v == 'off') deactivateSupplierEntry(s); },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('تعديل')),
                PopupMenuItem(value: 'off', child: Text('إيقاف')),
              ],
            ),
          )),
        if (suppliers.isEmpty) const Padding(padding: EdgeInsets.all(28), child: Text('لا يوجد موردون بعد. أضف الموردين قبل إنشاء فواتير التوريد.', textAlign: TextAlign.center)),
      ]),
    ),
  );
}
