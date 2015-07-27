#!/bin/bash
# OpenVPN Genetik57 installer pour Debian, Ubuntu et CentOS

# Ce script fonctionne sous Debian, Ubuntu, CentOS aet probablement sous d'autres distributions
# Script en Français et facile d'utilisation


if [[ "$USER" != 'root' ]]; then
	echo "Désolé, vous devez exécuter en tant que root"
	exit
fi


if [[ ! -e /dev/net/tun ]]; then
	echo "TUN/TAP n'est pas disponible"
	exit
fi


if grep -qs "CentOS release 5" "/etc/redhat-release"; then
	echo "CentOS 5 est trop vieux, il n'est donc pas pris en charge"
	exit
fi

if [[ -e /etc/debian_version ]]; then
	OS=debian
	RCLOCAL='/etc/rc.local'
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
	OS=centos
	RCLOCAL='/etc/rc.d/rc.local'
	# Nécessaire pour CentOS 7
	chmod +x /etc/rc.d/rc.local
else
	echo "Looks like you aren't running this installer on a Debian, Ubuntu or CentOS system"
	exit
fi

newclient () {
	# Génération du client.ovpn
	cp /usr/share/doc/openvpn*/*ample*/sample-config-files/client.conf ~/$1.ovpn
	sed -i "/ca ca.crt/d" ~/$1.ovpn
	sed -i "/cert client.crt/d" ~/$1.ovpn
	sed -i "/key client.key/d" ~/$1.ovpn
	echo "<ca>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/2.0/keys/ca.crt >> ~/$1.ovpn
	echo "</ca>" >> ~/$1.ovpn
	echo "<cert>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/2.0/keys/$1.crt >> ~/$1.ovpn
	echo "</cert>" >> ~/$1.ovpn
	echo "<key>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/2.0/keys/$1.key >> ~/$1.ovpn
	echo "</key>" >> ~/$1.ovpn
}


# Essaye d'obtenir l'adresse IP du système.
# Pour rendre compatible avec les serveurs NATed (lowendspirit.com)
# et pour éviter d'avoir une adresse IPv6.
IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
if [[ "$IP" = "" ]]; then
		IP=$(wget -qO- ipv4.icanhazip.com)
fi


if [[ -e /etc/openvpn/server.conf ]]; then
	while :
	do
	clear
		echo "On dirait qu'OpenVPN est déjà installé"
		echo ""
		echo "Que voulez-vous faire ?"
		echo "   1) Ajouter un certificat pour un nouvel utilisateur ?"
		echo "   2) Révoquer le certificat existant d'un utilisateur ?"
		echo "   3) Supprimer OpenVPN ?"
		echo "   4) Quitter/Sortir ?"
		echo ""
		echo "Script OpenVPN By Genetik57"
		echo ""
		read -p "Sélectionnez une option [1-4]: " option
		case $option in
			1) 
			echo ""
			echo "Donnez-moi un nom pour le certificat"
			echo "S'il vous plaît, utilisez un seul mot, pas de caractères spéciaux"
			read -p "Nom du client : " -e -i client CLIENT
			cd /etc/openvpn/easy-rsa/2.0/
			source ./vars
			# Contruire la clé pour le client
			export KEY_CN="$CLIENT"
			export EASY_RSA="${EASY_RSA:-.}"
			"$EASY_RSA/pkitool" $CLIENT
			# Générer le client.ovpn
			newclient "$CLIENT"
			echo ""
			echo "Client $CLIENT ajouté, le certificat est disponible ici ~/$CLIENT.ovpn"
			exit
			;;
			2)
			# Cette option pourrait être documentée un peu mieux et peut-être même être simplifiée
			NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/2.0/keys/index.txt | grep "^V" | wc -l)
			if [[ "$NUMBEROFCLIENTS" = '0' ]]; then
				echo ""
				echo "Vous n'avez pas de clients existants !"
				exit
			fi
			echo ""
			echo "Sélectionnez le certificat du client existant que vous souhaitez révoquer"
			tail -n +2 /etc/openvpn/easy-rsa/2.0/keys/index.txt | grep "^V" | cut -d '/' -f 7 | cut -d '=' -f 2 | nl -s ') '
			if [[ "$NUMBEROFCLIENTS" = '1' ]]; then
				read -p "Select one client [1]: " CLIENTNUMBER
			else
				read -p "Select one client [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
			fi
			CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/2.0/keys/index.txt | grep "^V" | cut -d '/' -f 7 | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)
			cd /etc/openvpn/easy-rsa/2.0/
			. /etc/openvpn/easy-rsa/2.0/vars
			. /etc/openvpn/easy-rsa/2.0/revoke-full $CLIENT
			# Si c'est la première fois que vous révoquer un certificat
			# nous devons ajouter la ligne crl-verify
			if ! grep -q "crl-verify" "/etc/openvpn/server.conf"; then
				echo "crl-verify /etc/openvpn/easy-rsa/2.0/keys/crl.pem" >> "/etc/openvpn/server.conf"
				# And restart
				if pgrep systemd-journal; then
					systemctl restart openvpn@server.service
				else
					if [[ "$OS" = 'debian' ]]; then
						/etc/init.d/openvpn restart
					else
						service openvpn restart
					fi
				fi
			fi
			echo ""
			echo "Le certificat du client $CLIENT est révoqué !"
			exit
			;;
			3) 
			echo ""
			read -p "Voulez-vous vraiment supprimer OpenVPN ? [y/n]: " -e -i n REMOVE
			if [[ "$REMOVE" = 'y' ]]; then
				if [[ "$OS" = 'debian' ]]; then
					apt-get remove --purge -y openvpn openvpn-blacklist
				else
					yum remove openvpn -y
				fi
				rm -rf /etc/openvpn
				rm -rf /usr/share/doc/openvpn*
				sed -i '/--dport 53 -j REDIRECT --to-port/d' $RCLOCAL
				sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0/d' $RCLOCAL
				echo ""
				echo "OpenVPN supprimé !"
			else
				echo ""
				echo "Suppression annulée !"
			fi
			exit
			;;
			4) exit;;
		esac
	done
