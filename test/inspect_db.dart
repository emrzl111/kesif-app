import 'package:supabase_flutter/supabase_flutter.dart';

const String _supabaseUrl = 'https://bhgefvqpojdersndsetp.supabase.co';
const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJoZ2VmdnFwb2pkZXJzbmRzZXRwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM1MjUwNTIsImV4cCI6MjA5OTEwMTA1Mn0.7jcIPEv8KzyFjuVnvtx_d9JkPBAhs0HYHkGEhgPil5M';

void main() async {
  final client = SupabaseClient(_supabaseUrl, _supabaseAnonKey);
  try {
    print('Testing is_read on messages table...');
    await client.from('messages').insert({
      'sender_id': '00000000-0000-0000-0000-000000000000',
      'receiver_id': '00000000-0000-0000-0000-000000000000',
      'content': 'Test',
      'is_read': false,
    });
    print('Insert succeeded with is_read!');
  } catch (e) {
    print('Error on messages insert: $e');
  }

  try {
    print('Testing read on messages table...');
    await client.from('messages').insert({
      'sender_id': '00000000-0000-0000-0000-000000000000',
      'receiver_id': '00000000-0000-0000-0000-000000000000',
      'content': 'Test',
      'read': false,
    });
    print('Insert succeeded with read!');
  } catch (e) {
    print('Error on messages insert (read): $e');
  }
}
