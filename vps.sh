#!/bin/bash
set -euo pipefail

# Copyright (c) 2025 Jakub Orłowski
# Licensed under the MIT License. See LICENSE for details.


display_header() {
    clear
    cat << "EOF"
+-----------------------------+-----+-----------------------------+
            
____   _________               _____      _____    _______   
\   \ /   /     \             /     \    /  _  \   \      \  
 \   Y   /  \ /  \   ______  /  \ /  \  /  /_\  \  /   |   \ 
  \     /    Y    \ /_____/ /    Y    \/    |    \/    |    \
   \___/\____|__  /         \____|__  /\____|__  /\____|__  /
                \/                  \/         \/         \/ 
                
+-----------------------------+-----+-----------------------------+
  
         POWERED BY LINUXIARZNAETACIE, BASED ON HOPINGBOYZ
                
+-----------------------------+-----+-----------------------------+
EOF
    echo
}

print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[OSTRZEZENIE]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[BLAD]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUKCES]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Wartosc musi byc numerem"
                return 1
            fi
            ;;
        "size")
            if ! [[ "$value" =~ ^[0-9]+[GgMm]$ ]]; then
                print_status "ERROR" "Rozmiar musi byc w podanej jednostce (np., 100G, 512M)"
                return 1
            fi
            ;;
        "port")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 23 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Podaj prawidlowy numer portu (23-65535)"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                print_status "ERROR" "Nazwa VM'ki moze zawierac wylacznie litery, cyfry, myslniki i podlogi"
                return 1
            fi
            ;;
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                print_status "ERROR" "Nazwa uzytkownika musi zaczynac sie od litery lub podlogi i zawierac wyłacznie litery, cyfry, myslniki i podlogi"
                return 1
            fi
            ;;
    esac
    return 0
}

check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Brakujace zaleznosci: ${missing_deps[*]}"
        print_status "INFO" "Na systemie Ubuntu/Debian, sprobuj wpisac: sudo apt install qemu-system cloud-image-utils wget -y"
        print_status "INFO" "Jesli uzywasz Google Firebase, wklej plik dev.nix"
        print_status "INFO" "z mojego githuba (https://github.com/gownokutas/firebase-vps-menu) na twoj Firebase do folderu /idx/dev.nix"
        exit 1
    fi
}

cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
}

get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        
        source "$config_file"
        return 0
    else
        print_status "ERROR" "Konfiguracja dla VM'ki '$vm_name' nie zostala znaleziona!"
        return 1
    fi
}

save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    
    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Zapisano konfiguracje do $config_file"
}

