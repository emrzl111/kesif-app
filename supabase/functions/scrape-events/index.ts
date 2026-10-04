// Supabase Edge Function: scrape-events
// Deno runtime — Kültür Portalı + büyükşehir belediyeleri
// Deploy: supabase functions deploy scrape-events
// Cron:   supabase functions schedule --cron "0 3 * * *" scrape-events

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─── Supabase ─────────────────────────────────────────────
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// ─── Tip ─────────────────────────────────────────────────
interface EventInsert {
  external_id: string;
  title: string;
  description?: string | null;
  category?: string | null;
  city: string;
  district?: string | null;
  location_name?: string | null;
  start_date: string;
  end_date?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  image_url?: string | null;
  source_url?: string | null;
  price?: number | null;
}

// ─── Şehir koordinatları ─────────────────────────────────
const CITY_COORDS: Record<string, { lat: number; lon: number }> = {
  "İstanbul":  { lat: 41.0082, lon: 28.9784 },
  "Ankara":    { lat: 39.9334, lon: 32.8597 },
  "İzmir":     { lat: 38.4237, lon: 27.1428 },
  "Bursa":     { lat: 40.1885, lon: 29.0610 },
  "Antalya":   { lat: 36.8969, lon: 30.7133 },
  "Adana":     { lat: 37.0017, lon: 35.3289 },
  "Konya":     { lat: 37.8746, lon: 32.4932 },
  "Gaziantep": { lat: 37.0662, lon: 37.3833 },
  "Kayseri":   { lat: 38.7312, lon: 35.4787 },
  "Eskişehir": { lat: 39.7767, lon: 30.5206 },
  "Trabzon":   { lat: 41.0027, lon: 39.7168 },
  "Mersin":    { lat: 36.8000, lon: 34.6333 },
  "Samsun":    { lat: 41.2928, lon: 36.3313 },
  "Diyarbakır":{ lat: 37.9144, lon: 40.2306 },
  "Şanlıurfa": { lat: 37.1591, lon: 38.7969 },
  "Muğla":     { lat: 37.2153, lon: 28.3636 },
  "Edirne":    { lat: 41.6771, lon: 26.5557 },
  "Denizli":   { lat: 37.7765, lon: 29.0864 },
  "Erzurum":   { lat: 39.9043, lon: 41.2679 },
  "Malatya":   { lat: 38.3552, lon: 38.3095 },
};

// ─── Kültür Portalı şehir slug'ları ───────────────────────
const KULTUR_SLUGS: Record<string, string> = {
  "İstanbul":  "istanbul",
  "Ankara":    "ankara",
  "İzmir":     "izmir",
  "Bursa":     "bursa",
  "Antalya":   "antalya",
  "Adana":     "adana",
  "Konya":     "konya",
  "Gaziantep": "gaziantep",
  "Kayseri":   "kayseri",
  "Eskişehir": "eskisehir",
  "Trabzon":   "trabzon",
  "Mersin":    "mersin",
  "Samsun":    "samsun",
  "Diyarbakır":"diyarbakir",
  "Şanlıurfa": "sanliurfa",
  "Muğla":     "mugla",
  "Edirne":    "edirne",
  "Denizli":   "denizli",
  "Erzurum":   "erzurum",
  "Malatya":   "malatya",
};

// ─── Kategori eşleştirme ──────────────────────────────────
function mapCategory(raw: string): string {
  const r = raw.toLowerCase();
  if (r.includes("konser") || r.includes("müzik") || r.includes("music")) return "konser";
  if (r.includes("tiyatro") || r.includes("sahne")) return "tiyatro";
  if (r.includes("sergi") || r.includes("resim") || r.includes("sanat")) return "sergi";
  if (r.includes("sinema") || r.includes("film")) return "sinema";
  if (r.includes("festival")) return "festival";
  if (r.includes("atölye") || r.includes("workshop") || r.includes("kurs")) return "atolye";
  if (r.includes("söyleşi") || r.includes("panel") || r.includes("konferans")) return "soylesi";
  if (r.includes("dans") || r.includes("bale")) return "dans";
  if (r.includes("çocuk") || r.includes("cocuk")) return "cocuk";
  if (r.includes("spor") || r.includes("maraton")) return "spor";
  return "etkinlik";
}

