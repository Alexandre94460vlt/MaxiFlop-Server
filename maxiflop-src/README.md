# MAXIFLOP — Jeu de Rythme (Solo)
*Inspiré de Osu! Taiko*

## Structure du projet

```
maxiflop/
├── project.godot          ← Ouvrir avec Godot 4.4
├── scenes/
│   ├── MainMenu.tscn      ← Écran d'accueil
│   ├── GameScreen.tscn    ← Scène de jeu principale
│   └── Note.tscn          ← Scène d'une note (préfab)
├── scripts/
│   ├── GameManager.gd     ← Singleton (Autoload)
│   ├── GameScreen.gd      ← Contrôleur principal
│   ├── NoteSpawner.gd     ← Spawn + beatmap
│   ├── HitZone.gd         ← Détection d'input/hit
│   ├── Note.gd            ← Comportement d'une note
│   └── MainMenu.gd        ← Menu principal
└── assets/                ← Musiques, fonts, sprites...
```

## Installation

1. Ouvrir **Godot 4.4**
2. Importer le dossier `maxiflop/`
3. Dans **Projet → Paramètres du projet → Autoload**, ajouter :
   - Script : `res://scripts/GameManager.gd`
   - Nom : `GameManager`
4. Lancer le projet (`F5`)

## Contrôles

| Touche | Action |
|--------|--------|
| `A` | Frapper note **Bleue** |
| `S` | Frapper note **Jaune** |
| `D` | Frapper note **Rouge** |
| `Échap` | Retour au menu |

## Système de score

| Précision | Points |
|-----------|--------|
| **PERFECT** (< 80ms) | 300 pts |
| **GOOD** (< 150ms) | 100 pts |
| **BAD** (< 250ms) | 50 pts |
| **MISS** | 0 pts |

### Multiplicateurs de combo
- Combo ≥ 5 → **×2**
- Combo ≥ 10 → **×3**
- Combo ≥ 20 → **×4**

## Ajouter de la musique

1. Importer un fichier `.ogg` ou `.wav` dans `assets/`
2. Dans la scène `GameScreen.tscn`, sélectionner le nœud `MusicPlayer`
3. Assigner le stream audio
4. Adapter `song_duration` dans le script `GameScreen.gd`




## Mode multijoueur (host PC + manettes smartphone)

### 1) Lancer le serveur

Depuis la racine du repo :

```bash
cd maxiflop-server
npm install
npm start
```

Le serveur expose :
- `http://<ip-du-pc>:8080` : page manette smartphone
- `ws://<ip-du-pc>:8080/ws` : websocket utilisé par Godot + smartphone

### 2) Lancer Godot

Ouvrir `maxiflop-src` dans Godot 4.4.1 puis lancer la scène principale.

### 3) Rejoindre depuis téléphone

Connecter les téléphones au même réseau local, puis ouvrir l'URL affichée à droite de l'écran de jeu.

Fonctionnement :
- les appuis (`bleu/jaune/rouge`) sont envoyés au host;
- le host valide le timing des notes;
- le score est renvoyé à chaque manette;
- le classement Top 5 et les scores d'équipe sont affichés sur l'écran principal.
