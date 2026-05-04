#!/bin/bash
# =============================================================================
# post-import-config.sh
# Script de configuration post-import OVF pour Proxmox VE
#
# Usage:
#   chmod +x post-import-config.sh
#   ./post-import-config.sh <VMID> <STORAGE> <FIRMWARE>
#
# Arguments:
#   VMID      : Identifiant de la VM (ex: 300)
#   STORAGE   : Nom du storage Proxmox (ex: local-zfs, local-lvm)
#   FIRMWARE  : Type de firmware : uefi ou bios
#
# Exemples:
#   ./post-import-config.sh 300 local-zfs uefi
#   ./post-import-config.sh 200 local-lvm bios
#
# Testé sur : Proxmox VE 9.1.1
# Auteur    : Stagiaire DSI - Ministère de la Fonction Publique
# =============================================================================

set -e  # Arrêter en cas d'erreur

# --- Couleurs pour l'affichage ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Fonctions d'affichage ---
info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Vérification des arguments ---
if [ "$#" -ne 3 ]; then
    echo ""
    echo "Usage: $0 <VMID> <STORAGE> <FIRMWARE>"
    echo ""
    echo "  VMID     : Identifiant numérique de la VM (ex: 300)"
    echo "  STORAGE  : Nom du storage Proxmox (ex: local-zfs, local-lvm, local)"
    echo "  FIRMWARE : uefi  → VM VMware configurée en UEFI"
    echo "             bios  → VM VMware configurée en BIOS Legacy"
    echo ""
    echo "Exemples:"
    echo "  $0 300 local-zfs uefi"
    echo "  $0 200 local-lvm bios"
    echo ""
    exit 1
fi

VMID=$1
STORAGE=$2
FIRMWARE=$3

# --- Validation des arguments ---
if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
    error "VMID doit être un nombre entier (ex: 300)"
fi

if [[ "$FIRMWARE" != "uefi" && "$FIRMWARE" != "bios" ]]; then
    error "FIRMWARE doit être 'uefi' ou 'bios'"
fi

# --- Vérification que la VM existe ---
if ! qm status "$VMID" &>/dev/null; then
    error "La VM $VMID n'existe pas. Vérifiez l'import OVF."
fi

# --- Vérification que le storage existe ---
if ! pvesm status | grep -q "^$STORAGE "; then
    error "Le storage '$STORAGE' n'existe pas. Utilisez 'pvesm status' pour voir les storages."
fi

echo ""
echo "============================================================"
echo "  Configuration post-import Proxmox VE"
echo "  VM ID    : $VMID"
echo "  Storage  : $STORAGE"
echo "  Firmware : $FIRMWARE"
echo "============================================================"
echo ""

# --- Arrêter la VM si elle tourne ---
VM_STATUS=$(qm status "$VMID" | awk '{print $2}')
if [ "$VM_STATUS" == "running" ]; then
    warn "La VM $VMID est en cours d'exécution. Arrêt en cours..."
    qm stop "$VMID"
    sleep 3
    success "VM arrêtée"
fi

# --- Configuration selon le firmware ---
if [ "$FIRMWARE" == "uefi" ]; then
    info "Configuration UEFI (ovmf + q35)..."

    qm set "$VMID" --bios ovmf
    success "BIOS → ovmf"

    qm set "$VMID" --machine pc-q35-10.1
    success "Machine → pc-q35-10.1"

    # Vérifier si efidisk existe déjà
    if qm config "$VMID" | grep -q "efidisk0"; then
        warn "efidisk0 déjà présent — non recréé"
    else
        qm set "$VMID" --efidisk0 "${STORAGE}:1,efitype=4m,pre-enrolled-keys=0"
        success "efidisk0 créé sur $STORAGE"
    fi

else
    info "Configuration BIOS Legacy (seabios)..."
    qm set "$VMID" --bios seabios
    success "BIOS → seabios"
fi

# --- Réseau ---
info "Configuration réseau (e1000, bridge vmbr0)..."
qm set "$VMID" --net0 e1000,bridge=vmbr0
success "Carte réseau ajoutée (e1000, vmbr0)"

# --- OS type, cores, affichage ---
info "Configuration OS, CPU et affichage..."
qm set "$VMID" --ostype win10
qm set "$VMID" --cores 2
qm set "$VMID" --vga std
success "ostype=win10, cores=2, vga=std"

# --- Boot order ---
info "Vérification de l'ordre de boot..."
BOOT_ORDER=$(qm config "$VMID" | grep "^boot:" | awk '{print $2}')
if [ -z "$BOOT_ORDER" ]; then
    # Détecter le nom du disque principal
    DISK=$(qm config "$VMID" | grep -E "^(sata|scsi|ide|virtio)0:" | head -1 | awk -F: '{print $1}')
    if [ -n "$DISK" ]; then
        qm set "$VMID" --boot "order=${DISK}"
        success "Boot order → $DISK"
    else
        warn "Impossible de détecter le disque principal. Vérifiez manuellement."
    fi
else
    success "Boot order déjà configuré : $BOOT_ORDER"
fi

# --- QEMU Guest Agent ---
info "Activation du QEMU Guest Agent..."
qm set "$VMID" --agent enabled=1
success "QEMU Guest Agent activé"

# --- Affichage de la configuration finale ---
echo ""
echo "============================================================"
echo "  Configuration finale de la VM $VMID :"
echo "============================================================"
qm config "$VMID"
echo ""

# --- Résumé ---
echo "============================================================"
success "Configuration terminée !"
echo ""
echo "Prochaines étapes :"
echo "  1. Démarrer la VM  : qm start $VMID"
echo "  2. Ouvrir la console dans l'interface web Proxmox"
echo "  3. Vérifier que Windows démarre correctement"
echo "  4. Dans Windows : désinstaller VMware Tools"
echo "  5. Dans Windows : installer QEMU Guest Agent"
echo "       → https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/"
echo "============================================================"
echo ""
