# Keşif Uygulaması — Supabase Kurulum Kılavuzu

## 1. Supabase Projesi Oluştur

1. [supabase.com](https://supabase.com) adresine git → **Start your project** → Ücretsiz hesap oluştur
2. **New Project** tıkla:
   - Name: `kesif-app`
   - Database Password: Güçlü bir şifre seç (kaydet!)
   - Region: **Europe (Frankfurt)** seç (Türkiye'ye en yakın)
3. Proje oluşmasını bekle (~2 dakika)

---

## 2. API Bilgilerini Al

Supabase Dashboard → **Settings** → **API** sekmesi:

```
Project URL:  https://xxxxxxxxxxxxxxxxxxxx.supabase.co
anon/public key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

---

## 3. Flutter Koduna Ekle

`C:\KesifApp\kesif_app\lib\main.dart` dosyasını aç ve şu satırları güncelle:

```dart
const String _supabaseUrl = 'https://xxxx.supabase.co';      // buraya Project URL
const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1N...';     // buraya anon key
```

---

## 4. Auth Ayarları (E-posta Doğrulama)

Supabase Dashboard → **Authentication** → **Settings**:

- **Email Auth**: Etkin (varsayılan)
- **Confirm email**: İstersen kapatabilirsin (test için kolaylaştırır)
- **Site URL / Redirect URLs**: `com.kesif.app://login-callback`

---

## 5. Veritabanı Tabloları (Topluluk & Otomatik Etkinlikler İçin)

Supabase Dashboard → **SQL Editor** → **New query**:

```sql
-- Topluluk keşif noktaları tablosu
CREATE TABLE public.discovery_points (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  category INTEGER NOT NULL DEFAULT 0,
  likes INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS (Row Level Security) aktif et
ALTER TABLE public.discovery_points ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read" ON public.discovery_points FOR SELECT USING (true);
CREATE POLICY "User insert" ON public.discovery_points FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Otomatik Otomatik Etkinlikler Tablosu
CREATE TABLE public.events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT,
  district TEXT,
  city TEXT NOT NULL,
  start_date TIMESTAMPTZ NOT NULL,
  end_date TIMESTAMPTZ,
  location_name TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  source_url TEXT,
  image_url TEXT,
  external_id TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read events" ON public.events FOR SELECT USING (true);
```

**Run** butonuna bas.

---

## 5.1. Realtime (Anlık Senkronizasyon) Yayını Aktif Et

Mesajların ve yeni eklenen keşif noktalarının uygulamada **anlık olarak (sayfayı yenilemeden)** belirmesi için Supabase veritabanında Realtime yayınını aktif etmeniz gerekir:

Supabase Dashboard → **SQL Editor** → **New query**:

```sql
-- Realtime yayın grubuna tabloları ekle
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.discovery_points;
```

**Run** butonuna bas.

---

## 6. Uygulamayı Çalıştır

```powershell
# Terminalde:
cd C:\KesifApp\kesif_app
puro flutter run
```

> İlk çalıştırma için bağlı bir Android/iPhone veya emülatör gerekli.