else
	clear
	echo 'Bienvenue sur le script d&#39;installation rapide OpenVPN By Genetik57'
	echo ""
	# OpenVPN configuration et création du premier utilisateur
	echo "Je dois vous poser quelques questions avant de commencer l'installation"
	echo "Vous pouvez laisser les options par défauts et appuyez simplement sur ENTER si vous avez le même choix"
	echo ""
	echo "Je dois d'abord connaître l'adresse IPv4 de l'interface réseau OpenVPN que vous souhaitez"
	echo "voilà"
	read -p "Adresse IP : " -e -i $IP IP
	echo ""
	echo "Quel port voulez-vous pour OpenVPN ?"
	read -p "Port : " -e -i 1194 PORT
	echo ""
	echo "Souhaitez-vous qu'OpenVPN soit disponible au port 53 ?"
	echo "Cela peut être utile pour se connecter sous réseaux restreints"
	read -p "Disponible sur le port 53 [y/n] : " -e -i n ALTPORT
	echo ""
	echo "Voulez-vous activer le réseau interne pour le VPN ?"
	echo "Cela peut permettre aux clients VPN de communiquer entre eux"
	read -p "Autoriser réseau interne [y/n] : " -e -i n INTERNALNETWORK
	echo ""
	echo "Quel DNS voulez-vous utiliser avec le VPN ?"
	echo "   1) Résolveurs actuels du système"
	echo "   2) OpenDNS"
	echo "   3) Niveau 3"
	echo "   4) NTT"
	echo "   5) Hurricane Electric"
	echo "   6) Yandex"
	echo ""
	echo "Script OpenVPN By Genetik57"
	echo ""
	read -p "DNS [1-6] : " -e -i 1 DNS
	echo ""
	echo "Enfin, dites-moi votre nom pour le certificat client"
	echo "S'il vous plaît, utilisez un seul mot, pas de caractères spéciaux"
	read -p "Nom du client : " -e -i client CLIENT
	echo ""
	echo "D'accord, j'ai maintenant fini. Nous sommes prêts pour débuter la configuration de votre serveur OpenVPN"
	read -n1 -r -p "Appuyez sur n'importe quelle touche pour continuer ..."
		if [[ "$OS" = 'debian' ]]; then
		apt-get update
		apt-get install openvpn iptables openssl -y
	else
		# Sinon, la distribution est CentOS
		yum install epel-release -y
		yum install openvpn iptables openssl wget -y
	fi
	# Une ancienne version de easy-rsa était disponible par défaut dans certains packages OpenVPN
	if [[ -d /etc/openvpn/easy-rsa/2.0/ ]]; then
		rm -f /etc/openvpn/easy-rsa/2.0/
	fi
	# Sert à obtenir easy-rsa
	wget --no-check-certificate -O ~/easy-rsa.tar.gz https://github.com/OpenVPN/easy-rsa/archive/2.2.2.tar.gz
	tar xzf ~/easy-rsa.tar.gz -C ~/
	mkdir -p /etc/openvpn/easy-rsa/2.0/
	cp ~/easy-rsa-2.2.2/easy-rsa/2.0/* /etc/openvpn/easy-rsa/2.0/
	rm -rf ~/easy-rsa-2.2.2
	rm -rf ~/easy-rsa.tar.gz
	cd /etc/openvpn/easy-rsa/2.0/
	# Fixons-le en première chose ...
	cp -u -p openssl-1.0.0.cnf openssl.cnf
	# Créez le PKI
	. /etc/openvpn/easy-rsa/2.0/vars
	. /etc/openvpn/easy-rsa/2.0/clean-all
	# Les lignes suivantes sont pour build-ca. Je n'uutilise le script directement
	# car il est interactif et nous ne voulons pas qu'il le soit. Oui, cela pourrait briser
	# le script d'installation si des changements build-ca se font à l'avenir.
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" --initca $*
	# Même chose que la dernière fois, nous allons exécuter build-key-server
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" --server server
	# Maintenant, les touches de clients. Nous devons établir KEY_CN ou pkitool stupide crierons
	export KEY_CN="$CLIENT"
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" $CLIENT
	# DH params
	. /etc/openvpn/easy-rsa/2.0/build-dh
	# Nous allons configurer le serveur
	cd /usr/share/doc/openvpn*/*ample*/sample-config-files
	if [[ "$OS" = 'debian' ]]; then
		gunzip -d server.conf.gz
	fi
	cp server.conf /etc/openvpn/
	cd /etc/openvpn/easy-rsa/2.0/keys
	cp ca.crt ca.key dh2048.pem server.crt server.key /etc/openvpn
	cd /etc/openvpn/
	# Réglez la configuration du serveur
	sed -i 's|dh dh1024.pem|dh dh2048.pem|' server.conf
	sed -i 's|;push "redirect-gateway def1 bypass-dhcp"|push "redirect-gateway def1 bypass-dhcp"|' server.conf
	sed -i "s|port 1194|port $PORT|" server.conf
	# DNS
	case $DNS in
		1) 
		# Obtenir les résolveurs de resolv.conf et les utiliser pour OpenVPN
		grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
			sed -i "/;push \"dhcp-option DNS 208.67.220.220\"/a\push \"dhcp-option DNS $line\"" server.conf
		done
		;;
		2)
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 208.67.222.222"|' server.conf
		sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 208.67.220.220"|' server.conf
		;;
		3) 
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 4.2.2.2"|' server.conf
		sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 4.2.2.4"|' server.conf
		;;
		4) 
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 129.250.35.250"|' server.conf
		sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 129.250.35.251"|' server.conf
		;;
		5) 
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 74.82.42.42"|' server.conf
		;;
		6) 
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 77.88.8.8"|' server.conf
		sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 77.88.8.1"|' server.conf
		;;
	esac
	# Obtenir le port 53 si l'utilisateur veut que
	if [[ "$ALTPORT" = 'y' ]]; then
		iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port $PORT
		sed -i "1 a\iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port $PORT" $RCLOCAL
	fi
	# Activer net.ipv4.ip_forward pour le système
	if [[ "$OS" = 'debian' ]]; then
		sed -i 's|#net.ipv4.ip_forward=1|net.ipv4.ip_forward=1|' /etc/sysctl.conf
	else
		# CentOS 5 et 6
		sed -i 's|net.ipv4.ip_forward = 0|net.ipv4.ip_forward = 1|' /etc/sysctl.conf
		# CentOS 7
		if ! grep -q "net.ipv4.ip_forward=1" "/etc/sysctl.conf"; then
			echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
		fi
	fi
	# Évitez un redémarrage inutiles
	echo 1 > /proc/sys/net/ipv4/ip_forward
	# Fixer iptables
	if [[ "$INTERNALNETWORK" = 'y' ]]; then
		iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
		sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP" $RCLOCAL
	else
		iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP
		sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP" $RCLOCAL
	fi
	# Et enfin, le redémarrage OpenVPN
	if [[ "$OS" = 'debian' ]]; then
		# Petit hack pour vérifier systemd
		if pgrep systemd-journal; then
			systemctl restart openvpn@server.service
		else
			/etc/init.d/openvpn restart
		fi
	else
		if pgrep systemd-journal; then
			systemctl restart openvpn@server.service
			systemctl enable openvpn@server.service
		else
			service openvpn restart
			chkconfig openvpn on
		fi
	fi
	# Essayez de détecter une connexion NATed et demander à ce sujet un LowEndSpirit potentiel
	# utilisateurs
	EXTERNALIP=$(wget -qO- ipv4.icanhazip.com)
	if [[ "$IP" != "$EXTERNALIP" ]]; then
		echo ""
		echo "On dirait que votre serveur est derrière un NAT !"
		echo ""
		echo "Si votre serveur est NAT (LowEndSpirit), je dois savoir si l'adresse IP est externe"
		echo "Si ce est pas le cas, ignorez simplement cela et laissez le champ vide suivant"
		read -p "Adresse IP externe : " -e USEREXTERNALIP
		if [[ "$USEREXTERNALIP" != "" ]]; then
			IP=$USEREXTERNALIP
		fi
	fi
	# Ensemble IP/port sur le client.conf par défaut afin que nous puissions ajouter d'autres utilisateurs
	sed -i "s|remote my-server-1 1194|remote $IP $PORT|" /usr/share/doc/openvpn*/*ample*/sample-config-files/client.conf
	# Génére le client.ovpn
	newclient "$CLIENT"
	echo ""
	echo "Fini !"
	echo ""
	echo "Votre configuration client est disponible ici ~/$CLIENT.ovpn"
	echo "Si vous voulez ajouter plus de clients, il vous suffit de lancer ce script à nouveau !"
	echo ""
	echo "Script OpenVPN By Genetik57"
fi
