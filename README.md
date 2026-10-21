# Mecho Basic

Menü çubuğunda yaşayan küçük bir macOS uygulaması. **F6**'ya basılı tutup konuş, bırakınca söylediklerin yankılı şekilde geri çalınır.

## Kurulum

```bash
./build.sh install
```

Uygulama `~/Applications/Mecho Basic.app` olarak kurulur, başlatılır ve giriş öğesi olarak kaydedilir (menüden kapatılabilir).

İlk açılışta iki izin gerekir:
- **Mikrofon** — kayıt için.
- **Erişilebilirlik** — F6'yı yakalayıp sistemden gizlemek için (Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik).

> Mac klavyesinde üst sıra medya tuşu olarak çalışıyorsa F6 için `fn+F6` kullan ya da Sistem Ayarları → Klavye'den "F1, F2 vb. tuşları standart işlev tuşları olarak kullan"ı aç.
