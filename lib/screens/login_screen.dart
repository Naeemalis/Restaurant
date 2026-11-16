import 'package:flutter/material.dart';
import '../data/app_database.dart';
import '../app_locale.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool firstRun;
  const LoginScreen({super.key, this.firstRun = false});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final username = TextEditingController(text: 'admin');
  final pin = TextEditingController(text: '123456');
  bool busy = false;
  bool obscurePin = true;

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      final found = await AppDatabase.instance.login(username.text, pin.text);
      if (found == null) throw Exception('اسم المستخدم أو كلمة المرور غير صحيحة');
      if (!mounted) return;
      if (found['must_change_pin'] == 1) {
        final newPin = TextEditingController();
        final confirmPin = TextEditingController();
        final changed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('تغيير كلمة المرور الافتراضية'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('لأمان النظام، يجب تعيين كلمة مرور جديدة قبل المتابعة. استخدم ستة أرقام على الأقل.'),
                const SizedBox(height: 12),
                TextField(controller: newPin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة')),
                const SizedBox(height: 10),
                TextField(controller: confirmPin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  if (newPin.text != confirmPin.text || newPin.text.length < 6 || int.tryParse(newPin.text) == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب أن تتطابق كلمتا المرور وأن تتكون من ستة أرقام على الأقل')));
                    return;
                  }
                  try {
                    await AppDatabase.instance.changeOwnPin(userId: found['id'] as int, newPin: newPin.text);
                    if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                  } catch (e) {
                    if (dialogContext.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
                child: const Text('حفظ كلمة المرور'),
              ),
            ],
          ),
        );
        newPin.dispose();
        confirmPin.dispose();
        if (changed != true || !mounted) return;
        found['must_change_pin'] = 0;
      }
      final language=(found['preferred_language']??'ar').toString();
      appLocale.value=Locale(['ar','en','fr'].contains(language)?language:'ar');
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(user: found)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    username.dispose();
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.restaurant_menu, size: 64, color: Color(0xFF176B55)),
                const SizedBox(height: 12),
                const Text('NaeemSoft Restaurant', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                const Text('تسجيل الدخول', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 18),
                TextField(
                  controller: username,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pin,
                  obscureText: obscurePin,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => busy ? null : submit(),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => obscurePin = !obscurePin),
                      icon: Icon(obscurePin ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: busy ? const CircularProgressIndicator() : const Text('دخول'),
                ),
                const SizedBox(height: 18),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('بيانات المدير الافتراضية', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('اسم المستخدم: admin'),
                        Text('كلمة المرور: 123456'),
                        SizedBox(height: 6),
                        Text('غيّر كلمة المرور بعد الدخول، ولا تشاركها مع الآخرين.', style: TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
