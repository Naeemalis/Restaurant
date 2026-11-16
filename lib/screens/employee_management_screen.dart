import 'package:flutter/material.dart';
import '../data/app_database.dart';

class EmployeeManagementScreen extends StatefulWidget {
  final Map<String, Object?> user;
  const EmployeeManagementScreen({super.key, required this.user});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  List<Map<String, Object?>> employees = [];
  bool loading = true;
  int get actorId => widget.user['id'] as int;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final result = await AppDatabase.instance.listUsers(actorUserId: actorId);
      if (mounted) setState(() => employees = result);
    } catch (e) {
      if (mounted) _message(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _roleName(Object? role) {
    final lang=(widget.user['preferred_language']??'ar').toString();
    switch (role) {
      case 'admin': return lang=='en'?'Administrator':lang=='fr'?'Administrateur':'مدير';
      case 'cashier': return lang=='en'?'Cashier':lang=='fr'?'Caissier':'كاشير';
      case 'storekeeper': return lang=='en'?'Storekeeper':lang=='fr'?'Magasinier':'أمين مخزن';
      case 'kitchen': return lang=='en'?'Kitchen Manager':lang=='fr'?'Responsable cuisine':'مسؤول المطبخ';
      default: return role.toString();
    }
  }

  Future<void> addEmployee() async {
    final name = TextEditingController();
    final username = TextEditingController();
    final pin = TextEditingController();
    String role = 'cashier';
    String language = 'ar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('إضافة موظف'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الموظف')),
              TextField(controller: username, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
              TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN - ستة أرقام على الأقل')),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('مدير')),
                  DropdownMenuItem(value: 'cashier', child: Text('كاشير')),
                  DropdownMenuItem(value: 'storekeeper', child: Text('أمين مخزن')),
                  DropdownMenuItem(value: 'kitchen', child: Text((widget.user['preferred_language']=='en')?'Kitchen Manager':(widget.user['preferred_language']=='fr')?'Responsable cuisine':'مسؤول المطبخ')),
                ],
                onChanged: (value) => refresh(() => role = value ?? 'cashier'),
              ),
              DropdownButtonFormField<String>(
                value: language,
                decoration: const InputDecoration(labelText: 'لغة الحساب'),
                items: const [
                  DropdownMenuItem(value: 'ar', child: Text('العربية')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'fr', child: Text('Français')),
                ],
                onChanged: (value) => refresh(() => language = value ?? 'ar'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('إنشاء الحساب')),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await AppDatabase.instance.createEmployee(
          actorUserId: actorId,
          username: username.text,
          name: name.text,
          pin: pin.text,
          role: role,
          language: language,
        );
        await load();
        if (mounted) _message('تم إنشاء حساب الموظف');
      } catch (e) {
        if (mounted) _message(e.toString());
      }
    }
    name.dispose();
    username.dispose();
    pin.dispose();
  }

  Future<void> toggleActive(Map<String, Object?> employee, bool active) async {
    try {
      await AppDatabase.instance.setEmployeeActive(
        actorUserId: actorId,
        targetUserId: employee['id'] as int,
        active: active,
      );
      await load();
    } catch (e) {
      if (mounted) _message(e.toString());
    }
  }

  Future<void> resetPin(Map<String, Object?> employee) async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إعادة PIN - ${employee['display_name']}'),
        content: TextField(
          controller: pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN جديد - ستة أرقام على الأقل'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حفظ PIN')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await AppDatabase.instance.resetEmployeePin(
          actorUserId: actorId,
          targetUserId: employee['id'] as int,
          newPin: pin.text,
        );
        if (mounted) _message('تم تحديث PIN الموظف');
      } catch (e) {
        if (mounted) _message(e.toString());
      }
    }
    pin.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة الموظفين')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: addEmployee,
      icon: const Icon(Icons.person_add),
      label: const Text('إضافة موظف'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                const Card(child: ListTile(
                  leading: Icon(Icons.security),
                  title: Text('إدارة الحسابات والصلاحيات'),
                  subtitle: Text('لا يتم عرض PIN أو بيانات التحقق. تعطيل الحساب لا يحذف سجلاته.'),
                )),
                for (final employee in employees)
                  Card(
                    child: ListTile(
                      title: Text(employee['display_name'].toString()),
                      subtitle: Text(
                        '${employee['username']} • ${_roleName(employee['role'])} • ${employee['preferred_language']}',
                      ),
                      leading: CircleAvatar(child: Text(employee['display_name'].toString().isEmpty ? '?' : employee['display_name'].toString().substring(0, 1))),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'pin') resetPin(employee);
                          if (action == 'active') toggleActive(employee, (employee['is_active'] as int) != 1);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'pin', child: Text('إعادة تعيين PIN')),
                          PopupMenuItem(
                            value: 'active',
                            child: Text((employee['is_active'] as int) == 1 ? 'تعطيل الحساب' : 'تفعيل الحساب'),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  ),
                if (employees.isEmpty) const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('لا توجد حسابات موظفين. أضف أول موظف من الزر أدناه.', textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
  );
}
