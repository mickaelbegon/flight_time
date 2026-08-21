# Migration Android vers Built-in Kotlin

Flutter 3.44 prépare la prise en charge de **Built-in Kotlin** d'Android Gradle
Plugin (AGP). L'ancien chargement explicite de `kotlin-android` sera retiré par
AGP 9.

## État de cette branche

L'application n'applique plus le plugin Kotlin explicitement. Le plugin Gradle
Flutter le fournit à travers AGP, ce qui conserve la compilation de
`MainActivity.kt` tout en supprimant la configuration Kotlin héritée du projet.

`camerawesome` 2.5.0 applique encore Kotlin par son ancien build Gradle. En
attendant une correction en amont, l'application dépend temporairement du fork
[`mickaelbegon/CamerAwesome`](https://github.com/mickaelbegon/CamerAwesome), au
commit `28f938f1e7e24226ef2e3d27e2e35840351d81af`.

Le patch du fork est volontairement minimal : il retire uniquement le
`buildscript` Kotlin hérité et l'application explicite de `kotlin-android` du
module Android. Il ne modifie ni CameraX, ni la capture, ni les API Dart de
CamerAwesome.

## Sortie de la solution temporaire

Lorsque CamerAwesome publiera une version compatible Built-in Kotlin, remplacer
l'override Git par cette version publiée puis supprimer le bloc
`dependency_overrides` correspondant dans `pubspec.yaml`.

D'autres dépendances Android peuvent encore utiliser l'ancien mécanisme. Elles
doivent être traitées indépendamment, après validation de leur propre migration.
