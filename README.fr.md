# claude-cage

🇫🇷 Français · [🇬🇧 English](README.md)

Un flake Nix qui lance [Claude Code](https://claude.com/claude-code) dans un bac à sable ([bubblewrap](https://github.com/containers/bubblewrap)) : Claude ne voit et ne peut modifier que le répertoire de votre projet.

## Principe

Le flake fournit une commande `claude` qui remplace le binaire habituel. Au lieu de lancer Claude Code directement, elle l'exécute dans un conteneur `bwrap` avec :

- **Système de fichiers isolé** : seuls `/nix/store` (lecture seule), quelques fichiers `/etc` (`resolv.conf`, `hosts`, `passwd`, `group`, en lecture seule) et la racine du projet (lecture/écriture) sont visibles. Votre `$HOME`, vos clés SSH, vos autres projets, etc. sont **inaccessibles**.
- **Environnement vierge** (`--clearenv`) : aucune variable d'environnement de l'hôte n'est transmise (tokens, clés d'API…). Seules les variables nécessaires sont définies.
- **Réseau conservé** : Claude peut joindre l'API d'Anthropic (`--share-net`).
- **Fichiers sensibles protégés** : `flake.nix`, `flake.lock`, `.envrc`, `.git/hooks` et `.git/config` sont montés en **lecture seule**, pour que Claude ne puisse pas modifier la cage elle-même ni installer de hook git qui s'exécuterait hors du bac à sable.
- **Processus lié au parent** (`--die-with-parent`, `--new-session`) : la cage se ferme avec votre terminal.
- **`$HOME` factice** : `/home/sandbox` est un tmpfs vide, et `/tmp` aussi.

La configuration de Claude (connexion, historique, paramètres) est conservée dans `~/.local/state/claude-cage` (ou `$XDG_STATE_HOME/claude-cage`) et montée dans la cage sous `/claude-config`. Vous n'avez donc à vous connecter qu'une seule fois, et cette configuration est partagée entre tous vos projets utilisant claude-cage.

## Prérequis

- Linux (`x86_64-linux` ou `aarch64-linux`)
- [Nix](https://nixos.org/download) avec les *flakes* activés (`experimental-features = nix-command flakes`)
- Les *user namespaces* non privilégiés doivent être autorisés (c'est le cas par défaut sur la plupart des distributions)
- Recommandé : [direnv](https://direnv.net/) (et [nix-direnv](https://github.com/nix-community/nix-direnv))

> Le paquet `claude-code` est non libre ; le flake l'autorise explicitement via `allowUnfreePredicate`, vous n'avez rien à configurer.

## Utilisation

### Avec direnv (recommandé)

Le dépôt contient déjà un `.envrc` :

```
use flake
```

1. Placez `flake.nix` et `flake.lock` (et le `.envrc`) à la racine du projet à protéger.
2. Autorisez direnv :
   ```sh
   direnv allow
   ```
3. En entrant dans le répertoire, direnv charge le shell de développement : la commande `claude` de la cage est placée dans votre `PATH` et la variable `CLAUDE_CAGE_ROOT` est positionnée sur la racine du projet.
4. Lancez simplement :
   ```sh
   claude
   ```
   Vous verrez s'afficher `claude-cage: confined to /chemin/du/projet`.

Vous pouvez lancer `claude` depuis la racine **ou depuis n'importe quel sous-dossier** du projet. Tous les arguments sont transmis à Claude Code (`claude --resume`, `claude -p "..."`, etc.).

### Sans direnv

```sh
nix develop      # ouvre un shell avec la commande `claude` confinée
claude
```

La racine du projet est alors le répertoire courant au moment du `nix develop`. Lancez-le donc depuis la racine.

### Depuis un autre projet, sans copier le flake

```sh
nix develop /chemin/vers/claude-cage
```

> `CLAUDE_CAGE_ROOT` correspond alors au répertoire courant au moment de l'appel.

Ce flake est conçu pour être utilisé uniquement via son `devShell` : c'est le `shellHook` qui définit `CLAUDE_CAGE_ROOT`, dont la commande `claude` a besoin. Sans lui, elle refuse de démarrer.

## Utiliser claude-cage dans un autre projet

Dans le projet à protéger, créez un `.envrc` qui pointe vers ce flake :

```
use flake /chemin/vers/claude-cage
```

puis `direnv allow`. La racine de la cage sera ce projet.

Vous pouvez aussi copier `flake.nix`, `flake.lock` et `.envrc` directement dans le projet : ils seront alors protégés en lecture seule dans la cage.

## Messages d'erreur courants

| Message | Cause | Solution |
| --- | --- | --- |
| `CLAUDE_CAGE_ROOT is not set` | Le shell du flake n'est pas chargé. | Utilisez `direnv allow` ou `nix develop`. |
| `current directory is outside the project root` | Vous lancez `claude` en dehors du projet. | `cd` vers le projet (ou un de ses sous-dossiers). |
| `bwrap: No permissions to create new namespace` | Les user namespaces sont désactivés. | Activez-les (par ex. `sysctl kernel.unprivileged_userns_clone=1` sur certaines distributions). |

## Personnalisation

Tout se règle dans `flake.nix` :

- **Fichiers protégés** : liste `protected` (chemins relatifs à la racine du projet, montés en lecture seule s'ils existent).
- **Outils disponibles dans la cage** : fonction `binPath` (par défaut : bash, coreutils, git, ripgrep, grep, sed, find, tar, gzip). Ajoutez-y un paquet (ex. `nodejs`, `python3`) si Claude doit pouvoir l'utiliser.
- **Variables d'environnement** : ajoutez des `--setenv NOM valeur` dans l'appel à `bwrap`.
- **Accès réseau** : retirez `--share-net` pour couper entièrement le réseau (Claude ne pourra alors plus joindre l'API : utile seulement à des fins de test).
- **Systèmes pris en charge** : liste `systems`.

Après modification, rechargez l'environnement (`direnv reload` ou quittez/relancez `nix develop`).

Pour mettre à jour nixpkgs (et donc la version de Claude Code) :

```sh
nix flake update
```

> `DISABLE_AUTOUPDATER` est activé : Claude Code ne se met pas à jour tout seul, la version dépend de nixpkgs.

## Limites

- Le bac à sable protège le **système de fichiers** et l'**environnement**, pas le réseau : Claude peut toujours faire des requêtes sortantes.
- Tout ce qui se trouve dans la racine du projet est lisible et modifiable par Claude (hors fichiers listés dans `protected`) : y compris un fichier `.env` ou des secrets qui y seraient stockés.
- Le dossier `~/.local/state/claude-cage` est partagé entre tous vos projets : il contient les identifiants de connexion de Claude et l'historique des conversations.
- Ce n'est pas une garantie de sécurité absolue : `bubblewrap` offre une bonne isolation, mais n'est pas une machine virtuelle.
