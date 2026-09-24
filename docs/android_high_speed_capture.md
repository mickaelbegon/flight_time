# Capture vidéo Android à haute fréquence

L’écran de caméra Android permet de choisir 30, 60, 120 ou 240 fps. Le choix
est mémorisé localement et recrée la session caméra afin qu’il soit appliqué à
la prochaine capture.

Les cadences supérieures à 30 fps sont transmises à CamerAwesome comme une
demande de session CameraX `HighSpeedVideoSessionConfig`. Le plugin ne démarre
cette session que lorsque la caméra arrière annonce une plage exacte, par
exemple `[120, 120]` ou `[240, 240]`, pour la configuration 1080p utilisée par
la capture haute vitesse.

Si la caméra, la résolution ou la cadence demandée n’est pas compatible, le
plugin revient à la session vidéo CameraX standard. Le mode standard ne
garantit donc pas que la cadence demandée soit atteinte : il
faut choisir manuellement dans l’écran de replay la cadence réellement
enregistrée lorsque le téléphone a effectué ce repli.

## Validation initiale

Le Pixel 8a a été validé en 1080p à 240 fps avec une session Android
`CONSTRAINED_HIGH_SPEED`. Le MP4 obtenu indiquait une cadence nominale de
240,03 fps sur une vidéo de 3,91 s, et se relisait correctement dans
Flight Time.

## Limites

- Les combinaisons résolution/cadence sont propres à chaque caméra Android.
- Cette étape ne modifie pas encore le modèle de données : les essais existants
  restent compatibles, mais la cadence de capture n’est pas enregistrée avec
  la vidéo.
- La capture audio, le multi-capteur et l’analyse d’image restent exclus des
  sessions haute vitesse par les contraintes CameraX.
