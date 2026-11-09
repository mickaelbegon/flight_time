# Évaluation expérimentale de Nitro Camera haute fréquence

Cette branche évalue Nitro Camera sans remplacer CamerAwesome. La page
**Nitro Camera (expérimental)** est accessible depuis le menu latéral et ne
crée pas d’essai Flight Time.

## Versions verrouillées

- Flight Time : branche `experiment/nitro-camera-high-fps` ;
- Nitro Camera : fork `mickaelbegon/nitro_camera`, commit `4ece5e3` ;
- version déclarée du package : `0.0.3` ;
- Flutter local : consulter `flutter --version` au moment de chaque essai ;
- Android minimal : API 24.

Le fork est intentionnellement temporaire. Il ajoute trois informations qui ne
sont pas exposées de façon suffisante par le package publié :

1. les combinaisons exactes `taille × plage FPS` annoncées par Camera2 pour
   une session high-speed ;
2. le mode réellement négocié ;
3. les timestamps capteur collectés nativement pendant l’enregistrement.

## Format high-speed

Le backend Android utilise `CameraConstrainedHighSpeedCaptureSession`. Les
captures high-speed sont volontairement encodées comme des vidéos slow motion :
elles ont une timeline de lecture de 30 fps, sans audio. Une capture 240 fps
produit donc typiquement une lecture huit fois plus longue.

Ne jamais utiliser la position de lecture MP4 comme temps physique du saut :

```text
captureTime(frame)  = frame / captureFps
playbackPosition(frame) = frame / 30
```

Le replay de production n’est pas modifié par cette expérience.

## Vocabulaire de preuve

| Champ | Sens |
| --- | --- |
| Requested | Mode choisi par l’utilisateur. |
| Advertised | Tuple exact annoncé par Camera2. |
| Negotiated | Tuple choisi par la session native. |
| Measured | FPS déduit des timestamps `SENSOR_TIMESTAMP`. |

Un mode n’est jamais déclaré « réel » sur la seule base du FPS nominal MP4.
Une demande à 120 fps est refusée lorsqu’Android ne fournit qu’un mode dont la
cadence de capture effective est 240 fps : aucune substitution silencieuse
n’est acceptable pour Flight Time.

## Procédure Pixel 8a et Pixel 7

Pour chaque mode affiché dans la page expérimentale :

1. faire trois captures de cinq secondes en lumière forte ;
2. faire trois captures de cinq secondes en lumière intérieure ;
3. exécuter cinq captures successives pour observer une limitation thermique ;
4. utiliser une cible en mouvement pour l’analyse des duplications ;
5. noter le commit Flight Time, le commit Nitro et la version Android.

Après une capture, la fiche de l’application fournit le FPS mesuré, les
intervalles, le jitter et une estimation des frames manquantes. Pour inspecter
le conteneur MP4 sur un ordinateur :

```sh
python3 tool/analyze_nitro_capture.py /chemin/vers/video.mp4 --capture-fps 240
```

L’outil utilise `ffprobe` et `ffmpeg`. Les hashes identiques de frames sont un
signal indicatif uniquement : une scène immobile peut légitimement en contenir.

## Résultats

| Téléphone | Android | Mode annoncé | Mode négocié | FPS mesuré | Jitter | Frames manquantes | Résultat |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Pixel 8a | à compléter | à compléter | à compléter | à compléter | à compléter | à compléter | à compléter |
| Pixel 7 | à compléter | à compléter | à compléter | à compléter | à compléter | à compléter | à compléter |

## Critère de décision

Nitro peut rester expérimental seulement si les résultats matériels confirment
le mode négocié, une cadence mesurée proche de la cadence demandée et une
stabilité acceptable sur plusieurs essais. Une intégration de production
nécessitera ensuite une évolution de modèle séparée vers `startFrame`,
`endFrame` et `captureFps`.