create_new_vm() {
    print_status "INFO" "Tworzenie nowej VM'ki"
    
    print_status "INFO" "Wybierz system operacyjny:"
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Wybierz opcje (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "Nieprawidlowa opcja. Sprobuj ponownie."
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Wpisz nazwe VM'ki (domyslnie: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM'ka o nazwie '$VM_NAME' juz istnieje"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Wpisz nazwe komputera (domyslnie: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Wpisz nazwe uzytkownika (domyslnie: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        read -s -p "$(print_status "INPUT" "Wpisz haslo (domyslnie: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ -n "$PASSWORD" ]; then
            break
        else
            print_status "ERROR" "Haslo nie moze byc puste!"
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Wpisz rozmiar dysku (domyslnie: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Wpisz ilosc RAM'u w megabajtach (domyslnie: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Wpisz Liczbe CPU (domyslnie: 2): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Wpisz port SSH (domyslnie: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT jest aktualnie uzywany"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Czy wlaczyc tryb GUI? (y/n, domyslnie: n): ")" gui_input
        GUI_MODE=false
        gui_input="${gui_input:-n}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            break
        else
            print_status "ERROR" "Odpowiedz (y) - Tak lub (n) - Nie"
        fi
    done
    read -p "$(print_status "INPUT" "Wpisz tutaj dodatkowe porty do otwarcia (np., 8080:80, nacisnij ENTER, zeby nie dodawac zadnego): ")" PORT_FORWARDS

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    setup_vm_image
    
    save_vm_config
}


setup_vm_image() {
    print_status "INFO" "Pobieranie i przygotowywanie obrazu..."

    mkdir -p "$VM_DIR"
    
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Plik obrazu juz istnieje. Pomijanie pobierania."
    else
        print_status "INFO" "Pobieranie obrazu z: $IMG_URL..."
        if ! wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"; then
            print_status "ERROR" "Nie udalo sie pobrac obrazu z linku: $IMG_URL"
            exit 1
        fi
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_status "WARN" "Nie udalo sie zwiekszyc rozmairu dysku. Tworzenie nowego obrazu o okreslonym rozmiarze..."
        rm -f "$IMG_FILE"
        qemu-img create -f qcow2 -F qcow2 -b "$IMG_FILE" "$IMG_FILE.tmp" "$DISK_SIZE" 2>/dev/null || \
        qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
        if [ -f "$IMG_FILE.tmp" ]; then
            mv "$IMG_FILE.tmp" "$IMG_FILE"
        fi
    fi

    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Nie udalo sie utworzyc obrazu startowego cloud-init"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' zostala pomyslnie stworzona."
}

start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Uruchamianie VM'ki: $vm_name"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Haslo: $PASSWORD"
        
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "Obraz VM'ki nie zostal znaleziony: $IMG_FILE"
            return 1
        fi
        
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Nie znaleziono pliku seed, ponowne tworzenie..."
            setup_vm_image
        fi
        
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -m "$MEMORY"
            -smp "$CPUS"
            -cpu host
            -drive "file=$IMG_FILE,format=qcow2,if=virtio"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot order=c
            -device virtio-net-pci,netdev=n0
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )
        
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "virtio-net-pci,netdev=n${#qemu_cmd[@]}")
                qemu_cmd+=(-netdev "user,id=n${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
            done
        fi

        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi

        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
        )

        print_status "INFO" "Uruchamianie QEMU..."
        "${qemu_cmd[@]}"
        
        print_status "INFO" "VM $vm_name zostala wylaczona!"
    fi
}

delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "Ta opcja usunie twoja VM'ke '$vm_name' pernamentnie i usunie wszystkie dane tej maszyny!"
    read -p "$(print_status "INPUT" "Czy kontynuowac? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM '$vm_name' zostala pomyslnie usunieta!"
        fi
    else
        print_status "INFO" "Anulowano usuniecie!"
    fi
}

show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "Informacje o VM'ce: $vm_name"
        echo "=========================================="
        echo "OS: $OS_TYPE"
        echo "Nazwa komputera (hostname): $HOSTNAME"
        echo "Nazwa uzytkownika: $USERNAME"
        echo "Haslo: $PASSWORD"
        echo "Port SSH: $SSH_PORT"
        echo "RAM: $MEMORY MB"
        echo "CPU: $CPUS"
        echo "Rozmiar dysku: $DISK_SIZE"
        echo "Tryb GUI: $GUI_MODE"
        echo "Otwarte porty: ${PORT_FORWARDS:-None}"
        echo "Utworzono: $CREATED"
        echo "Plik obrazu: $IMG_FILE"
        echo "Plik Seed: $SEED_FILE"
        echo "=========================================="
        echo
        read -p "$(print_status "INPUT" "Nacisnij ENTER aby kontynuowac...")"
    fi
}

is_vm_running() {
    local vm_name=$1
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null; then
        return 0
    else
        return 1
    fi
}

stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Wylaczanie VM'ki: $vm_name"
            pkill -f "qemu-system-x86_64.*$IMG_FILE"
            sleep 2
            if is_vm_running "$vm_name"; then
                print_status "WARN" "VM'ka nie zostala wylaczona bezpiecznie, wymuszanie wylaczenia..."
                pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
            fi
            print_status "SUCCESS" "VM $vm_name zostala wylaczona"
        else
            print_status "INFO" "VM $vm_name nie jest wlaczona"
        fi
    fi
}

edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Edytowanie VM'ki: $vm_name"
        
        while true; do
            echo "Co chcesz edytowac?"
            echo "  1) Nazwa komputera (hostname)"
            echo "  2) Nazwa Uzytkownika"
            echo "  3) Haslo"
            echo "  4) Port SSH"
            echo "  5) Tryb GUI"
            echo "  6) Otwieranie Portow"
            echo "  7) RAM"
            echo "  8) Liczba CPU"
            echo "  9) Rozmiar dysku"
            echo "  0) Wroc do glownego menu"
            
            read -p "$(print_status "INPUT" "Wybierz opcje: ")" edit_choice
            
            case $edit_choice in
                1)
                    while true; do
                        read -p "$(print_status "INPUT" "Wpisz nowa nazwe komputera (hostname) (obecnie: $HOSTNAME): ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_status "INPUT" "Wpisz nowa nazwe uzytkownika (obecnie: $USERNAME): ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -s -p "$(print_status "INPUT" "Wpisz nowe haslo: ")" new_password
                        new_password="${new_password:-$PASSWORD}"
                        echo
                        if [ -n "$new_password" ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            print_status "ERROR" "Haslo nie moze byc puste!"
                        fi
                    done
                    ;;
                4)
                    while true; do
                        read -p "$(print_status "INPUT" "Wpisz nowy port SSH (obecnie: $SSH_PORT): ")" new_ssh_port
                        new_ssh_port="${new_ssh_port:-$SSH_PORT}"
                        if validate_input "port" "$new_ssh_port"; then
                            # Check if port is already in use
                            if [ "$new_ssh_port" != "$SSH_PORT" ] && ss -tln 2>/dev/null | grep -q ":$new_ssh_port "; then
                                print_status "ERROR" "Port $new_ssh_port jest aktualnie uzywany!"
                            else
                                SSH_PORT="$new_ssh_port"
                                break
                            fi
                        fi
                    done
                    ;;
                5)
                    while true; do
                        read -p "$(print_status "INPUT" "Czy wlaczyc tryb GUI? (y/n, obecnie: $GUI_MODE): ")" gui_input
                        gui_input="${gui_input:-}"
                        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
                            GUI_MODE=true
                            break
                        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
                            GUI_MODE=false
                            break
                        elif [ -z "$gui_input" ]; then
                            # Keep current value if user just pressed Enter
                            break
                        else
                            print_status "ERROR" "Odpowiedz (y) - Tak lub (n) - Nie"
                        fi
                    done
                    ;;
                6)
                    read -p "$(print_status "INPUT" "Otworz kolejne porty (obecnie: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                    PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
                    ;;
                7)
                    while true; do
                        read -p "$(print_status "INPUT" "Wpisz nowa ilosc RAM'u w megabajtach (obecnie: $MEMORY): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        if validate_input "number" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    ;;
                8)
                    while true; do
                        read -p "$(print_status "INPUT" "Wpisz nowa ilosc CPU (obecnie: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                9)
                    while true; do
                        read -p "$(print_status "INPUT" "Wpisz nowy rozmiar dysku (obecnie: $DISK_SIZE): ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
                    ;;
                0)
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Nieprawidlowa opcja!"
                    continue
                    ;;
            esac
            
            if [[ "$edit_choice" -eq 1 || "$edit_choice" -eq 2 || "$edit_choice" -eq 3 ]]; then
                print_status "INFO" "Aktualizowanie konfiguracji cloud-init..."
                setup_vm_image
            fi
            
            save_vm_config
            
            read -p "$(print_status "INPUT" "Czy Kontynuowac edytowanie? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
        done
    fi
}

resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Obecny rozmiar dysku: $DISK_SIZE"
        
        while true; do
            read -p "$(print_status "INPUT" "Napisz nowy rozmiar dysku (np., 50G): ")" new_disk_size
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_status "INFO" "Nowy dysk ma taki sam rozmiar jak stary. Nie zapisano zmian."
                    return 0
                fi
                
                local current_size_num=${DISK_SIZE%[GgMm]}
                local new_size_num=${new_disk_size%[GgMm]}
                local current_unit=${DISK_SIZE: -1}
                local new_unit=${new_disk_size: -1}
                
                if [[ "$current_unit" =~ [Gg] ]]; then
                    current_size_num=$((current_size_num * 1024))
                fi
                if [[ "$new_unit" =~ [Gg] ]]; then
                    new_size_num=$((new_size_num * 1024))
                fi
                
                if [[ $new_size_num -lt $current_size_num ]]; then
                    print_status "WARN" "Zmniejszanie rozmiaru dysku nie jest rekomendowane i moze prowadzic do utraty danych!"
                    read -p "$(print_status "INPUT" "Czy napewno chcesz kontynuowac? (y/N): ")" confirm_shrink
                    if [[ ! "$confirm_shrink" =~ ^[Yy]$ ]]; then
                        print_status "INFO" "Anulowano zmiane rozmiaru dyku."
                        return 0
                    fi
                fi
                
                print_status "INFO" "Zmienianie rozmiaru dysku na $new_disk_size..."
                if qemu-img resize "$IMG_FILE" "$new_disk_size"; then
                    DISK_SIZE="$new_disk_size"
                    save_vm_config
                    print_status "SUCCESS" "Zmieniono rozmiar dysku na $new_disk_size"
                else
                    print_status "ERROR" "Nie udalo sie zmienic rozmiaru dysku!"
                    return 1
                fi
                break
            fi
        done
    fi
}

show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Uzycie zasobow dla VM: $vm_name"
            echo "=========================================="
            
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                echo "Statystyki procesow QEMU:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers
                echo
                echo "Uzycie RAM'u:"
                free -h
                echo
                echo "Uzycie dysku:"
                df -h "$IMG_FILE" 2>/dev/null || du -h "$IMG_FILE"
            else
                print_status "ERROR" "Nie mozna znalezc procesow QEMU dla VM'ki: $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name nie jest uruchomiona"
            echo "Konfiguracja:"
            echo "  RAM: $MEMORY MB"
            echo "  CPU: $CPUS"
            echo "  Dysk: $DISK_SIZE"
        fi
        echo "=========================================="
        read -p "$(print_status "INPUT" "Nacisnij ENTER aby kontynuowac...")"
    fi
}

main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Znaleziono $vm_count istniejacych VM'ek:"
            for i in "${!vms[@]}"; do
                local status="Wylaczona"
                if is_vm_running "${vms[$i]}"; then
                    status="Uruchomiona"
                fi
                printf "  %2d) %s (%s)\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi
        
        echo "Menu Glowne:"
        echo "  1) Stworz nowa VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Uruchom VM"
            echo "  3) Wylacz VM"
            echo "  4) Pokaz informacje o danej VM"
            echo "  5) Edytuj konfiguracje VM"
            echo "  6) Usun VM"
            echo "  7) Zmien rozmiar dysku dla VM"
            echo "  8) Pokaz zuzycie parametrow VM"
        fi
        echo "  0) Wyjdz"
        echo
        
        read -p "$(print_status "INPUT" "Wybierz opcje: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Wpisz ID VM'ki ktora uruchomic: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Nie prawidlowe ID!"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Wpisz ID VM'ki ktora zatrzymac: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Nie prawidlowe ID!"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Wpisz ID VM'ki ktorej pokazac konfiguracje: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Nie prawidlowe ID!"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Wpisz ID VM'ki ktora edytowac: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Nie prawidlowe ID!"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Wpisz ID VM'ki ktora usunac: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Nie prawidlowe ID!"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Wpisz ID VM'ki ktorej zmienic rozmiar dysku: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        resize_vm_disk "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Nie prawidlowe ID!"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Wpisz ID VM'ki ktorej pokazac parametry: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Nie prawidlowe ID!"
                    fi
                fi
                ;;
            0)
                print_status "INFO" "Bye Bye <3"
                exit 0
                ;;
            *)
                print_status "ERROR" "Nie prawidlowy numer opcji!"
                ;;
        esac
        
        read -p "$(print_status "INPUT" "Nacisnij ENTER aby kontynuowac...")"
    done
}

trap cleanup EXIT

check_dependencies

VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Debian 13"]="debian|trixie|https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2|debian13|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

main_menu
