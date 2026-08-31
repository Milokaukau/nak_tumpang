import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nak_tumpang/core/entities/train_station.dart';
import 'package:nak_tumpang/core/data/train_station_data.dart';
import 'package:nak_tumpang/core/constants/api_constants.dart';
import 'package:csv/csv.dart';

class GtfsService {
  // --- UPDATED to use ApiConstants ---
  final String _apiUrl = ApiConstants.gtfsPrasaranaEndpoint;
  final String _cacheKey = 'cached_train_stations';
  final String _dateKey = 'gtfs_last_updated';

  Future<void> initStations() async {
    if (TrainStationData.stations.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastUpdateStr = prefs.getString(_dateKey);
    final cachedData = prefs.getString(_cacheKey);

    bool needsUpdate = true;

    if (lastUpdateStr != null && cachedData != null) {
      final lastUpdate = DateTime.parse(lastUpdateStr);
      if (DateTime.now().difference(lastUpdate).inDays < 7) {
        needsUpdate = false;
        final List<dynamic> decoded = json.decode(cachedData);
        TrainStationData.stations = decoded.map((e) => TrainStation.fromJson(e)).toList();
        print('✅ Loaded ${TrainStationData.stations.length} transit stations from local cache.');
      }
    }

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

  Future<void> _populateAndCacheStations(
      String stopsCsv,
      String routesCsv,
      String stopTimesCsv,
      SharedPreferences prefs) async {

    final converter = CsvToListConverter(eol: '\n', shouldParseNumbers: false);

    // ==========================================
    // 1. PARSE ROUTES
    // ==========================================
    final routeDetails = <String, ({String name, Color color, String shortName})>{};
    final routeRows = converter.convert(routesCsv.replaceAll('\r', ''));

    if (routeRows.isNotEmpty) {
      final headers = routeRows.first.map((e) => e.toString().trim()).toList();
      final idIdx = headers.indexOf('route_id');
      final shortIdx = headers.indexOf('route_short_name');
      final longIdx = headers.indexOf('route_long_name');
      final colorIdx = headers.indexOf('route_color');

      if (idIdx != -1) {
        for (var i = 1; i < routeRows.length; i++) {
          final row = routeRows[i];
          if (row.length > idIdx) {
            final routeId = row[idIdx].toString().trim();
            final shortName = shortIdx != -1 && row.length > shortIdx ? row[shortIdx].toString().trim() : '';
            final longName = longIdx != -1 && row.length > longIdx ? row[longIdx].toString().trim() : '';
            final colorHex = colorIdx != -1 && row.length > colorIdx ? row[colorIdx].toString().trim() : '';

            if (routeId.isNotEmpty) {
              Color color = Colors.pink; // Default fallback
              if (colorHex.isNotEmpty) {
                try {
                  color = Color(int.parse('FF$colorHex', radix: 16));
                } catch (_) {}
              }
              routeDetails[routeId] = (
              name: longName,
              color: color,
              shortName: shortName,
              );
            }
          }
        }
      }
    }

    // ==========================================
    // 2. PARSE STOP TIMES (For Sequence)
    // ==========================================
    final stopSequences = <String, int>{};
    final stRows = converter.convert(stopTimesCsv.replaceAll('\r', ''));

    if (stRows.isNotEmpty) {
      final headers = stRows.first.map((e) => e.toString().trim()).toList();
      final stopIdIdx = headers.indexOf('stop_id');
      final seqIdx = headers.indexOf('stop_sequence');

      if (stopIdIdx != -1 && seqIdx != -1) {
        for (var i = 1; i < stRows.length; i++) {
          final row = stRows[i];
          if (row.length > stopIdIdx && row.length > seqIdx) {
            final stopId = row[stopIdIdx].toString().trim();
            if (!stopSequences.containsKey(stopId)) {
              stopSequences[stopId] = int.tryParse(row[seqIdx].toString().trim()) ?? 0;
            }
          }
        }
      }
    }

    // ==========================================
    // 3. PARSE STOPS
    // ==========================================
    final parsedStations = <TrainStation>[];
    final stopRows = converter.convert(stopsCsv.replaceAll('\r', ''));

    if (stopRows.isNotEmpty) {
      final headers = stopRows.first.map((e) => e.toString().trim()).toList();
      final idIdx = headers.indexOf('stop_id');
      final nameIdx = headers.indexOf('stop_name');
      final latIdx = headers.indexOf('stop_lat');
      final lonIdx = headers.indexOf('stop_lon');

      int routeIdx = headers.indexOf('route_id');
      if (routeIdx == -1) routeIdx = headers.indexOf('zone_id');
      if (routeIdx == -1) routeIdx = 5;

      if (idIdx != -1 && latIdx != -1 && lonIdx != -1) {
        for (var i = 1; i < stopRows.length; i++) {
          final row = stopRows[i];
          if (row.length > idIdx && row.length > latIdx && row.length > lonIdx) {
            final lat = double.tryParse(row[latIdx].toString().trim()) ?? 0.0;
            final lon = double.tryParse(row[lonIdx].toString().trim()) ?? 0.0;
            final stopId = row[idIdx].toString().trim();
            final stopName = nameIdx != -1 && row.length > nameIdx ? row[nameIdx].toString().trim() : stopId;
            final routeId = routeIdx != -1 && row.length > routeIdx ? row[routeIdx].toString().trim() : '';

            if (lat == 0.0 || lon == 0.0) continue;
            final details = routeDetails[routeId];

            parsedStations.add(
              TrainStation(
                id: stopId,
                name: stopName,
                location: LatLng(lat, lon),
                lineId: routeId,
                lineName: details?.name ?? routeId,
                lineShortName: details?.shortName ?? routeId,
                lineColor: details?.color ?? Colors.pink,
                sequence: stopSequences[stopId] ?? 0,
              ),
            );
          }
        }
      }
    }

    TrainStationData.stations = parsedStations;
    final jsonList = parsedStations.map((s) => s.toJson()).toList();
    await prefs.setString(_cacheKey, json.encode(jsonList));
    await prefs.setString(_dateKey, DateTime.now().toIso8601String());

    print('✅ Saved ${TrainStationData.stations.length} transit stations to local cache.');
  }
}