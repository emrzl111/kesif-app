import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

void main() async {
  final url = Uri.parse('https://bhgefvqpojdersndsetp.supabase.co/rest/v1/discovery_points');
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJoZ2VmdnFwb2pkZXJzbmRzZXRwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM1MjUwNTIsImV4cCI6MjA5OTEwMTA1Mn0.7jcIPEv8KzyFjuVnvtx_d9JkPBAhs0HYHkGEhgPil5M';
  
  final uuid = Uuid();
  
  final points = [
    {
      'id': uuid.v4(),
      'title': 'Sefaköy Botanik Kafe ☕',
      'description': 'Bahçesinde harika çiçekler olan ve lezzetli kahveler sunan huzurlu mekan.',
      'latitude': 40.9915,
      'longitude': 28.7850,
      'category': 0, // Kafe
      'likes': 42,
      'is_pet_friendly': true,
      'created_at': DateTime.now().toIso8601String(),
    },
    {
      'id': uuid.v4(),
      'title': 'Cennet Manzara Tepesi 🌅',
      'description': 'Gün batımını izlemek için Sefaköy civarındaki en yüksek ve keyifli tepe.',
      'latitude': 40.9880,
      'longitude': 28.7810,
      'category': 3, // Manzara
      'likes': 78,
      'is_pet_friendly': true,
      'created_at': DateTime.now().toIso8601String(),
    },
    {
      'id': uuid.v4(),
      'title': 'Sefaköy Kültür Parkı 🌳',
      'description': 'Yürüyüş yolları ve evcil hayvan alanlarıyla yemyeşil bir dinlenme noktası.',
      'latitude': 40.9902,
      'longitude': 28.7830,
      'category': 4, // Park
      'likes': 25,
      'is_pet_friendly': true,
      'created_at': DateTime.now().toIso8601String(),
    },
    {
      'id': uuid.v4(),
      'title': 'Cennet Sanat Kahvesi ☕',
      'description': 'Duvarlarında harika tablolar olan ve sessiz çalışma ortamı sunan yer.',
      'latitude': 40.9875,
      'longitude': 28.7860,
      'category': 0, // Kafe
      'likes': 64,
      'is_pet_friendly': true,
      'created_at': DateTime.now().toIso8601String(),
    },
    {
      'id': uuid.v4(),
      'title': 'Sefaköy Sessiz Kütüphane 💻',
      'description': 'Prizleri bol, interneti hızlı ve tamamen sessiz ders çalışma/çalışma alanı.',
      'latitude': 40.9930,
      'longitude': 28.7865,
      'category': 7, // Çalışmaya Uygun
      'likes': 112,
      'is_pet_friendly': true,
      'created_at': DateTime.now().toIso8601String(),
    },
    {
      'id': uuid.v4(),
      'title': 'Sefaköy Gurme Restoran 🍽️',
      'description': 'Eşsiz yöresel yemeklerin sunulduğu temiz ve şık bir aile restoranı.',
      'latitude': 40.9940,
      'longitude': 28.7815,
      'category': 1, // Restaurant
      'likes': 53,
      'is_pet_friendly': false,
      'created_at': DateTime.now().toIso8601String(),
    },
    {
      'id': uuid.v4(),
      'title': 'Canlı Müzik Sahnesi 🎸',
      'description': 'Haftasonları yerel grupların sahne aldığı keyifli eğlence mekanı.',
      'latitude': 40.9910,
      'longitude': 28.7890,
      'category': 6, // Canlı Müzik
      'likes': 91,
      'is_pet_friendly': false,
      'created_at': DateTime.now().toIso8601String(),
    },
    {
      'id': uuid.v4(),
      'title': 'Tarihi Çeşme Meydanı 🏛️',
      'description': 'Osmanlı döneminden kalma restore edilmiş tarihi çeşme ve etrafındaki dinlenme alanı.',
      'latitude': 40.9935,
      'longitude': 28.7885,
      'category': 5, // Tarihi Yer
      'likes': 37,
      'is_pet_friendly': false,
      'created_at': DateTime.now().toIso8601String(),
    }
  ];

  print('Sefaköy mock noktaları Supabase veritabanına ekleniyor...');
  
  try {
    final response = await http.post(
      url,
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: jsonEncode(points),
    );

    if (response.statusCode == 201) {
      print('Başarılı! Sefaköy civarına 8 adet keşif noktası Supabase veritabanına başarıyla eklendi.');
    } else {
      print('Hata oluştu! Durum Kodu: ${response.statusCode}');
      print('Cevap: ${response.body}');
    }
  } catch (e) {
    print('HTTP Hatası: $e');
  }
}
