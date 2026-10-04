import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/app_logger.dart';

class WeatherData {
  final double temperature;
  final double apparentTemperature;
  final int humidity;
  final double windSpeed;
  final String conditionText;
  final String sunsetTime;
  final String recommendation;
  final int weatherCode;

  WeatherData({
    required this.temperature,
    required this.apparentTemperature,
    required this.humidity,
    required this.windSpeed,
    required this.conditionText,
    required this.sunsetTime,
    required this.recommendation,
    required this.weatherCode,
  });

  factory WeatherData.mock() {
    return WeatherData(
      temperature: 22.0,
      apparentTemperature: 23.0,
      humidity: 54,
      windSpeed: 12.0,
      conditionText: 'Parçalı Bulutlu',
      sunsetTime: '19:18',
      recommendation: 'Şehir keşfi ve yürüyüş için ideal hava.',
      weatherCode: 2,
    );
  }
}

class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  WeatherData? _cachedData;
  DateTime? _lastFetchTime;
  double? _lastLat;
  double? _lastLng;

  Future<WeatherData> getWeather(double latitude, double longitude) async {
    // 15 dakikalık önbellek
    if (_cachedData != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inMinutes < 15 &&
        _lastLat != null &&
        (_lastLat! - latitude).abs() < 0.05 &&
        _lastLng != null &&
        (_lastLng! - longitude).abs() < 0.05) {
      return _cachedData!;
    }

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latitude&longitude=$longitude'
        '&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m'
        '&daily=sunset&timezone=auto',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];
        final daily = data['daily'];

        final temp = (current['temperature_2m'] as num).toDouble();
        final appTemp = (current['apparent_temperature'] as num).toDouble();
        final hum = (current['relative_humidity_2m'] as num).round();
        final wind = (current['wind_speed_10m'] as num).toDouble();
        final code = (current['weather_code'] as num).toInt();

        // Günbatımı saati (2026-09-29T19:18 -> 19:18)
        String sunset = '19:18';
        if (daily != null && daily['sunset'] != null && (daily['sunset'] as List).isNotEmpty) {
          final rawSunset = daily['sunset'][0].toString();
          if (rawSunset.contains('T')) {
            sunset = rawSunset.split('T')[1].substring(0, 5);
          }
        }

        final condition = _getConditionText(code);
        final tip = _getRecommendation(code, temp, wind);

        _cachedData = WeatherData(
          temperature: temp,
          apparentTemperature: appTemp,
          humidity: hum,
          windSpeed: wind,
          conditionText: condition,
          sunsetTime: sunset,
          recommendation: tip,
          weatherCode: code,
        );
        _lastFetchTime = DateTime.now();
        _lastLat = latitude;
        _lastLng = longitude;

        return _cachedData!;
      }
    } catch (e) {
      AppLogger.error('Hava durumu çekme hatası', error: e, tag: 'WeatherService');
    }

    return _cachedData ?? WeatherData.mock();
  }

  String _getConditionText(int code) {
    if (code == 0) return 'Açık Güneşli';
    if (code == 1) return 'Çoğunlukla Açık';
    if (code == 2) return 'Parçalı Bulutlu';
    if (code == 3) return 'Kapalı Bulutlu';
    if (code >= 45 && code <= 48) return 'Sisli';
    if (code >= 51 && code <= 55) return 'Çiseleyen Yağmur';
    if (code >= 61 && code <= 65) return 'Yağmurlu';
    if (code >= 71 && code <= 77) return 'Kar Yağışlı';
    if (code >= 80 && code <= 82) return 'Sağanak Yağışlı';
    if (code >= 95 && code <= 99) return 'Gök Gürültülü Fırtına';
    return 'Hafif Bulutlu';
  }

  String _getRecommendation(int code, double temp, double wind) {
    if (code >= 51 && code <= 82) {
      return 'Yağmura dikkat! Şemsiyeni yanına almayı unutma.';
    }
    if (code >= 95) {
      return 'Fırtınalı hava. Kapalı mekan etkinliklerini tercih et.';
    }
    if (temp >= 20 && temp <= 27 && wind < 20) {
      return 'Şehir keşfi ve yürüyüş için ideal hava.';
    }
    if (temp > 27) {
      return 'Sıcak hava. Güneş gözlüğü ve su almayı ihmal etme.';
    }
    if (temp < 12) {
      return 'Hava serin. Sıcak bir kahve eşliğinde keşfe çık!';
    }
    return 'Şehir keşfi ve yürüyüş için güzel bir gün.';
  }
}
