import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SyncService {
  static const String _offlineWalkRecordsKey = 'offline_walk_records';
  
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  void initialize() {
    // Listen for connectivity changes and trigger sync when online
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.mobile) || 
          results.contains(ConnectivityResult.wifi) || 
          results.contains(ConnectivityResult.ethernet)) {
        syncOfflineRecords();
      }
    });
  }

  /// Saves a walk record. If offline, queues it locally. 
  /// If online, attempts to upload directly.
  Future<void> saveWalkRecord(Map<String, dynamic> recordData) async {
    final connectivityResult = await Connectivity().checkConnectivity();
    
    if (connectivityResult.contains(ConnectivityResult.none)) {
      await _saveLocally(recordData);
    } else {
      try {
        await Supabase.instance.client.from('walk_records').insert(recordData);
      } catch (e) {
        // If upload fails despite being online, save locally to retry later
        debugPrint('Direct upload failed, saving locally: $e');
        await _saveLocally(recordData);
      }
    }
  }

  Future<void> _saveLocally(Map<String, dynamic> recordData) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> offlineRecords = prefs.getStringList(_offlineWalkRecordsKey) ?? [];
    
    offlineRecords.add(jsonEncode(recordData));
    await prefs.setStringList(_offlineWalkRecordsKey, offlineRecords);
    
    debugPrint('Offline record saved. Total queued: ${offlineRecords.length}');
  }

  /// Attempts to upload all locally saved records to the server.
  Future<void> syncOfflineRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> offlineRecords = prefs.getStringList(_offlineWalkRecordsKey) ?? [];

    if (offlineRecords.isEmpty) return;

    List<String> failedRecords = [];

    for (String recordString in offlineRecords) {
      try {
        final Map<String, dynamic> recordData = jsonDecode(recordString);
        await Supabase.instance.client.from('walk_records').insert(recordData);
      } catch (e) {
        debugPrint('Failed to sync offline record: $e');
        failedRecords.add(recordString); // Keep in queue if it fails
      }
    }

    if (failedRecords.isEmpty) {
      await prefs.remove(_offlineWalkRecordsKey);
      debugPrint('All offline records synced successfully.');
    } else {
      await prefs.setStringList(_offlineWalkRecordsKey, failedRecords);
      debugPrint('${failedRecords.length} offline records failed to sync. Kept in queue.');
    }
  }
}
