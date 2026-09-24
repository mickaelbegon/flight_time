# APK Android avec GitHub Actions

Le workflow `.github/workflows/android.yml` s’exécute sur chaque push et pull
request vers `main`. Il récupère les dépendances Flutter, lance l’analyse et
les tests, construit un APK debug, puis le rend téléchargeable dans la section
**Artifacts** de l’exécution GitHub Actions.

L’artifact debug est conservé 14 jours. Il est destiné aux essais internes et
ne doit pas être diffusé comme version de production.

## Publication d’une release

Pousser un tag qui commence par `v`, par exemple `v1.0.3`, lance après les
tests un second job. Il construit un APK release signé, le conserve 90 jours
comme artifact et l’ajoute à la GitHub Release associée au tag.

Avant le premier tag, configurer dans le fork GitHub les secrets suivants,
sous **Settings → Secrets and variables → Actions** :

- `ANDROID_KEYSTORE_BASE64` : contenu Base64 du fichier `.jks` ;
- `ANDROID_KEYSTORE_PASSWORD` : mot de passe du keystore ;
- `ANDROID_KEY_ALIAS` : alias de la clé ;
- `ANDROID_KEY_PASSWORD` : mot de passe de la clé.

Pour créer la valeur Base64 sur macOS sans ajouter le keystore au dépôt :

```sh
base64 < android/app/upload-keystore.jks | tr -d '\n'
```

La commande de publication est ensuite :

```sh
git tag v1.0.3
git push fork v1.0.3
```

Sans ces quatre secrets, un tag échoue volontairement au moment de la
signature, sans publier d’APK non signé.