// ─── Tarih ayrıştırma ─────────────────────────────────────
function parseDate(str?: string | null): Date | null {
  if (!str) return null;
  const s = str.trim();

  // ISO formatı
  const iso = new Date(s);
  if (!isNaN(iso.getTime())) return iso;

  // "27 Eylül 2026" veya "27.09.2026"
  const months: Record<string, number> = {
    "ocak": 0, "şubat": 1, "mart": 2, "nisan": 3, "mayıs": 4, "haziran": 5,
    "temmuz": 6, "ağustos": 7, "eylül": 8, "ekim": 9, "kasım": 10, "aralık": 11,
    "january": 0, "february": 1, "march": 2, "april": 3, "may": 4, "june": 5,
    "july": 6, "august": 7, "september": 8, "october": 9, "november": 10, "december": 11,
  };

  const longMatch = s.match(/(\d{1,2})\s+([a-zA-ZğüşıöçĞÜŞİÖÇ]+)\s+(\d{4})/i);
  if (longMatch) {
    const day = parseInt(longMatch[1]);
    const month = months[longMatch[2].toLowerCase()];
    const year = parseInt(longMatch[3]);
    if (month !== undefined) return new Date(year, month, day, 12, 0, 0);
  }

  const dotMatch = s.match(/(\d{1,2})\.(\d{1,2})\.(\d{4})/);
  if (dotMatch) {
    return new Date(parseInt(dotMatch[3]), parseInt(dotMatch[2]) - 1, parseInt(dotMatch[1]), 12, 0, 0);
  }

  return null;
}

// ─── HTML'den metin çek (basit regex) ─────────────────────
function extractText(html: string, selector: string): string {
  // class veya tag bazlı basit extractor
  const classMatch = selector.match(/\.([a-zA-Z0-9_-]+)/);
  const tagMatch = selector.match(/^([a-zA-Z]+)/);

  if (classMatch) {
    const cls = classMatch[1];
    const re = new RegExp(`class="[^"]*${cls}[^"]*"[^>]*>([^<]+)<`, "i");
    const m = html.match(re);
    return m ? m[1].trim() : "";
  }
  if (tagMatch) {
    const tag = tagMatch[1];
    const re = new RegExp(`<${tag}[^>]*>([^<]+)<\/${tag}>`, "i");
    const m = html.match(re);
    return m ? m[1].trim() : "";
  }
  return "";
}

function extractAttr(html: string, tag: string, attr: string): string {
  const re = new RegExp(`<${tag}[^>]+${attr}="([^"]+)"`, "i");
  const m = html.match(re);
  return m ? m[1] : "";
}

