# Firebase QEMU VPS Menu

## Ogólny przegląd

Ten skrypt ma na celu uruchomienie zaawansowane menu do narzędzia QEMU, można za pomocą tego menu wykonywać takie rzeczy, które za pomocą komend, zajeły by "kupe" lat.

## Minimalne wymagania

- System operacyjny: Debian, Ubuntu lub Google Firebase
- Środowisko powłoki Bash
- Połączenie z internetem
- Procesor o architekturze: x86_64 (amd64)
- Zainstalowane narzędzie curl lub git (do uruchomienia lub pobrania samego skryptu)
- Zainstalowane zależności (do prawidlowego dzialania skryptu): qemu-system qemu-kvm cloud-image-utils wget
- Zainstalowanie zależności (do uruchomienia trybu GUI) xrdp tigervnc-standalone-server tigervnc-xorg-extension

## Zainstaluj zależności

Debian / Ubuntu:

  Zależności do działania skryptu i prawidłowego działania
  
    sudo apt update && sudo apt install qemu-system cloud-image-utils wget curl git -y

  Zależności do działania trybu GUI
  
    sudo apt update && xrdp tigervnc-standalone-server tigervnc-xorg-extension -y
    
Google Firebase:

    1. Na stronie https://idx.google.com po zalogowaniu na konto google, kliknij przycisk Import Repo
    2. Wklej ten link w Repo URL: https://github.com/JishnuTheGamer/vps123, zaznacz opcję Mobile SDK Support, i naciśnij Import
    3. Gdy Firebase sie uruchomi, zapyta o stworzenie domyslnej konfiguracji dev.nix, zgódź się! i naciśnij Take me Here
    4. Skopiuj całą zawartość pliku z tego linku: https://github.com/gownokutas/firebase-vps-menu/blob/main/dev.nix
    5. Wklej całą zawartość tego pliku w to miejsce które otworzyło się na twoim serwerze, a następnie naciśnij Rebuilt Envirionment i zaczekaj 5-10 minut
    6. Uruchom skrypt za pomocą narzędzia curl (poniżej jest komenda)

## Pobierz i uruchom skrypt
 Uruchom Skrypt za pomocą narzędzia curl:
 
    bash <(curl -sSf https://raw.githubusercontent.com/linuxiarznaetacie/firebase-vps-menu/refs/heads/main/vps.sh)

 Uruchom skrypt za pomocą narzędzia git
 
    git clone https://github.com/linuxiarznaetacie/firebase-vps-menu.git && cd firebase-vps-menu && clear && bash vps.sh

## Rozwiązania na problemy które mogą wyniknąć:

Problem: Port SSH: Port 2222 jest już zajęty!
Rozwiązanie: Wpisz 2022, lub inny wolny port.


## Licencja 🇵🇱

Ten skrypt na maszyny wirtualne QEMU został wydany na licencji [MIT License](LICENSE).

## Zasługi 🇵🇱

Ten projekt mógł zostać stworzony dzięki [hopingboyz](https://github.com/hopingboyz) 
jego skrypt https://github.com/hopingboyz/vms został przetłumaczony na Język Polski, i dodatkowo usprawniony.
Nie jest to kopia jeden do jeden lecz fork powyższego projektu.

**Notatka 🇵🇱:** Ten skrypt został stworzony w celach naukowych i eksperymentalnych, nie odpowiadam za zablokowane Firebase, lub inne uszkodzenia sprzętu, używasz na własną odpowiedzialność!

---

## License 🇬🇧

Ten QEMU virtual machine scripts have been released under the [MIT License](LICENSE).

## Credits 🇬🇧

This project was made possible thanks to [hopingboyz](https://github.com/hopingboyz).
His script https://github.com/hopingboyz/vms has been translated into Polish and further improved.
This is not a one-to-one copy, but a fork with a short project description.

**Note 🇬🇧:** This script was created for scientific and experimental purposes, I am not responsible for blocked Firebase or other hardware damage, use at your own risk!
