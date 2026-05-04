# 🖥️ Migration VMware Workstation → Proxmox VE

> **Guide complet et reproductible** pour migrer une machine virtuelle Windows depuis VMware Workstation Pro vers Proxmox VE, via WinSCP et la CLI Proxmox.
>
> Validé en environnement de simulation (lab) et applicable directement en production.

---

## 📋 Table des matières

- [Contexte](#-contexte)
- [Architecture](#-architecture)
- [Prérequis](#-prérequis)
- [Vue d'ensemble du processus](#-vue-densemble-du-processus)
- [Étape 1 — Vérification et export depuis VMware](#étape-1--vérification-et-export-depuis-vmware)
- [Étape 2 — Transfert via WinSCP](#étape-2--transfert-via-winscp)
- [Étape 3 — Import dans Proxmox](#étape-3--import-dans-proxmox)
- [Étape 4 — Configuration post-import](#étape-4--configuration-post-import)
- [Étape 5 — Démarrage et vérification](#étape-5--démarrage-et-vérification)
- [Étape 6 — Nettoyage](#étape-6--nettoyage)
- [Dépannage](#-dépannage)
- [Commandes de référence rapide](#-commandes-de-référence-rapide)
- [Auteur](#-auteur)

---

## 📌 Contexte

Ce projet documente la migration de machines virtuelles Windows depuis **VMware Workstation Pro** vers **Proxmox VE**, dans le cadre de l'homogénéisation de l'environnement de virtualisation du **Ministère de la Fonction Publique**.

La procédure a été :
1. Testée et validée en **environnement de simulation** (Proxmox installé comme VM dans VMware sur Windows 11)
2. Conçue pour être directement **applicable en production**

---

## 🏗️ Architecture

### Environnement de simulation (lab)

```
┌─────────────────────────────────────────────────────┐
│              Machine hôte Windows 11                │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │         VMware Workstation Pro               │   │
│  │                                              │   │
│  │  ┌─────────────────┐  ┌──────────────────┐  │   │
│  │  │  VM Windows 10  │  │   VM Proxmox VE  │  │   │
│  │  │   (SOURCE)      │  │    (CIBLE)       │  │   │
│  │  │                 │  │  192.168.75.149  │  │   │
│  │  └────────┬────────┘  └────────▲─────────┘  │   │
│  │           │   Export OVF       │             │   │
│  │           └───────────────────►│             │   │
│  │                    WinSCP SFTP              │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Équivalence Production

| Composant lab | Équivalent Production |
|---|---|
| PC Windows 11 | Serveur physique |
| VMware Workstation Pro | VMware Workstation / ESXi |
| VM Windows 10 dans VMware | VM Windows du Ministère |
| VM Proxmox dans VMware | Serveur Proxmox VE dédié |
| WinSCP depuis Windows 11 | WinSCP ou SCP depuis poste admin |

---

## ✅ Prérequis

### Logiciels requis

| Logiciel | Version testée | Usage |
|---|---|---|
| VMware Workstation Pro | 17+ | Hyperviseur source |
| Proxmox VE | 9.1.1 | Hyperviseur cible |
| WinSCP | 6+ | Transfert SFTP |

### Configuration réseau VMware

Pour que WinSCP puisse atteindre la VM Proxmox depuis l'hôte Windows, configurer le réseau des VMs en mode **NAT** ou **Bridged** dans VMware.

### Informations à collecter avant de démarrer

- [ ] Adresse IP de la VM Proxmox (`ip a` dans la console Proxmox)
- [ ] Mot de passe root de Proxmox
- [ ] Chemin des fichiers de la VM VMware (`VM Settings → Options → Working directory`)
- [ ] **Type de firmware de la VM source : BIOS ou UEFI** ← CRITIQUE

> ⚠️ **Point critique** : Le type de firmware (BIOS/UEFI) de la VM source dans VMware doit correspondre exactement à la configuration dans Proxmox. Une erreur ici empêche le démarrage de la VM.

---

## 🗺️ Vue d'ensemble du processus

```
[1] Vérifier firmware VMware (BIOS/UEFI)
         ↓
[2] Export OVF depuis VMware
         ↓
[3] Vérifier espace disque sur Proxmox
         ↓
[4] Transfert WinSCP → Proxmox
         ↓
[5] Import qm importovf sur Proxmox
         ↓
[6] Configuration post-import (UEFI + réseau + vga)
         ↓
[7] Démarrage et vérification
         ↓
[8] Nettoyage des fichiers temporaires
```

---

## Étape 1 — Vérification et export depuis VMware

### 1.1 Vérifier le type de firmware de la VM source

> ⚠️ **Cette étape est OBLIGATOIRE** — elle conditionne toute la configuration Proxmox.

Dans VMware Workstation :
1. Clic droit sur la VM → **Settings**
2. Onglet **Options** → **Advanced**
3. Regarder le champ **Firmware type**

| Valeur affichée | Action dans Proxmox |
|---|---|
| **BIOS** | `--bios seabios` (défaut) |
| **UEFI** | `--bios ovmf` + `--efidisk0` + `--machine pc-q35-10.1` |

Dans notre cas : **UEFI** (sans Secure Boot).

### 1.2 Arrêt propre de la VM

> ⚠️ Ne jamais forcer l'arrêt — risque de corruption du VMDK.

Dans la VM Windows : **Démarrer → Arrêter**

Attendre que VMware affiche la VM comme éteinte avant de continuer.

### 1.3 Export au format OVF

1. Dans VMware : **File → Export to OVF...**
2. Choisir un dossier de destination, par exemple `D:\Migration\`
3. Donner un nom : `Win10-Ministere`
4. Cliquer **Save** et attendre la fin

**Fichiers générés :**

```
D:\Migration\
├── Win10-Ministere.ovf          ← configuration XML (15 KB)
├── Win10-Ministere-disk1.vmdk   ← disque Windows (~7-35 GB)
├── Win10-Ministere-file1.iso    ← ne pas transférer
├── Win10-Ministere-file2.nvram  ← ne pas transférer
└── Win10-Ministere.mf           ← fichier de hachage (1 KB)
```

> **Seuls 3 fichiers sont nécessaires pour l'import Proxmox :** `.ovf`, `.vmdk`, `.mf`

---

## Étape 2 — Transfert via WinSCP

### 2.1 Vérifier l'espace disponible sur Proxmox

Dans le Shell Proxmox, **avant** de transférer :

```bash
df -h /root      # espace partition système
zfs list         # espace ZFS disponible
```

**Résultat type :**
```
/root  →  8.4G total, 6.3G utilisé, 1.7G libre  ⚠️ souvent insuffisant
local-zfs  →  48.0G disponible                   ✅ utiliser ZFS
```

> ⚠️ Ne pas transférer dans `/root` si l'espace est insuffisant. Utiliser le storage ZFS.

**Créer le dossier de réception :**

```bash
mkdir -p /local-zfs/migration-win10
```

### 2.2 Connexion WinSCP

Ouvrir WinSCP et configurer :

| Champ | Valeur |
|---|---|
| File Protocol | **SFTP** |
| Host name | IP de la VM Proxmox (ex: `192.168.75.149`) |
| Port | `22` |
| User name | `root` |
| Password | mot de passe root Proxmox |

Cliquer **Login** → accepter l'empreinte SSH (normal à la première connexion).

### 2.3 Transfert des fichiers

Dans WinSCP :
- **Panneau gauche (Windows)** : naviguer vers `D:\Migration\`
- **Panneau droit (Proxmox)** : naviguer vers `/local-zfs/migration-win10/`

Sélectionner avec `Ctrl+clic` ces 3 fichiers uniquement :
- `Win10-Ministere.ovf`
- `Win10-Ministere-disk1.vmdk`
- `Win10-Ministere.mf`

Glisser-déposer vers le panneau droit et attendre la fin du transfert.

**Vérification après transfert :**

```bash
ls -lh /local-zfs/migration-win10/
```

Sortie attendue :
```
-rw-r--r-- 1 root root   1K  Win10-Ministere.mf
-rw-r--r-- 1 root root  15K  Win10-Ministere.ovf
-rw-r--r-- 1 root root 7.5G  Win10-Ministere-disk1.vmdk
```

---

## Étape 3 — Import dans Proxmox

### 3.1 Choisir un VMID disponible

```bash
qm list    # voir les VMID déjà utilisés
```

Choisir un VMID libre (ex: `300`).

### 3.2 Identifier le storage cible

```bash
pvesm status
```

Utiliser le storage avec suffisamment d'espace. Dans notre cas : `local-zfs`.

### 3.3 Lancer l'import OVF

```bash
qm importovf 300 /local-zfs/migration-win10/Win10-Ministere.ovf local-zfs
```

L'import affiche la progression :
```
transferred 1.0 GiB of 35.0 GiB (2.86%)
transferred 2.0 GiB of 35.0 GiB (5.72%)
...
transferred 35.0 GiB of 35.0 GiB (100.00%)
```

> La durée dépend de la taille du disque. Prévoir 5 à 20 minutes.

### 3.4 Vérifier la VM créée

```bash
qm list         # la VM 300 doit apparaître
qm config 300   # voir la configuration importée
```

---

## Étape 4 — Configuration post-import

> ⚠️ L'import OVF crée une VM minimale. Il faut configurer manuellement le firmware, le réseau et l'affichage.

### 4.1 Vérifier la configuration importée

```bash
qm config 300
```

Configuration type après import :
```
boot: order=sata0
cores: 1
memory: 4096
name: Windows10VM
sata0: local-zfs:vm-300-disk-0
```

**Ce qui manque :** bios, machine, efidisk (si UEFI), réseau, vga.

### 4.2 Appliquer la configuration complète

#### Cas UEFI (notre cas — VM VMware configurée en UEFI)

```bash
# Activer UEFI + machine q35
qm set 300 --bios ovmf --machine pc-q35-10.1

# Ajouter le disque EFI (obligatoire avec ovmf)
qm set 300 --efidisk0 local-zfs:1,efitype=4m,pre-enrolled-keys=0

# Ajouter la carte réseau
qm set 300 --net0 e1000,bridge=vmbr0

# Définir le type d'OS, les cores et l'affichage
qm set 300 --ostype win10 --cores 2 --vga std
```

#### Cas BIOS Legacy (si la VM VMware était en mode BIOS)

```bash
# SeaBIOS est le défaut, mais on le précise
qm set 300 --bios seabios

# Ajouter la carte réseau
qm set 300 --net0 e1000,bridge=vmbr0

# Définir le type d'OS et l'affichage
qm set 300 --ostype win10 --cores 2 --vga std
```

### 4.3 Vérification finale de la configuration

```bash
qm config 300
```

Configuration attendue (cas UEFI) :
```
bios: ovmf
boot: order=sata0
cores: 2
efidisk0: local-zfs:vm-300-disk-1,efitype=4m,pre-enrolled-keys=0,size=1M
machine: pc-q35-10.1
memory: 4096
name: Windows10VM
net0: e1000=XX:XX:XX:XX:XX:XX,bridge=vmbr0
ostype: win10
sata0: local-zfs:vm-300-disk-0
vga: std
```

---

## Étape 5 — Démarrage et vérification

### 5.1 Démarrer la VM

```bash
qm start 300
```

Puis aller dans l'interface web Proxmox → VM 300 → **Console**.

### 5.2 Comportement attendu au premier démarrage

| Scénario | Signification | Action |
|---|---|---|
| Écran noir quelques secondes | Normal, Windows démarre | Patienter 1-3 min |
| `Guest has not initialized the display yet` | Normal, affichage en cours d'init | Patienter |
| Bureau Windows visible | ✅ **Migration réussie** | Passer aux vérifications |
| BSOD `INACCESSIBLE_BOOT_DEVICE` | Mauvais contrôleur disque | Voir [Dépannage](#-dépannage) |
| `No bootable device found` | Mauvais firmware ou boot order | Voir [Dépannage](#-dépannage) |

### 5.3 Vérifications dans Windows

**Vérifier le réseau :**
```cmd
ipconfig /all
```
La VM doit avoir une adresse IP via DHCP.

**Vérifier le Gestionnaire de périphériques :**
- Ouvrir `devmgmt.msc`
- Vérifier l'absence de périphériques inconnus (points d'exclamation jaunes)

**Désinstaller VMware Tools :**
- Panneau de configuration → Programmes → Désinstaller `VMware Tools`
- Ces outils sont inutiles et potentiellement gênants dans Proxmox

### 5.4 Installer le QEMU Guest Agent (recommandé)

Le QEMU Guest Agent permet à Proxmox de :
- Effectuer des arrêts propres depuis l'interface
- Voir l'adresse IP de la VM dans Proxmox
- Faire des snapshots cohérents

```bash
# Dans Proxmox, activer le guest agent
qm set 300 --agent enabled=1
```

Puis dans Windows, installer `qemu-ga-x86_64.msi` depuis l'ISO VirtIO :
- Télécharger : https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/

---

## Étape 6 — Nettoyage

Une fois la migration validée, supprimer les fichiers temporaires :

```bash
rm -rf /local-zfs/migration-win10/
```

Vérifier la suppression :
```bash
ls /local-zfs/
```

---

## 🔧 Dépannage

### Problème : `No valid offer received` + écran UEFI en boucle

**Cause :** VM configurée en UEFI dans Proxmox mais sans efidisk, ou efidisk vide.

**Solution :**
```bash
qm stop 300
qm set 300 --bios ovmf --machine pc-q35-10.1
qm set 300 --efidisk0 local-zfs:1,efitype=4m,pre-enrolled-keys=0
qm start 300
```

---

### Problème : `No bootable device. Retrying in 1 second` (SeaBIOS)

**Cause :** VM en SeaBIOS mais le disque est GPT/UEFI (pas de MBR).

**Diagnostic :**
```bash
fdisk -l /dev/zvol/local-zfs/vm-300-disk-0
```

Si `Disklabel type: gpt` → le disque est UEFI, pas BIOS.

**Solution :** Passer en UEFI (voir configuration post-import cas UEFI).

---

### Problème : WinSCP ne peut pas se connecter

**Vérifications :**
```bash
# Sur Proxmox
ip a                        # vérifier l'IP
systemctl status ssh        # vérifier que SSH tourne
```

Vérifier aussi que les VMs VMware sont dans le même réseau (NAT ou Bridged).

---

### Problème : `qm importovf` échoue — `storage not found`

```bash
pvesm status    # voir les noms exacts des storages
```

Utiliser le nom exact affiché (ex: `local-zfs`, `local-lvm`, `local`).

---

### Problème : Écran noir persistant dans la Console

**Solution :**
```bash
qm stop 300
qm set 300 --vga std
qm start 300
```

---

### Problème : BSOD au démarrage Windows

**Cause :** Contrôleur SCSI incompatible.

**Solution :** Essayer différents contrôleurs dans l'ordre :
```bash
qm stop 300
qm set 300 --scsihw lsi        # essai 1
# ou
qm set 300 --scsihw ide        # essai 2
qm start 300
```

---

## 📖 Commandes de référence rapide

```bash
# Voir toutes les VMs
qm list

# Voir la config d'une VM
qm config <VMID>

# Voir le statut d'une VM
qm status <VMID>

# Démarrer / Arrêter / Forcer arrêt
qm start <VMID>
qm stop <VMID>
qm shutdown <VMID>

# Supprimer complètement une VM et ses disques
qm destroy <VMID> --purge

# Voir les storages disponibles
pvesm status

# Voir les datasets ZFS
zfs list

# Voir l'espace disque
df -h /root

# Vérifier le type de partition d'un disque
fdisk -l /dev/zvol/local-zfs/vm-<VMID>-disk-0
```

---

## 📁 Structure du projet

```
vmware-to-proxmox-migration/
├── README.md                          ← ce fichier
├── docs/
│   ├── guide-migration-complet.docx  ← guide Word détaillé
│   └── troubleshooting.md            ← dépannage avancé
└── scripts/
    └── post-import-config.sh         ← script de configuration automatique
```

---

## 📚 Références

- [Documentation officielle Proxmox VE 9.1](https://pve.proxmox.com/pve-docs/pve-admin-guide.html)
- [Section 10.7 — Importing Virtual Machines](https://pve.proxmox.com/pve-docs/pve-admin-guide.html#qm_import)
- [Wiki Proxmox — Migrate to Proxmox VE](https://pve.proxmox.com/wiki/Migrate_to_Proxmox_VE)
- [Drivers VirtIO pour Windows](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/)

---

## 👤 Auteur

**Stagiaire DSI — Direction des Systèmes d'Information**
Ministère de la Fonction Publique

> Ce guide a été rédigé après validation en environnement de simulation.
> Il est destiné à être reproduit en production par l'équipe DSI ou tout technicien habilité.

---

## 📄 Licence

Ce projet est publié sous licence [MIT](LICENSE) — libre d'utilisation, modification et distribution avec attribution.
