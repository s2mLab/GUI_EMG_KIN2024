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

### Application Python

Le fichier principal est `EMG_GUI_diligent.py`.

- affichage simultané de deux entrées analogiques, de `AI0-AI1` à `AI6-AI7`;
- mode `TEST` simulant deux muscles et une perturbation secteur à 60 Hz;
- acquisition à `2000 Hz` avec fenêtre d'affichage glissante de `5 s`;
- mesure MVC séparée pour chaque canal pendant `5 s`;
- affichage du signal brut et d'une enveloppe RMS normalisée par la MVC;
- affichage en direct par canal, puis superposition des deux courbes après
  l'arrêt de l'enregistrement;
- export de la figure en PNG et du dernier enregistrement en CSV.

### Version MATLAB

`EMG_GUI_digilent.m` fournit une autre interface avec mode simulation,
acquisition MCC via l'assemblage `.NET` `MccDaq`, export et traitement
incluant un rejet de 60 Hz, un passe-bande `20-400 Hz` et une enveloppe RMS.
Elle demande une installation MATLAB et MCC compatible sur le poste de
laboratoire.

## Ce que l'on observe

L'application Python affiche quatre graphiques :

| Graphique | Interprétation |
| --- | --- |
| `EMG1 brut`, `EMG2 brut` | tension enregistrée en volts; le signal oscille rapidement autour de zéro |
| `EMG1 filtré (normalisé)`, `EMG2 filtré (normalisé)` | enveloppe RMS donnant une lecture plus simple de l'intensité d'activation |

Une valeur en `%MVC` n'est interprétable qu'après avoir mesuré la MVC du
canal correspondant. Avant cette étape, la courbe inférieure représente
l'enveloppe non normalisée, même si l'axe conserve l'étiquette `%MVC`.

Dans la version Python actuelle, la courbe appelée `filtré` repose sur une
enveloppe RMS de `100 ms` et un retrait adaptatif de la moyenne. Elle
n'applique pas encore le rejet de 60 Hz ni le passe-bande EMG que l'on trouve
dans la version MATLAB.

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

## Utilisation avec une carte MCC

Le dépôt contient le manuel d'une MCC USB-1208FS-PLUS et la version MATLAB
nomme ce modèle. L'en-tête du script Python mentionne toutefois une
USB-1206FS-PLUS : le modèle réellement disponible au laboratoire doit être
confirmé avant une séance avec matériel.

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

## Export des résultats

Dans l'application Python, les fichiers sont écrits dans le dossier depuis
lequel le programme a été lancé :

- `emg_graphs_YYYYMMDD_HHMMSS.png` : capture des graphiques affichés;
- `emg_last_YYYYMMDD_HHMMSS.csv` : dernier enregistrement arrêté.

Le CSV contient les colonnes suivantes :

| Colonne | Contenu |
| --- | --- |
| `time_s` | temps en secondes |
| `emg1_raw_V`, `emg2_raw_V` | signaux bruts en volts |
| `emg1_env_pctMVC`, `emg2_env_pctMVC` | enveloppes RMS; en `%MVC` seulement si les MVC ont été mesurées |

## Structure du dépôt

| Fichier | Rôle |
| --- | --- |
| `EMG_GUI_diligent.py` | interface Python principale et simulation |
| `EMG_GUI_digilent.m` | variante MATLAB |
| `environment.yml` | environnement Conda Python avec dépendance MCC |
| `test_daq.py`, `test2.py` | essais simples d'accès à la carte avec `mcculw` |
| `test_affichage.py` | prototype de rafraîchissement de l'affichage |
| `test_api.m`, `test_wrapper.m` | essais de connexion MCC côté MATLAB |
| `usb-1208fs-plus-users-guide.pdf` | documentation de la carte d'acquisition |

## Limites connues

- Le backend matériel Python lit actuellement les échantillons un par un;
  il n'exploite pas encore un balayage matériel avec tampon circulaire.
- Le traitement Python ne possède pas encore le pipeline classique
  rejet secteur plus passe-bande EMG présent en MATLAB.
- Le modèle de carte MCC nommé dans le script Python n'est pas cohérent avec
  le manuel inclus et doit être harmonisé.
- La simulation Python est limitée à un essai de 5 secondes.
- Les exports Python ne sauvegardent pas encore les métadonnées d'une séance
  (muscles, participant, placement, condition et valeurs MVC).
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
| 1 | Parcours guidé `Préparer -> MVC -> Enregistrer -> Interpréter -> Exporter` | Réduit les erreurs de manipulation lors d'une première séance |
| 2 | Axe affiché en volts avant la MVC, puis en `%MVC` après calibration | Évite de présenter comme normalisée une enveloppe qui ne l'est pas encore |
| 3 | Rejet de 60 Hz et passe-bande EMG dans l'application Python | Rapproche la démonstration des pratiques de traitement expliquées en cours |
| 4 | Acquisition MCC scannée avec tampon circulaire | Améliore la régularité de l'échantillonnage et la fluidité de l'affichage |
| 5 | Alertes de saturation, bruit élevé et MVC insuffisante | Donne un retour immédiat sur la qualité du signal |
| 6 | Scénarios `TEST` plus longs et annotés | Permet d'enseigner bruit, coactivation et artefacts sans matériel |
| 7 | Interface Qt/PyQtGraph avec commandes agrandies | Facilite l'usage en salle de laboratoire et le temps réel |
| 8 | Métadonnées de séance dans les exports | Rend les fichiers exploitables et traçables lors des travaux pratiques |
| 9 | Sélection d'une période et statistiques simples de `%MVC` | Relie immédiatement le tracé à une question d'analyse |
| 10 | Tests automatisés et diagnostic de connexion MCC | Sécurise les évolutions et réduit les problèmes de démarrage |

Un premier lot d'implémentation raisonnable regrouperait les priorités `1`,
`2`, `3` et `4` : elles améliorent à la fois la pédagogie, la validité de
l'interprétation et les performances en acquisition réelle.

## Développement

Pour vérifier rapidement la syntaxe du programme principal :

```bash
python -m py_compile EMG_GUI_diligent.py
```

Les paramètres principaux (`FS`, durée MVC, taille de fenêtre RMS et cadence
d'affichage) se trouvent au début de `EMG_GUI_diligent.py`.
