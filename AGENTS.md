# Guide de navigation rapide

Ce dépôt est une application Flutter de mesure du temps de vol à partir d’une
vidéo. Avant de modifier une zone, lire le fichier ciblé et ses tests associés
plutôt que de relire l’ensemble du dépôt.

## Repères de code

- `lib/screens/camera_page.dart` : acquisition caméra et configuration de la
  cadence Android. La sélection enregistrée sous `captureFps` vaut 30, 60, 120
  ou 240 fps.
- `lib/screens/playback_page.dart` : initialisation/remplacement du
  `VideoPlayerController`, notamment après la fin de lecture Android.
- `lib/widgets/scaffold_video_playback.dart` : interface de replay, choix manuel
  de fps, bornes décollage/atterrissage et sauvegarde des essais.
- `lib/widgets/video_playback_timing.dart` : conversions durée/image et
  arithmétique en microsecondes. Centraliser ici tout nouveau calcul lié aux
  frames.
- `lib/widgets/video_seek_coordinator.dart` : coordination « last request wins »
  des `seekTo()` ; ne pas réintroduire de rafales de seeks concurrents.
- `lib/widgets/velocity_jog_scrubber*.dart` : molette de scrubbing et modèle de
  vitesse, avec inversion de direction.
- `lib/models/video_meta_data.dart`, `lib/models/athletes.dart` et
  `lib/models/file_manager.dart` : persistance et compatibilité des essais.
- `test/video_seek_coordinator_test.dart`,
  `test/video_playback_timing_test.dart` et
  `test/velocity_jog_scrubber*_test.dart` : tests ciblés du replay.

## Capture Android haute fréquence

Flight Time dépend temporairement du fork `mickaelbegon/CamerAwesome`, référencé
dans `pubspec.yaml`. Les changements natifs correspondants sont sur la branche
`high-speed-video-poc` de ce fork.

`AndroidVideoOptions.highSpeedFrameRate` demande une session CameraX à cadence
exacte. Seules les plages explicitement supportées par l’appareil sont activées;
sinon le plugin revient à la capture standard. Ne pas prétendre que la cadence
est garantie après ce repli. Les contraintes CameraX haute vitesse excluent à
ce stade audio, multi-capteur et analyse d’image.

Le Pixel 8a a été validé en 1080p/240 fps. Consulter
`docs/android_high_speed_capture.md` avant de modifier ce flux.

## Contraintes fonctionnelles

- Préserver le choix manuel de replay à 30 / 60 / 120 / 240 fps.
- Ne pas migrer le modèle de données vers `startFrame`, `endFrame` ou
  `captureFps` sans tâche dédiée : les essais déjà enregistrés doivent rester
  lisibles.
- Les positions vidéo internes utilisent des microsecondes. Toujours protéger
  les calculs contre une durée nulle et vérifier `mounted` après les `await`
  d’un widget.

## Validation

Après un changement Dart :

1. `dart format` sur les fichiers modifiés ;
2. `flutter analyze` ;
3. `flutter test` ou les tests ciblés.

Sur macOS, les tests Sembast de `test/athletes_test.dart` sont réservés à Linux
et échouent donc indépendamment des changements de replay. Pour valider le
plugin Android après une mise à jour Git, exécuter depuis `android/` :

```sh
./gradlew :camerawesome:clean :camerawesome:compileDebugKotlin --no-daemon
./gradlew app:assembleDebug --no-daemon
```

La compilation actuelle signale encore une mise à jour Kotlin à prévoir et des
dépréciations CamerAwesome ; ne pas les confondre avec une régression du flux
haute vitesse.

## Git

Ne pas versionner les artefacts générés `android/build/` ni les préférences
locales de `android/gradle.properties`. Vérifier le diff avant tout commit et
garder les changements de l’application séparés de ceux du fork CamerAwesome.
