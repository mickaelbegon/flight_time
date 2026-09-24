import 'dart:io';

import 'package:flight_time/models/file_manager.dart';
import 'package:flight_time/models/text_manager.dart';
import 'package:flight_time/models/video_meta_data.dart';
import 'package:path/path.dart';
import 'package:sembast/sembast_io.dart';

class Athletes {
  Database? _database;
  bool _isReady = false;
  bool get isReady => _isReady;
  final _store = StoreRef.main();
  final List<Athlete> _athletes = [];

  // Prepare the singleton
  static Athletes? _instance;
  static Athletes get instance => _instance!;
  Athletes._();

  ///
  /// Wait for the database to be ready
  static Future<void> initialize() async {
    if (Athletes._instance?.isReady ?? false) return;

    Athletes._instance = Athletes._();
    Athletes._instance!._initializeDataBase();

    //await _deleteCacheFolder();

    while (!Athletes._instance!.isReady) {
      // wait for the database to be ready
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  ///
  /// Return an immutable list of athletes
  List<Athlete> get athletes => List.unmodifiable(_athletes);

  Future<void> _initializeDataBase() async {
    // open the database
    _database = await databaseFactoryIo.openDatabase(await databasePath());

    // load the athletes
    final athletes = await _store.find(_database!);
    _athletes.addAll(athletes.map(
        (record) => Athlete.fromJson(record.value as Map<String, dynamic>)));

    _isReady = true;
  }

  ///
  /// This method checks for unclassified videos in the cache folder.
  /// If a video is found, it adds it to the unclassified athlete in the metadata field.
  Future<Athlete> checkForUnclassifiedVideos() async {
    final unclassified = Athlete(name: TextManager.instance.unclassified.en);

    // Look at videos that are in the cache folder. They do not belong to any athlete yet
    final cacheDir = Directory(await FileManager.cacheFolder);
    try {
      final files = await cacheDir.list().toList();
      for (var file in files) {
        if (file is File && extension(file.path) == '.mp4') {
          unclassified._videoMetaDataPaths.add(file.path);
        }
      }
    } catch (e) {
      // Do nothing and return what we have so far
    }
    return unclassified;
  }

  Future<String> databasePath() async =>
      join(await FileManager.dataFolder, 'athletes.db');

  ///
  /// Get an athlete from their name, throws if the athlete does not exist
  Athlete athleteFromName(String name) =>
      _athletes.firstWhere((athlete) => athlete.name == name);

  ///
  /// Get an athlete from their name, adds it if it does not exist
  Future<Athlete> athleteFromNameOrAdd(String name) async {
    try {
      return athleteFromName(name);
    } on StateError {
      await addAthlete(name);
      return athleteFromName(name);
    }
  }

  ///
  /// Add a new athlete from their name, if the athlete already exists, throw an error
  /// Return the newly created athlete
  Future<void> addAthlete(String name) async {
    if (!isReady) throw StateError('Database is not ready');
    if (_athletes.any((athlete) => athlete.name == name)) {
      throw StateError('Athlete already exists');
    }

    final athlete = Athlete(name: name);
    await _store.record(athlete.name).put(_database!, athlete.toJson());
    _athletes.add(athlete);
  }

  ///
  /// Add a video to an athlete, if the video already exists in the database,
  /// only the metadata file is updated
  Future<void> addVideo(VideoMetaData metaData) async {
    if (!isReady) throw StateError('Database is not ready');

    final athlete = metaData.athlete;
    if (!_athletes.any((knownAthlete) => knownAthlete.name == athlete.name)) {
      throw StateError('Athlete does not exist');
    }

    // Update the metadata file
    await metaData.writeToDisk();

    // If the video already exists, we are done
    if (athlete.videoMetaDataPaths.contains(metaData.path)) return;

    // Add the video to the athlete
    athlete._videoMetaDataPaths.add(metaData.path);

    // Update the database
    await _store.record(athlete.name).put(_database!, athlete.toJson());
  }

  ///
  /// Remove a video from an athlete, throws if the video does not exist
  Future<void> removeVideo(VideoMetaData metaData) async {
    if (!isReady) throw StateError('Database is not ready');

    if (metaData.isFromCorrupted) {
      // This is a special case where the actual video is stored in the metadata path
      // but nothing else exist (neither the athlete nor the metadata)
      await File(metaData.videoPath).delete();
      return;
    }

    final athlete = metaData.athlete;

    // If the video does not exist, then it is not possible to remove it
    if (!athlete.videoMetaDataPaths.contains(metaData.path)) {
      throw StateError('Video does not exist');
    }

    // Delete the metadata
    await metaData.deleteFile();

    // Remove the video from the athlete
    athlete._videoMetaDataPaths.remove(metaData.path);

    // Update the database
    await _store.record(athlete.name).put(_database!, athlete.toJson());

    // Remove file from disk
    await File(metaData.videoPath).delete();
  }

  ///
  /// Remove an athlete, throws if the athlete does not exist
  Future<void> removeAthlete(String name) async {
    if (!isReady) throw StateError('Database is not ready');

    // Get the athlete and remove it from the database
    Athlete athlete = athleteFromName(name);
    await _store.record(athlete.name).delete(_database!);
    _athletes.remove(athlete);
  }

  ///
  /// Get the athletes names
  Iterable<String> get athleteNames => _athletes.map((athlete) => athlete.name);

  ///
  /// Reset the database
  /// This will remove all the athletes and their videos. This is irreversible!
  Future<void> reset() async {
    if (!isReady) throw StateError('Database is not ready');

    // Remove all the athletes
    for (var athlete in _athletes) {
      await _store.record(athlete.name).delete(_database!);
    }
    _athletes.clear();
  }
}

class Athlete {
  final String name;
  final List<String> _videoMetaDataPaths = [];
  List<String> get videoMetaDataPaths => List.unmodifiable(_videoMetaDataPaths);

  Athlete({required this.name});

  Map<String, dynamic> toJson() => {
        'name': name,
        'meta_data_paths': videoMetaDataPaths,
      };

  factory Athlete.fromJson(
          Map<String, dynamic> json) =>
      Athlete(name: json['name'])
        .._videoMetaDataPaths
            .addAll((json['meta_data_paths'] as List).cast<String>());
}
