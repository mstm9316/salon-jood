# قائمة تحقق قبل إطلاق صالون جود

## إعداد وربط
- [ ] إنشاء مشروع Supabase.
- [ ] تنفيذ `supabase/schema.sql` دون أخطاء.
- [ ] إنشاء مستخدم المدير وموظف الاستقبال في Authentication.
- [ ] إضافة سجلاتهما إلى `public.profiles` مع الدور الصحيح.
- [ ] ضبط `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY` في Netlify.
- [ ] ربط مستودع Git ونشر الموقع.

## اختبار يدوي إلزامي
- [ ] طلب حجز في يوم دوام.
- [ ] التأكد أن الحالة تبدأ `pending`.
- [ ] تأكيد الحجز من لوحة الإدارة.
- [ ] محاولة حجز متداخل والتأكد أن قاعدة البيانات ترفضه.
- [ ] تجربة الحجز يوم الجمعة والتأكد من منعه.
- [ ] تجربة المواعيد وفق ساعات الفتح والإغلاق المحفوظة في إعدادات المحل، بما فيها أوقات ما بعد منتصف الليل.
- [ ] إضافة خدمة وتعديل مدتها وسعرها.
- [ ] إضافة دور وانتظار وظهور رقم التذكرة.
- [ ] اختبار صلاحيات المدير والاستقبال كلٌ على حدة.
- [ ] تجربة الواجهة على هاتف Android وiPhone إن أمكن.
- [ ] مراجعة سياسات RLS من Supabase Security Advisor.

## لا تطلق للعامة قبل إكمال
- [ ] تفعيل متابعة آمنة للزبون برمز لمرة واحدة أو رمز متابعة عشوائي.
- [ ] اختبار فعلي للحجوزات المتزامنة من جهازين.
- [ ] وضع خطة نسخ احتياطي وتصدير دوري للبيانات.
- [ ] تحديد آلية استرجاع الحسابات وكلمات المرور.

## تحديث إعدادات المحل
- [ ] تنفيذ `supabase/migration-settings.sql` مرة واحدة على قاعدة البيانات الحالية.
- [ ] نشر نسخة الموقع المحدّثة.
- [ ] من لوحة المدير > إعدادات المحل، ضبط ساعات الدوام ومكان شريط التنقل.
- [ ] اختبار حجز موعد قبل منتصف الليل وموعد بعد منتصف الليل.

## Customer tracking update (2026-11-17)
1. Before deploying the updated frontend, run `supabase/customer-tracking-migration.sql` once in Supabase SQL Editor.
2. Upload the updated project files to the existing GitHub `main` branch (do not delete the repository).
3. Netlify automatically deploys from `main`.
4. New booking and queue requests show an 8-digit tracking code. Customers need both their phone number and that code to view status.
5. Existing requests created before this migration do not have a tracking code and cannot be looked up through the new customer tracking screen.
6. Queue estimates are approximate and refresh while the customer keeps the tracking page open; this does not send SMS/push alerts when the page is closed.