// ─────────────────────────────────────────────────────────
// SCRAPER 1: Kültür Portalı (Tüm şehirler)
// ─────────────────────────────────────────────────────────
async function scrapeKulturPortali(city: string): Promise<EventInsert[]> {
  const slug = KULTUR_SLUGS[city];
  if (!slug) return [];
  const coords = CITY_COORDS[city];
  const events: EventInsert[] = [];

  // ── Deneme 1: Bilinen REST API endpoint'leri ──────────
  const apiCandidates = [
    `https://www.kulturportali.gov.tr/rest/etkinlik/getEtkinlikler?il=${slug}&page=0&size=30`,
    `https://www.kulturportali.gov.tr/api/v1/etkinlik/list?sehir=${slug}&limit=30`,
    `https://www.kulturportali.gov.tr/api/etkinlik?il=${slug}&limit=30`,
    `https://www.kulturportali.gov.tr/rest/etkinlik/list?sehir=${slug}`,
  ];

  for (const apiUrl of apiCandidates) {
    try {
      console.log(`[KP] API deneniyor: ${apiUrl}`);
      const res = await fetch(apiUrl, {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
          "Accept": "application/json, text/plain, */*",
          "Accept-Language": "tr-TR,tr;q=0.9",
          "Referer": "https://www.kulturportali.gov.tr/",
        },
        signal: AbortSignal.timeout(10000),
      });

      console.log(`[KP] ${apiUrl} → HTTP ${res.status}`);
      if (!res.ok) continue;

      const contentType = res.headers.get("content-type") ?? "";
      if (!contentType.includes("json")) {
        console.log(`[KP] JSON değil (${contentType}), sonraki deneniyor`);
        continue;
      }

      const json = await res.json();
      console.log(`[KP] JSON alındı, keys: ${Object.keys(json).join(", ")}`);

      // Farklı response formatlarını dene
      const items: Record<string, unknown>[] =
        json?.items ?? json?.data ?? json?.etkinlikler ??
        json?.content ?? json?.result ?? json?.Results ?? [];

      if (!Array.isArray(items) || items.length === 0) {
        console.log(`[KP] Etkinlik listesi boş veya bulunamadı`);
        continue;
      }

      console.log(`[KP] ${items.length} etkinlik bulundu (${city})`);

      for (const item of items) {
        const title = (item.adi ?? item.baslik ?? item.title ?? item.name) as string;
        if (!title) continue;

        const startDate = parseDate(
          (item.baslangicTarihi ?? item.tarih ?? item.startDate ?? item.etkinlikTarihi) as string
        );
        if (!startDate) continue;

        const now = new Date();
        const daysDiff = (startDate.getTime() - now.getTime()) / 86400000;
        if (daysDiff < -1 || daysDiff > 14) continue;

        events.push({
          external_id: `kp_${slug}_${String(item.id ?? item.etkinlikId ?? Math.random()).replace(/\./g, "_")}`,
          title,
          description: (item.aciklama ?? item.description ?? item.ozet) as string ?? null,
          city,
          district: (item.ilce ?? item.district ?? item.semt) as string ?? null,
          location_name: (item.mekanAdi ?? item.locationName ?? item.mekan) as string ?? null,
          start_date: startDate.toISOString(),
          end_date: null,
          latitude: (item.enlem ?? coords?.lat) as number ?? null,
          longitude: (item.boylam ?? coords?.lon) as number ?? null,
          image_url: (item.resimUrl ?? item.imageUrl ?? item.gorsel) as string ?? null,
          source_url: (item.detayUrl ?? item.url ?? item.link) as string ?? null,
          category: mapCategory((item.kategori ?? item.category ?? "") as string),
          price: null,
        });
      }

      if (events.length > 0) return events;
    } catch (err) {
      console.warn(`[KP] API hatası (${apiUrl}):`, String(err));
    }
  }

  // ── Deneme 2: HTML + JSON-LD ──────────────────────────
  console.log(`[KP] HTML/JSON-LD fallback deneniyor: ${city}`);
  try {
    const pageUrl = `https://www.kulturportali.gov.tr/turkiye/${slug}/etkinlik`;
    const res = await fetch(pageUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "tr-TR,tr;q=0.9,en;q=0.8",
      },
      signal: AbortSignal.timeout(15000),
    });

    console.log(`[KP] HTML ${city} → HTTP ${res.status}`);
    if (!res.ok) return events;

    const html = await res.text();
    console.log(`[KP] HTML boyutu: ${html.length} byte`);

    // JSON-LD structured data ara
    const jsonLdMatches = [...html.matchAll(/<script[^>]+type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi)];
    console.log(`[KP] JSON-LD blok sayısı: ${jsonLdMatches.length}`);

    for (const m of jsonLdMatches) {
      try {
        const data = JSON.parse(m[1]);
        const items = Array.isArray(data) ? data : (data?.["@graph"] ?? [data]);
        for (const ev of items) {
          if (!["Event", "SocialEvent", "MusicEvent", "TheaterEvent"].includes(ev["@type"])) continue;
          const startDate = parseDate(ev.startDate);
          if (!startDate) continue;
          const now = new Date();
          if ((startDate.getTime() - now.getTime()) / 86400000 > 14) continue;

          events.push({
            external_id: `kp_ld_${city}_${ev.name?.substring(0, 20)}_${startDate.toISOString().split("T")[0]}`.replace(/\s/g, "_"),
            title: ev.name ?? "Etkinlik",
            description: ev.description ?? null,
            city,
            district: ev.location?.address?.addressLocality ?? null,
            location_name: ev.location?.name ?? null,
            start_date: startDate.toISOString(),
            end_date: ev.endDate ? new Date(ev.endDate).toISOString() : null,
            latitude: ev.location?.geo?.latitude ?? coords?.lat ?? null,
            longitude: ev.location?.geo?.longitude ?? coords?.lon ?? null,
            image_url: Array.isArray(ev.image) ? ev.image[0] : ev.image ?? null,
            source_url: ev.url ?? null,
            category: mapCategory(ev["@type"] ?? ""),
            price: null,
          });
        }
      } catch { continue; }
    }

    // Hiç JSON-LD yoksa HTML'den tarih bazlı event link'leri bul (en son çare)
    if (events.length === 0) {
      console.log(`[KP] JSON-LD boş, basit link tarama deneniyor...`);
      const linkMatches = [...html.matchAll(/href="([^"]*etkinlik[^"]*\/(\d{4})[^"]*)"/gi)];
      console.log(`[KP] Etkinlik linkleri: ${linkMatches.length}`);

      const uniqueLinks = [...new Set(linkMatches.map(m => m[1]))].slice(0, 10);
      for (const link of uniqueLinks) {
        const fullUrl = link.startsWith("http") ? link : `https://www.kulturportali.gov.tr${link}`;
        console.log(`[KP] Detay sayfası: ${fullUrl}`);
        // Detay sayfası scraping burada genişletilebilir
      }
    }

  } catch (err) {
    console.error(`[KP] HTML hata (${city}):`, String(err));
  }

  console.log(`[KP] ${city} toplam: ${events.length} etkinlik`);
  return events;
}




