import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nak_tumpang/core/entities/train_station.dart';
import 'package:nak_tumpang/core/data/train_station_data.dart';

class GtfsService {
  final String _apiUrl = 'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl';
  final String _cacheKey = 'cached_train_stations';
  final String _dateKey = 'gtfs_last_updated';

  Future<void> initStations() async {
    // 1. Skip if already loaded into RAM this session
    if (TrainStationData.stations.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastUpdateStr = prefs.getString(_dateKey);
    final cachedData = prefs.getString(_cacheKey);

    bool needsUpdate = true;

    // 2. Check if local cache exists and is fresh (< 7 days old)
    if (lastUpdateStr != null && cachedData != null) {
      final lastUpdate = DateTime.parse(lastUpdateStr);
      if (DateTime.now().difference(lastUpdate).inDays < 7) {
        needsUpdate = false;

        // Load instantly from phone storage
        final List<dynamic> decoded = json.decode(cachedData);
        TrainStationData.stations = decoded.map((e) => TrainStation.fromJson(e)).toList();
        print('✅ Loaded ${TrainStationData.stations.length} transit stations from local cache.');
      }
    }

    // 3. Only download from API if cache is missing or expired
    if (needsUpdate) {
      await _fetchAndExtractGtfs(prefs);
    }
  }

  Future<void> _fetchAndExtractGtfs(SharedPreferences prefs) async {
    try {
      print('⏳ Downloading new GTFS data...');
      final response = await http.get(Uri.parse(_apiUrl));

      if (response.statusCode == 200) {
        final archive = ZipDecoder().decodeBytes(response.bodyBytes);

        String stopsCsv = '';
        String routesCsv = '';
        String stopTimesCsv = '';

        for (final file in archive) {
          if (!file.isFile) continue;
          if (file.name == 'stops.txt') stopsCsv = String.fromCharCodes(file.content as List<int>);
          if (file.name == 'routes.txt') routesCsv = String.fromCharCodes(file.content as List<int>);
          if (file.name == 'stop_times.txt') stopTimesCsv = String.fromCharCodes(file.content as List<int>);
        }

        await _populateAndCacheStations(stopsCsv, routesCsv, stopTimesCsv, prefs);
      }
    } catch (e) {
      print('Error fetching GTFS data: $e');
    }
  }

  Future<void> _populateAndCacheStations(String stopsCsv, String routesCsv, String stopTimesCsv, SharedPreferences prefs) async {
    final routeDetails = <String, ({String name, Color color})>{};
    for (var line in routesCsv.split('\n').skip(1)) {
      final parts = line.split(',');
      if (parts.length > 6) {
        final color = Color(int.parse('FF${parts[6].trim()}', radix: 16));
        routeDetails[parts[0].trim()] = (name: parts[3].trim(), color: color);
      }
    }

    final stopSequences = <String, int>{};
    for (var line in stopTimesCsv.split('\n').skip(1)) {
      final parts = line.split(',');
      if (parts.length > 6) {
        final stopId = parts[5].trim();
        if (!stopSequences.containsKey(stopId)) {
          stopSequences[stopId] = int.tryParse(parts[6].trim()) ?? 0;
        }
      }
    }

    final parsedStations = <TrainStation>[];
    for (var line in stopsCsv.split('\n').skip(1)) {
      final parts = line.split(',');
      if (parts.length > 5) {
        final lat = double.tryParse(parts[2].trim()) ?? 0.0;
        final lon = double.tryParse(parts[3].trim()) ?? 0.0;
        final routeId = parts[5].trim();

        if (lat == 0.0 || lon == 0.0) continue;
        final details = routeDetails[routeId];

        parsedStations.add(
            TrainStation(
              id: parts[0].trim(),
              name: parts[1].trim(),
              location: LatLng(lat, lon),
              lineId: routeId,
              lineName: details?.name ?? routeId,
              lineColor: details?.color ?? Colors.pink,
              sequence: stopSequences[parts[0].trim()] ?? 0,
            )
        );
      }
    }

    // Update RAM
    TrainStationData.stations = parsedStations;

    // Save to Local Storage and update timestamp
    final jsonList = parsedStations.map((s) => s.toJson()).toList();
    await prefs.setString(_cacheKey, json.encode(jsonList));
    await prefs.setString(_dateKey, DateTime.now().toIso8601String());

    print('✅ Saved ${TrainStationData.stations.length} transit stations to local cache.');
  }
}