# مجموعة نصوص إدارة Proxmox VE
مجموعة من نصوص الإدارة المختلفة لبيئة Proxmox VE.

<div align="center">
  <h3>🌍 اختيار اللغة</h3>
  <a href="README.md">🇰🇷 한국어</a> |
  <a href="README_EN.md">🇺🇸 English</a> |
  <a href="README_CN.md">🇨🇳 中文</a> |
  <a href="README_JP.md">🇯🇵 日本語</a> |
  <a href="README_ES.md">🇪🇸 Español</a> |
  <a href="README_FR.md">🇫🇷 Français</a> |
  <a href="README_DE.md">🇩🇪 Deutsch</a> |
  <a href="README_RU.md">🇷🇺 Русский</a> |
  <a href="README_PT.md">🇵🇹 Português</a> |
  <a href="README_AR.md">🇸🇦 العربية</a>
</div>

---

## قائمة البرامج النصية

### 1. أداة إعداد DHCP لجسر VM
سكريبت لتحويل جسر vmbr0 إلى وضع DHCP أو الاستعادة من النسخة الاحتياطية.

**الميزات:**
- **تحويل DHCP**: تحويل vmbr0 من IP ثابت إلى وضع DHCP
- **استعادة النسخة الاحتياطية**: استعادة الإعدادات السابقة من النسخة الاحتياطية
- **النسخ الاحتياطي التلقائي**: نسخ احتياطي تلقائي للإعدادات الحالية قبل التغييرات

**التنفيذ:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. أداة تغيير حجم LVM
سكريبت لدمج local-lvm في local لتحسين مساحة القرص.

**⚠️ مهم: استخدام هذا السكريبت يجعل التراجع صعباً ولن تعمل النسخ الاحتياطية للقطات.**

**الميزات:**
- **دمج LVM**: دمج local-lvm في local
- **تغيير الحجم التلقائي**: توسيع حجم الجذر تلقائياً
- **التحقق من الأمان**: التحقق من حالة النظام قبل العملية

**التنفيذ:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. أداة التحديث التلقائي DDNS DNSZI
سكريبت لتكوين التحديث التلقائي DDNS لخدمة DNSZI.

**الميزات:**
- **التثبيت التلقائي**: تثبيت وتكوين تلقائي لخدمة cron
- **تحديث التمهيد**: تحديث DDNS تلقائي عند تشغيل النظام
- **التحديث المنتظم**: تحديث DDNS تلقائي كل 3 ساعات
- **الإزالة السهلة**: وظيفة الإزالة الكاملة

**التنفيذ:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

### 4. أداة إعداد حجم LVM-Thin ⚠️ **قيد الاختبار - لا تستخدم**
سكريبت لتغيير حجم أدلة LVM و LVM-thin بعد تثبيت Proxmox.

**⚠️ تحذير: هذا السكريبت قيد الاختبار حالياً وقد يدمر نظامك. لا تستخدمه!**

**الميزات:**
- **إعداد الحجم المرن**: إعداد تلقائي/مخصص/قائم على النسبة المئوية
- **تغيير حجم الحجم الجذر**: دعم آمن للتوسيع/التقليص
- **إعادة تكوين LVM-Thin**: إعادة إنشاء حجم البيانات الموجود كـ LVM-thin
- **الإفراط في التوفير**: استخدام فعال للمساحة مع 95% إفراط في التوفير
- **التأكيد خطوة بخطوة**: عملية آمنة مع تأكيد المستخدم

**خيارات إعداد الحجم:**
1. **تلقائي**: الجذر 20GB، البيانات المساحة المتبقية
2. **مخصص**: أحجام محددة من قبل المستخدم
3. **النسبة المئوية**: الجذر 30%، البيانات 70%

**التنفيذ:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_thin_setup.sh)"
```

**🚨 حرج: هذا السكريبت قيد الاختبار وقد يسبب فقدان بيانات النظام. لا تستخدم في بيئات الإنتاج!**

### 5. أداة تخصيص ISO Proxmox
سكريبت لدمج برنامج تشغيل بطاقة الشبكة Realtek R8168 في ISO Proxmox 8.4.

**الميزات:**
- **تحميل ISO**: تحميل تلقائي لـ ISO الرسمي Proxmox 8.4
- **دمج برامج التشغيل**: دمج برنامج تشغيل Realtek R8168 في initrd
- **قائمة التمهيد**: إنشاء قائمة تمهيد مخصصة
- **التعبئة**: إنشاء ملف ISO جديد

**التنفيذ:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```

---

<a href='https://ko-fi.com/R6R71ILZQL' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a> 