// ─────────────────────────────────────────────────────────
// SCRAPER 2: İBB (İstanbul)
// ─────────────────────────────────────────────────────────
async function scrapeIBB(): Promise<EventInsert[]> {
  const events: EventInsert[] = [];

  // İBB Açık API dene
  try {
    const res = await fetch(
      "https://api.ibb.gov.tr/kultur/Event/GetAll?PageSize=100&PageNumber=1",
      {
        headers: {
          "User-Agent": "KesifApp/1.0",
          "Accept": "application/json",
        },
        signal: AbortSignal.timeout(15000),
      }
    );

    if (res.ok) {
      const json = await res.json();
      const items = json?.Result ?? json?.Data ?? json ?? [];

      for (const item of items) {
        const startDate = parseDate(item.StartDate ?? item.BaslangicTarihi ?? item.EventDate);
        if (!startDate) continue;

        const now = new Date();
        const daysDiff = (startDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24);
        if (daysDiff < -1 || daysDiff > 14) continue;

        const district = item.District ?? item.Ilce ?? item.LocationDistrict ?? null;
        const locationName = item.VenueName ?? item.MekanAdi ?? item.Location ?? null;
        let imageUrl = item.ImageUrl ?? item.ResimUrl ?? item.Image ?? null;
        if (imageUrl && imageUrl.startsWith("/")) imageUrl = `https://api.ibb.gov.tr${imageUrl}`;

        events.push({
          external_id: `ibb_${item.Id ?? item.EventId ?? item.Uuid ?? Math.random()}`,
          title: item.Name ?? item.Title ?? item.Adi ?? "Etkinlik",
          description: item.Description ?? item.Aciklama ?? null,
          city: "İstanbul",
          district,
          location_name: locationName,
          start_date: startDate.toISOString(),
          end_date: item.EndDate ? new Date(item.EndDate).toISOString() : null,
          latitude: item.Latitude ?? item.Enlem ?? null,
          longitude: item.Longitude ?? item.Boylam ?? null,
          image_url: imageUrl,
          source_url: item.Url ?? item.DetailUrl ?? null,
          category: mapCategory(item.Category ?? item.Kategori ?? ""),
          price: item.Price ?? item.Ucret ?? null,
        });
      }

      if (events.length > 0) return events;
    }
  } catch (err) {
    console.warn("[İBB API] Hata, HTML scraping deneniyor:", err);
  }

  // HTML fallback
  try {
    const res = await fetch("https://kulturlife.ibb.istanbul/tr/Events", {
      headers: { "User-Agent": "Mozilla/5.0", "Accept": "text/html" },
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) return events;
    const html = await res.text();

    // Event JSON-LD verisi (schema.org)
    const jsonLdMatches = [...html.matchAll(/<script[^>]+type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi)];
    for (const m of jsonLdMatches) {
      try {
        const data = JSON.parse(m[1]);
        const items = Array.isArray(data) ? data : [data];
        for (const ev of items) {
          if (ev["@type"] !== "Event") continue;
          const startDate = parseDate(ev.startDate);
          if (!startDate) continue;

          const now = new Date();
          const daysDiff = (startDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24);
          if (daysDiff < -1 || daysDiff > 14) continue;

          const isOffers = Array.isArray(ev.offers) ? ev.offers[0] : ev.offers;
          const price = isOffers?.price != null ? parseFloat(isOffers.price) : null;

          events.push({
            external_id: `ibb_html_${ev.name?.substring(0, 20)}_${startDate.toISOString().split("T")[0]}`.replace(/\s/g, "_"),
            title: ev.name ?? "Etkinlik",
            description: ev.description ?? null,
            city: "İstanbul",
            district: ev.location?.address?.addressLocality ?? null,
            location_name: ev.location?.name ?? null,
            start_date: startDate.toISOString(),
            end_date: ev.endDate ? new Date(ev.endDate).toISOString() : null,
            latitude: ev.location?.geo?.latitude ?? null,
            longitude: ev.location?.geo?.longitude ?? null,
            image_url: Array.isArray(ev.image) ? ev.image[0] : ev.image ?? null,
            source_url: ev.url ?? null,
            category: mapCategory(ev.eventStatus ?? ev["@type"] ?? ""),
            price: (price === 0 || price == null) ? null : price,
          });
        }
      } catch {
        continue;
      }
    }
  } catch (err) {
    console.error("[İBB HTML] Hata:", err);
  }

  return events;
}

// ─────────────────────────────────────────────────────────
// SCRAPER 3: Ankara Büyükşehir Belediyesi
// ─────────────────────────────────────────────────────────
async function scrapeABB(): Promise<EventInsert[]> {
  const events: EventInsert[] = [];
  const coords = CITY_COORDS["Ankara"]!;

  try {
    const res = await fetch("https://www.ankara.bel.tr/etkinlikler", {
      headers: { "User-Agent": "Mozilla/5.0", "Accept": "text/html", "Accept-Language": "tr" },
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) return events;
    const html = await res.text();

    // JSON-LD dene
    const jsonLdMatches = [...html.matchAll(/<script[^>]+type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi)];
    for (const m of jsonLdMatches) {
      try {
        const data = JSON.parse(m[1]);
        const items = Array.isArray(data) ? data : [data];
        for (const ev of items) {
          if (ev["@type"] !== "Event") continue;
          const startDate = parseDate(ev.startDate);
          if (!startDate) continue;
          const now = new Date();
          if ((startDate.getTime() - now.getTime()) / 86400000 > 14) continue;

          events.push({
            external_id: `abb_${ev.name?.substring(0, 20)}_${startDate.toISOString().split("T")[0]}`.replace(/\s/g, "_"),
            title: ev.name ?? "Etkinlik",
            description: ev.description ?? null,
            city: "Ankara",
            district: ev.location?.address?.addressLocality ?? null,
            location_name: ev.location?.name ?? null,
            start_date: startDate.toISOString(),
            end_date: ev.endDate ? new Date(ev.endDate).toISOString() : null,
            latitude: ev.location?.geo?.latitude ?? coords.lat,
            longitude: ev.location?.geo?.longitude ?? coords.lon,
            image_url: Array.isArray(ev.image) ? ev.image[0] : ev.image ?? null,
            source_url: ev.url ?? null,
            category: mapCategory(ev.eventStatus ?? ""),
            price: null,
          });
        }
      } catch { continue; }
    }
  } catch (err) {
    console.error("[ABB] Hata:", err);
  }

  return events;
}

// ─────────────────────────────────────────────────────────
// SCRAPER 4: İzmir Büyükşehir Belediyesi
// ─────────────────────────────────────────────────────────
async function scrapeIZBB(): Promise<EventInsert[]> {
  const events: EventInsert[] = [];
  const coords = CITY_COORDS["İzmir"]!;

  try {
    const res = await fetch("https://www.izmir.bel.tr/etkinlikler", {
      headers: { "User-Agent": "Mozilla/5.0", "Accept": "text/html" },
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) return events;
    const html = await res.text();

    const jsonLdMatches = [...html.matchAll(/<script[^>]+type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi)];
    for (const m of jsonLdMatches) {
      try {
        const data = JSON.parse(m[1]);
        const items = Array.isArray(data) ? data : [data];
        for (const ev of items) {
          if (ev["@type"] !== "Event") continue;
          const startDate = parseDate(ev.startDate);
          if (!startDate) continue;
          const now = new Date();
          if ((startDate.getTime() - now.getTime()) / 86400000 > 14) continue;

          events.push({
            external_id: `izbb_${ev.name?.substring(0, 20)}_${startDate.toISOString().split("T")[0]}`.replace(/\s/g, "_"),
            title: ev.name ?? "Etkinlik",
            description: ev.description ?? null,
            city: "İzmir",
            district: ev.location?.address?.addressLocality ?? null,
            location_name: ev.location?.name ?? null,
            start_date: startDate.toISOString(),
            end_date: ev.endDate ? new Date(ev.endDate).toISOString() : null,
            latitude: ev.location?.geo?.latitude ?? coords.lat,
            longitude: ev.location?.geo?.longitude ?? coords.lon,
            image_url: Array.isArray(ev.image) ? ev.image[0] : ev.image ?? null,
            source_url: ev.url ?? null,
            category: mapCategory(ev.eventStatus ?? ""),
            price: null,
          });
        }
      } catch { continue; }
    }
  } catch (err) {
    console.error("[İZBB] Hata:", err);
  }

  return events;
}

// ─────────────────────────────────────────────────────────
// VERİTABANINA KAYDET
// ─────────────────────────────────────────────────────────
async function upsertEvents(events: EventInsert[]): Promise<number> {
  if (events.length === 0) return 0;

  let saved = 0;
  // 20'şer batch halinde kaydet
  for (let i = 0; i < events.length; i += 20) {
    const batch = events.slice(i, i + 20);
    try {
      const { error } = await supabase
        .from("events")
        .upsert(batch, { onConflict: "external_id", ignoreDuplicates: false });

      if (error) {
        console.error("[DB] Upsert hatası:", error.message);
      } else {
        saved += batch.length;
      }
    } catch (err) {
      console.error("[DB] Batch hatası:", err);
    }
  }
  return saved;
}

// ─────────────────────────────────────────────────────────
// MAIN HANDLER
// ─────────────────────────────────────────────────────────
serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const start = Date.now();
  console.log(`[scrape-events] Başladı: ${new Date().toISOString()}`);

  try {
    const url = new URL(req.url);
    const cityParam = url.searchParams.get("city");

    // Hangi şehirleri tara
    const targetCities = cityParam
      ? [cityParam]
      : Object.keys(KULTUR_SLUGS);

    let totalEvents: EventInsert[] = [];
    let totalSaved = 0;

    // 1. İBB (her zaman)
    if (!cityParam || cityParam === "İstanbul") {
      console.log("[İBB] Taranıyor...");
      const ibbEvents = await scrapeIBB();
      totalEvents.push(...ibbEvents);
      console.log(`[İBB] ${ibbEvents.length} etkinlik bulundu`);
    }

    // 2. ABB (her zaman veya Ankara istenince)
    if (!cityParam || cityParam === "Ankara") {
      console.log("[ABB] Taranıyor...");
      const abbEvents = await scrapeABB();
      totalEvents.push(...abbEvents);
      console.log(`[ABB] ${abbEvents.length} etkinlik bulundu`);
    }

    // 3. İZBB
    if (!cityParam || cityParam === "İzmir") {
      console.log("[İZBB] Taranıyor...");
      const izbbEvents = await scrapeIZBB();
      totalEvents.push(...izbbEvents);
      console.log(`[İZBB] ${izbbEvents.length} etkinlik bulundu`);
    }

    // 4. Kültür Portalı (tüm şehirler)
    for (const city of targetCities) {
      console.log(`[KültürPortalı] ${city} taranıyor...`);
      const cityEvents = await scrapeKulturPortali(city);
      totalEvents.push(...cityEvents);
      console.log(`[KültürPortalı] ${city}: ${cityEvents.length} etkinlik`);
    }

    // Kaydet
    totalSaved = await upsertEvents(totalEvents);

    const elapsed = Date.now() - start;
    const result = {
      success: true,
      cities: targetCities.length,
      eventsFound: totalEvents.length,
      eventsSaved: totalSaved,
      elapsedMs: elapsed,
    };

    console.log("[scrape-events] Tamamlandı:", result);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[scrape-events] Kritik hata:", err);
    return new Response(JSON.stringify({ success: false, error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
