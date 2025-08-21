import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class UuidManagerService {
  Future<String> getOrCreateGaUserId() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'ga_user_id';

    // 이미 저장돼 있으면 재사용
    final existing = prefs.getString(key);
    if (existing != null) return existing;

    // 없으면 새로 만들고 저장
    final newId = const Uuid().v4(); // e4c1c7fd-1d15-4e2a-a9e7-a9b9e1…
    await prefs.setString(key, newId);
    return newId;
  }
}
