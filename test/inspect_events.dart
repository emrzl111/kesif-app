import 'package:supabase_flutter/supabase_flutter.dart';

const String _supabaseUrl = 'https://bhgefvqpojdersndsetp.supabase.co';
const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJoZ2VmdnFwb2pkZXJzbmRzZXRwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM1MjUwNTIsImV4cCI6MjA5OTEwMTA1Mn0.7jcIPEv8KzyFjuVnvtx_d9JkPBAhs0HYHkGEhgPil5M';

void main() async {
  final client = SupabaseClient(_supabaseUrl, _supabaseAnonKey);
  
  print('--- Supabase Kontrolü ---');
  
  try {
    final pointsCount = await client.from('discovery_points').select('id');
    print('Discovery Points (Keşfet Noktaları) sayısı: ${pointsCount.length}');
    if (pointsCount.isNotEmpty) {
      print('Örnek Nokta ID: ${pointsCount.first}');
    }
  } catch (e) {
    print('Discovery Points tablosu sorgu hatası: $e');
  }

  try {
    final eventsCount = await client.from('events').select('id, city, district');
    print('Events (Etkinlikler) sayısı: ${eventsCount.length}');
    if (eventsCount.isNotEmpty) {
      print('Örnek Etkinlik: ${eventsCount.first}');
      
      final Map<String, int> cityCounts = {};
      for (var ev in eventsCount) {
        final city = ev['city'] as String? ?? 'Bilinmeyen';
        cityCounts[city] = (cityCounts[city] ?? 0) + 1;
      }
      print('Şehirlere göre dağılım: $cityCounts');
    }
  } catch (e) {
    print('Events tablosu sorgu hatası: $e');
  }
}
