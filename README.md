# GUI EMG KIN2024

Interface pédagogique d'acquisition et de visualisation d'électromyographie
de surface (EMG) sur deux canaux. Le projet est destiné à des étudiants en
kinésiologie qui découvrent le signal EMG, la normalisation par contraction
volontaire maximale (MVC) et l'interprétation d'une activation musculaire.

Le mode `TEST`, activé au démarrage de l'application Python, permet de faire
une première séance sans capteur ni carte d'acquisition. Le mode matériel est
prévu pour une carte Measurement Computing (MCC) configurée avec InstaCal.

> Ce logiciel est un outil d'enseignement et d'exploration du signal. Il ne
> constitue pas un dispositif médical ni un outil de diagnostic.

## Objectifs pédagogiques

Après une prise en main, l'étudiant devrait pouvoir :

- distinguer un signal EMG brut de son enveloppe d'amplitude;
- observer des bouffées d'activité associées à une contraction;
- comprendre pourquoi une MVC permet d'exprimer l'activité en `%MVC`;
- comparer qualitativement l'activation de deux muscles ou deux canaux;
- exporter des données afin de poursuivre l'analyse dans un tableur ou un
  script scientifique.

## Fonctionnalités actuelles

### Applications Python

Deux frontends partagent le même traitement et le même accès MCC :

- affichage simultané de deux entrées analogiques, de `AI0-AI1` à `AI6-AI7`;
- mode `TEST` simulant deux muscles et une perturbation secteur à 60 Hz;
- acquisition à `2000 Hz` avec fenêtre d'affichage glissante de `5 s`;
- parcours `GUIDE` indiquant les étapes MVC, enregistrement et export;
- mesure MVC séparée pour chaque canal pendant `5 s`;
- rejet de 60 Hz, passe-bande `20-400 Hz` et enveloppe RMS normalisée par MVC;
- alertes de saturation, bruit secteur, signal faible et MVC insuffisante;
- capture webcam synchronisée à l'enregistrement EMG et relecture avec
  curseur temporel;
- affichage en direct par canal, puis superposition des deux courbes après
  l'arrêt de l'enregistrement;
- export de la figure en PNG et du dernier enregistrement en CSV.

`EMG_GUI_diligent.py` conserve une interface Matplotlib simple. Pour les
séances temps réel, `EMG_GUI_pyqtgraph.py` fournit une interface Qt/PyQtGraph
avec commandes plus grandes, rendu graphique plus fluide et lecteur vidéo
intégré à droite des courbes.

### Version MATLAB

`EMG_GUI_digilent.m` fournit une autre interface avec mode simulation,
acquisition MCC via l'assemblage `.NET` `MccDaq`, export et traitement
incluant un rejet de 60 Hz, un passe-bande `20-400 Hz` et une enveloppe RMS.
Elle demarre en mode materiel; la case `Mode TEST (simulation)` en bas a
gauche permet d'activer explicitement les signaux simules.
Le bouton `Bilan installations` evalue au demarrage les composants disponibles
et indique les toolboxes, support packages ou pilotes MCC a installer.
Elle propose un positionnement webcam de `5 s`, puis déclenche ensemble la
vidéo et l'EMG. La relecture est liée aux graphiques par un curseur temporel
et un panneau compare le contenu fréquentiel des deux signaux. Un checkbox
permet d'activer ou désactiver les notch filters de `60 Hz` et de ses
harmoniques (`120` à `360 Hz`).

## Installation MATLAB sur Windows

### Mode TEST sans matériel

Le mode `TEST` peut être utilisé sans carte MCC et sans webcam. Installer :

1. MATLAB;
2. **Signal Processing Toolbox**, utilisé pour le filtrage EMG et l'analyse
   fréquentielle (`butter`, `filtfilt`, `pwelch`).

Dans MATLAB, placer le dossier du projet dans le chemin courant, puis lancer :

```matlab
EMG_GUI_digilent
```

L'interface tente par defaut de se connecter a la carte MCC. Pour travailler
sans materiel, cocher `Mode TEST (simulation)` en bas a gauche apres
l'ouverture; les acquisitions suivantes utilisent alors les signaux simules.

### Webcam facultative

Pour activer le positionnement et l'enregistrement vidéo, installer
**MATLAB Support Package for USB Webcams** :

