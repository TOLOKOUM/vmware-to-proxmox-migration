# 🔧 Guide de dépannage — Migration VMware → Proxmox VE

Ce document couvre les problèmes rencontrés lors de la migration et leurs solutions exactes, basées sur des cas réels.

---

## Problème 1 — Écran UEFI en boucle : `No valid offer received`

**Symptômes :**
```
DVE-E16: No valid offer received
Failed to load Boot0001 UEFI QEMU...
Start boot option
```

**Cause :** La VM est en mode UEFI (ovmf) mais soit l'efidisk manque, soit il est vide, soit la machine n'est pas en q35.

**Solution complète :**
```bash
qm stop <VMID>
qm set <VMID> --bios ovmf
qm set <VMID> --machine pc-q35-10.1
qm set <VMID> --efidisk0 local-zfs:1,efitype=4m,pre-enrolled-keys=0
qm set <VMID> --boot order=sata0
qm start <VMID>
```

---

## Problème 2 — SeaBIOS : `No bootable device. Retrying in 1 second`

**Symptômes :**
```
SeaBIOS (version rel-1.17...)
Booting from Hard Disk...
No bootable device. Retrying in 1 second.
```

**Cause :** Le disque importé est en GPT/UEFI (pas de MBR) mais la VM est configurée en BIOS Legacy.

**Diagnostic :**
```bash
# Trouver le bon chemin du disque ZFS
zfs list | grep <VMID>

# Vérifier le type de partition
fdisk -l /dev/zvol/local-zfs/vm-<VMID>-disk-0
```

Si la sortie indique `Disklabel type: gpt` avec une partition `EFI System` → le disque est UEFI.

**Solution :** Passer en UEFI (voir Problème 1).

---

## Problème 3 — `fdisk: cannot open /dev/zvol/rpool/data/...`

**Symptôme :** Le chemin ZFS utilisé n'existe pas.

**Cause :** Le pool ZFS n'est pas `rpool` mais un nom personnalisé (ex: `local-zfs`).

**Diagnostic :**
```bash
zfs list           # voir les pools et datasets
ls /dev/zvol/      # voir les pools disponibles
```

Construire le chemin correct : `/dev/zvol/<NOM_POOL>/vm-<VMID>-disk-<N>`

---

## Problème 4 — WinSCP ne peut pas se connecter à Proxmox

**Symptômes :** Timeout de connexion, refus de connexion.

**Vérifications sur Proxmox :**
```bash
ip a                          # vérifier l'adresse IP
systemctl status ssh          # vérifier que SSH est actif
ss -tlnp | grep :22           # vérifier que le port 22 écoute
```

**Vérification réseau :**
- Les deux VMs (Windows 10 et Proxmox) doivent être dans le même réseau VMware
- Essayer de pinger Proxmox depuis Windows : `ping <IP-Proxmox>`
- Vérifier le mode réseau VMware : NAT ou Bridged (éviter Host-Only)

---

## Problème 5 — `qm importovf` échoue : `storage not found`

**Symptôme :**
```
storage 'local-lvm' does not exist
```

**Solution :**
```bash
pvesm status    # affiche les noms exacts des storages
```

Utiliser le nom exact tel qu'affiché dans la colonne `Name`.

---

## Problème 6 — `qm importovf` échoue : `permission denied` sur le fichier OVF

**Symptôme :**
```
Permission denied: /local-zfs/migration-win10/Win10-Ministere.ovf
```

**Solution :**
```bash
chmod 644 /local-zfs/migration-win10/*.ovf
chmod 644 /local-zfs/migration-win10/*.vmdk
chmod 644 /local-zfs/migration-win10/*.mf
```

---

## Problème 7 — Espace insuffisant dans `/root`

**Symptôme :** Transfert WinSCP échoue ou `importovf` échoue par manque d'espace.

**Diagnostic :**
```bash
df -h /root      # voir l'espace disponible sur /
zfs list         # voir l'espace ZFS disponible
```

**Solution :** Utiliser le storage ZFS comme destination :
```bash
mkdir -p /local-zfs/migration-win10
# Transférer dans /local-zfs/migration-win10/ via WinSCP
```

---

## Problème 8 — Écran noir persistant dans la Console Proxmox

**Symptômes :** La VM est en état `running` mais la console affiche un écran noir depuis plus de 5 minutes.

**Solution :**
```bash
qm stop <VMID>
qm set <VMID> --vga std
qm start <VMID>
```

Le type d'affichage `std` est le plus compatible avec Windows lors d'une migration.

---

## Problème 9 — BSOD `INACCESSIBLE_BOOT_DEVICE`

**Cause :** Le contrôleur SCSI configuré dans Proxmox est incompatible avec les drivers Windows existants.

**Solution — essayer dans l'ordre :**

```bash
qm stop <VMID>

# Essai 1 : LSI (le plus compatible avec Windows)
qm set <VMID> --scsihw lsi
qm start <VMID>

# Si toujours BSOD, essai 2 :
qm stop <VMID>
qm set <VMID> --scsihw lsi53c810
qm start <VMID>
```

Si le disque est en `sata`, ce problème ne se pose généralement pas.

---

## Problème 10 — Deux efidisks créés accidentellement

**Symptôme :** La commande `qm set --efidisk0` a été lancée deux fois.

**Diagnostic :**
```bash
qm config <VMID>   # si efidisk0 et efidisk1 apparaissent
zfs list | grep <VMID>   # voir tous les disques créés
```

**Solution :**
```bash
# Supprimer le disque superflu (garder disk-1, supprimer disk-2 ou disk-3)
qm set <VMID> --delete efidisk0
# Puis recréer proprement
qm set <VMID> --efidisk0 local-zfs:1,efitype=4m,pre-enrolled-keys=0
```

Pour supprimer manuellement un dataset ZFS orphelin :
```bash
zfs destroy local-zfs/vm-<VMID>-disk-<N>
```

---

## Commandes de diagnostic générales

```bash
# Statut complet d'une VM
qm status <VMID>
qm config <VMID>

# Logs QEMU de la VM (très utile pour diagnostiquer les crashes)
cat /var/log/pve/qemu-server/<VMID>.log

# Voir tous les disques d'une VM
zfs list | grep <VMID>

# Voir les tâches récentes Proxmox
journalctl -u pvedaemon --since "1 hour ago"
```