1. Dans MATLAB, ouvrir `Home > Add-Ons > Get Hardware Support Packages`.
2. Choisir `MATLAB Support Package for USB Webcams` dans la catégorie
   caméras/imagerie et terminer l'installation.
3. Autoriser l'accès de MATLAB à la caméra dans les paramètres de
   confidentialité Windows si nécessaire.
4. Vérifier l'installation dans MATLAB :

```matlab
webcamlist
cam = webcam;
snapshot(cam);
clear cam
```

Documentation officielle :
[MathWorks - Install the MATLAB Support Package for USB Webcams](https://www.mathworks.com/help/imaq/install-the-matlab-support-package-for-usb-webcams.html).

### Vidéo parallèle à l'acquisition EMG

La fonction `webcam` seule fournit des images par appels `snapshot`; elle ne
permet pas à cette interface de journaliser la vidéo indépendamment de la
boucle analogique. Pour enregistrer la vidéo en parallèle de l'acquisition
MCC, installer également :

1. **Image Acquisition Toolbox**;
2. **Image Acquisition Toolbox Support Package for OS Generic Video
   Interface**, qui fournit l'adaptateur Windows `winvideo`.

Après installation, vérifier dans MATLAB :

```matlab
info = imaqhwinfo;
assert(any(strcmpi(info.InstalledAdaptors,'winvideo')))
```

Lorsque `winvideo` est disponible, l'interface choisit automatiquement
`videoinput` avec un `DiskLogger`: la caméra écrit la vidéo sur disque en
arrière-plan pendant que la boucle MCC collecte le signal analogique. Sans cet
adaptateur, la capture `webcam` reste disponible en repli horodaté.

Documentation officielle :
[MathWorks - Installer les adaptateurs Image Acquisition Toolbox](https://www.mathworks.com/help/imaq/installing-the-support-packages-for-image-acquisition-toolbox-adaptors.html)
et
[MathWorks - Logging Image Data to Disk](https://www.mathworks.com/help/imaq/logging-image-data-to-disk.html).

### Carte MCC USB-1208FS-PLUS

L'acquisition matérielle MATLAB utilise l'assembly `.NET` `MccDaq`. Sur le
poste Windows d'acquisition :

1. Installer **Universal Library for Windows** de Digilent/MCC, avec les
   composants `.NET`, ainsi que **InstaCal**.
2. Brancher la carte, ouvrir InstaCal, détecter ou ajouter la carte, puis
   l'affecter au numéro `0` (`Board Number 0`).
3. Relancer MATLAB et vérifier la DLL puis l'accès analogique :

```matlab
load_mccdaq_assembly
test_api
```

Téléchargement et instructions officiels :
[Digilent - Universal Library](https://digilent.com/shop/universal-library/)
et
[Digilent/MCC - Getting Started](https://files.digilent.com/manuals/Mcculw_WebHelp/Users_Guide/Overview/GetStarted.htm).

## Ce que l'on observe

L'application Python affiche quatre graphiques :

| Graphique | Interprétation |
| --- | --- |
| `EMG1 brut`, `EMG2 brut` | tension enregistrée en volts; le signal oscille rapidement autour de zéro |
| `EMG1/EMG2 enveloppe RMS` ou `enveloppe normalisée` | enveloppe donnant une lecture plus simple de l'intensité d'activation |

Une valeur en `%MVC` n'est interprétable qu'après avoir mesuré la MVC du
canal correspondant. Avant cette étape, la courbe inférieure représente
l'enveloppe non normalisée et l'axe indique `Enveloppe RMS (V)`.

Dans les deux versions, la courbe d'enveloppe est calculée après rejet de
`60 Hz` et passe-bande EMG `20-400 Hz`, puis lissée par RMS sur `100 ms`.
L'axe reste en volts avant une MVC valide et passe en `%MVC` uniquement après
calibration du canal.

Dans l'application MATLAB, le menu `Apres Stop` propose deux lectures :

- `EMG1 + EMG2` conserve la comparaison des deux signaux;
- `Brut + filtre` superpose, pour chaque canal, le signal brut transparent et
  le signal passe-bande/notch filtre en volts. Dans ce mode, l'analyse
  frequentielle affiche egalement les spectres filtres des deux canaux.

La superposition est volontairement reservee au post-traitement, apres
`Stop`. Pendant l'acquisition, chaque graphique affiche uniquement son canal
afin de limiter le travail graphique et les risques de retard.

La ligne `Qualite` associe les problemes detectes a une action pratique :
saturation -> reduire l'amplification ou le gain; signal faible -> verifier
les electrodes et les cables; bruit `60 Hz` -> verifier la masse et
l'alimentation; MVC faible -> recommencer la contraction maximale.

Le bouton `Bilan installations` rappelle les prerequis absents pour
l'acquisition analogique (`MccDaq` / InstaCal), la webcam, la video parallele
`winvideo` et le traitement frequentiel.

## Démarrage rapide en mode TEST

### Prérequis

- Python `3.10` recommandé par `environment.yml`;
- Conda ou Miniconda;
- un environnement avec `numpy` et `matplotlib`.

Sur un poste Windows de laboratoire où le pilote MCC doit aussi être utilisé :

```bash
conda env create -f environment.yml
conda activate emg_mcc
python EMG_GUI_diligent.py
```

Pour le frontend temps réel recommandé en laboratoire :

```bash
python EMG_GUI_pyqtgraph.py
```

Pour explorer seulement le mode simulé sur un poste qui ne possède pas les
outils MCC, on peut créer un environnement plus léger :

```bash
conda create -n emg_test python=3.10 numpy matplotlib
conda activate emg_test
python EMG_GUI_diligent.py
```

### Première manipulation suggérée

1. Lancer `python EMG_GUI_diligent.py`. La case `TEST` doit être cochée.
2. Cliquer sur `MVC 1`, attendre 5 secondes, puis faire la même chose avec
   `MVC 2`.
3. Cliquer sur `Enregistrer` et observer les activations simulées des deux
   canaux.
4. Arrêter l'enregistrement après environ 5 secondes en mode `TEST`.
5. Comparer les enveloppes en `%MVC` et exporter le résultat avec
   `Exporter CSV` ou `Exporter PNG`.

Le scénario simulé contient des périodes d'activation différentes sur EMG1
et EMG2. Il est volontairement simple afin de servir à l'explication en
classe. Dans l'implémentation actuelle, il contient `5 s` de données
d'enregistrement; une acquisition simulée plus longue produit ensuite des
zéros.

### Capture vidéo

Dans l'application MATLAB, le clic sur `Enregistrer` affiche d'abord la camera
pendant `5 s` pour permettre le placement lorsque `Placement camera 5 s` est
coche. Cette attente est intentionnelle; decocher la case permet un depart
immediat lors des essais suivants. A la fin du compte a rebours,
l'EMG et la vidéo sont déclenchés depuis une horloge commune. La vidéo n'est
pas redessinée pendant l'acquisition afin de préserver les ressources. Après
`Stop`, le curseur vertical des graphiques et le lecteur vidéo utilisent les
horodatages capturés. Si aucune webcam n'est accessible, l'enregistrement EMG
continue sans vidéo et un message l'indique.

- Python : la capture utilise `opencv`, inclus dans `environment.yml`.
- MATLAB : la capture utilise `webcam` et nécessite le support package
  **MATLAB Support Package for USB Webcams**.
- MATLAB : l'acquisition vidéo réellement indépendante de la boucle EMG
  nécessite `Image Acquisition Toolbox` et l'adaptateur `winvideo`.
- Avec `winvideo`, la video est journalisee par `videoinput` en parallele de
  la boucle EMG. En repli `webcam`, les images sont prises dans la boucle
  d'acquisition : il ne s'agit pas de deux threads independants et des
  retards peuvent apparaître.
- La synchronisation MATLAB repose sur les horodatages logiciels de capture;
  elle améliore fortement l'alignement pédagogique, mais ne remplace pas un
  déclencheur matériel pour une analyse biomécanique de précision.

## Utilisation avec une carte MCC

Le dépôt, les interfaces Python et MATLAB ciblent une MCC USB-1208FS-PLUS.
Le modèle réellement disponible au laboratoire doit néanmoins être confirmé
avant une séance avec matériel.

Pour préparer le poste et démarrer :

1. Installer les pilotes Measurement Computing et InstaCal sur le poste
   Windows utilisé pour l'acquisition.
2. Configurer et vérifier la carte dans InstaCal comme carte numéro `0`.
3. Installer l'environnement `emg_mcc` avec `environment.yml`, qui inclut
   `mcculw`.
4. Connecter les signaux aux deux entrées choisies dans l'interface.
5. Décocher `TEST`, sélectionner la paire `AIx-AIy`, effectuer les MVC, puis
   enregistrer.

La plage d'acquisition configurée dans le script Python est `+/- 5 V`
(`BIP5VOLTS`). Toute séance avec de vraies électrodes doit suivre les
procédures du laboratoire concernant préparation de la peau, placement,
amplification, sécurité électrique et consentement.

### Dépannage MATLAB : `MccDaq` introuvable

Le message `MccDaq could not be found in the .NET global assembly cache`
signifie que MATLAB n'a pas trouvé l'assembly `.NET` de Measurement Computing
par son nom. Il apparaît lorsque le mode matériel est activé et que
Universal Library for .NET n'est pas installée, ou lorsque `MccDaq.dll` est
installée localement mais n'est pas enregistrée dans le cache global `.NET`.

La version MATLAB utilise `load_mccdaq_assembly.m`, qui essaie
automatiquement le cache global puis les emplacements usuels :

- `C:\Program Files\Measurement Computing\DAQ\MccDaq.dll`;
- `C:\Program Files (x86)\Measurement Computing\DAQ\MccDaq.dll`.

Sur le poste d'acquisition :

1. Vérifier que `.NET Framework 4.0` ou plus récent est installé, puis
   installer Measurement Computing Universal Library avec la prise en charge
   `.NET` et InstaCal.
2. Configurer la carte comme carte `0` dans InstaCal.
3. Dans MATLAB, exécuter `load_mccdaq_assembly` pour vérifier le chargement.
4. Si la DLL est installée dans un autre dossier, définir son répertoire avec
   `setenv('MCCDAQ_DIR', 'C:\chemin\vers\DAQ')`, puis relancer la commande.

### Dépannage MATLAB : erreur `AIn 126`

L'erreur `AIn: err=126` indique que la DLL MCC est chargée, mais que Universal
Library ne trouve pas le fichier de configuration `CB.CFG`. Ce fichier est
créé ou mis à jour par InstaCal et contient notamment l'association entre la
carte connectée et son numéro de carte (`0` dans cette application).

1. Fermer MATLAB.
2. Brancher la carte MCC.
3. Ouvrir InstaCal et vérifier que la carte est détectée.
4. Ajouter/configurer la carte comme `Board Number 0`, puis quitter InstaCal.
5. Relancer MATLAB et exécuter `test_api`, puis l'interface.

Si l'erreur persiste, vérifier que l'installation MCC utilisée par MATLAB est
la même que celle qui a installé et lancé InstaCal, et rechercher `CB.CFG`
dans le dossier d'installation Measurement Computing.

## Export des résultats

Dans l'application Python, les fichiers sont écrits dans le dossier depuis
lequel le programme a été lancé :

- `emg_graphs_YYYYMMDD_HHMMSS.png` : capture des graphiques affichés;
- `emg_last_YYYYMMDD_HHMMSS.csv` : dernier enregistrement arrêté.
- `emg_video_YYYYMMDD_HHMMSS.mp4` : vidéo enregistrée avec le mode webcam.
- `emg_video_YYYYMMDD_HHMMSS.avi` : vidéo enregistrée en parallèle avec `winvideo`.

Le CSV contient les colonnes suivantes :

| Colonne | Contenu |
| --- | --- |
| `time_s` | temps en secondes |
| `emg1_raw_V`, `emg2_raw_V` | signaux bruts en volts |
| `emg1_env_pctMVC`, `emg2_env_pctMVC` | enveloppes RMS lorsque les MVC correspondantes ont été mesurées |
| `emg1_env_V`, `emg2_env_V` | nom utilisé pour un canal exporté sans MVC valide en mode libre |

## Structure du dépôt

| Fichier | Rôle |
| --- | --- |
| `EMG_GUI_diligent.py` | interface Python Matplotlib, traitement et acquisition |
| `EMG_GUI_pyqtgraph.py` | interface Python Qt/PyQtGraph pour le temps réel |
| `EMG_GUI_digilent.m` | variante MATLAB |
| `environment.yml` | environnement Conda Python avec dépendance MCC |
| `test_daq.py`, `test2.py` | essais simples d'accès à la carte avec `mcculw` |
| `test_processing.py` | tests sans matériel du filtrage et du contrôle qualité |
| `test_affichage.py` | prototype de rafraîchissement de l'affichage |
| `test_api.m`, `test_wrapper.m` | essais de connexion MCC côté MATLAB |
| `tests/test_EMG_GUI_digilent.m` | tests MATLAB sans matériel de mise en page et d'analyse fréquentielle |
| `load_mccdaq_assembly.m` | chargement robuste et diagnostic de la DLL MCC pour MATLAB |
| `usb-1208fs-plus-users-guide.pdf` | documentation de la carte d'acquisition |

## Limites connues

- Le balayage matériel MCC utilise les API `a_in_scan`/`AInScan`; un repli en
  lecture ponctuelle reste prévu si un pilote ancien ne supporte pas ce mode.
- La simulation Python est limitée à un essai de 5 secondes.
- Les exports Python ne sauvegardent pas encore les métadonnées d'une séance
  (muscles, participant, placement, condition et valeurs MVC).
- La version MATLAB horodate les images et les blocs EMG à partir d'un départ
  logiciel commun; une synchronisation matérielle reste nécessaire pour une
  mesure cinématique image par image.
- L'acquisition analogique MATLAB utilise actuellement des scans successifs,
  pas un buffer continu en arriere-plan. L'interface signale un retard de
  bloc superieur a `20 ms`; pour reduire ce risque, utiliser `winvideo` ou
  enregistrer sans video de repli `webcam`.
- Les scripts `test_*.py` interrogent le matériel directement et ne sont pas
  des tests automatisés exécutables sans carte MCC.

## Proposition de séance d'introduction

1. Présenter le bruit de fond, une bouffée EMG et l'influence de la MVC en
   utilisant le mode `TEST`.
2. Demander aux étudiants de repérer les intervalles d'activation EMG1 et
   EMG2 sur les signaux bruts, puis sur les enveloppes.
3. Exporter le CSV et calculer une moyenne de `%MVC` sur une période choisie.
4. En laboratoire, répéter avec un mouvement simple et deux muscles en
   documentant le placement des électrodes et la consigne MVC.

## Feuille de route proposée

Ces améliorations visent d'abord la compréhension par des étudiants qui
découvrent l'EMG, puis la robustesse d'une utilisation en laboratoire.

| Priorité | Axe | Bénéfice attendu |
| --- | --- | --- |
| 1 | Parcours guidé `Préparer -> MVC -> Enregistrer -> Interpréter -> Exporter` | Implémenté dans Python et MATLAB |
| 2 | Axe affiché en volts avant la MVC, puis en `%MVC` après calibration | Implémenté dans Python et MATLAB |
| 3 | Rejet de 60 Hz et passe-bande EMG dans l'application Python | Implémenté et harmonisé avec MATLAB |
| 4 | Acquisition MCC scannée avec tampon circulaire | Implémenté avec repli compatible |
| 5 | Alertes de saturation, bruit élevé et MVC insuffisante | Implémenté dans Python et MATLAB |
| 6 | Scénarios `TEST` plus longs et annotés | Permet d'enseigner bruit, coactivation et artefacts sans matériel |
| 7 | Interface Qt/PyQtGraph avec commandes agrandies | Frontend Python temps réel disponible |
| 8 | Métadonnées de séance dans les exports | Rend les fichiers exploitables et traçables lors des travaux pratiques |
| 9 | Sélection d'une période et statistiques simples de `%MVC` | Relie immédiatement le tracé à une question d'analyse |
| 10 | Tests automatisés et diagnostic de connexion MCC | Sécurise les évolutions et réduit les problèmes de démarrage |

Les priorités `1`, `2`, `3`, `4`, `5` et `7` forment maintenant le premier
lot implémenté. Les priorités restantes portent sur les scénarios
pédagogiques, les métadonnées et l'analyse de périodes choisies.

## Développement

Pour vérifier rapidement la syntaxe du programme principal :

```bash
python -m py_compile EMG_GUI_diligent.py EMG_GUI_pyqtgraph.py
python -m unittest -v test_processing.py
```

Pour vérifier l'interface MATLAB sans webcam et sans carte MCC :

```matlab
results = runtests('tests/test_EMG_GUI_digilent.m');
assertSuccess(results);
```

Ces tests contrôlent notamment les espaces réservés aux titres et labels, le
bouton de lecture vidéo placé devant le curseur, la détection de fréquences
connues sur les deux voies et le rejet optionnel de `60 Hz` et de ses
harmoniques.

Les paramètres principaux (`FS`, durée MVC, taille de fenêtre RMS et cadence
d'affichage) se trouvent au début de `EMG_GUI_diligent.py`.
