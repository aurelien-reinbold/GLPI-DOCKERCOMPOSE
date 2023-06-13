#!/bin/bash

#### 12/06/2023 - Maxime ROLLAND - mrolland57@gmail.com ####
## Script Démo TP TSR L13
## Installation et configuration d'un serveur LAMP

## On s'assure que notre script s execute avec les droits root car on agit sur le système
if (( $(id -u) != 0 ));then
	echo "Ce script a besoin des droits root pour s'executer."
	exit
fi

# Variable globale
adminEmail="toto@toto.fr"

## On met à jour notre système si la dernière mise à jour à plus d'une heure
nbSecondeBtwUpdate=3600
# On récupère la date de dernière mise à jour du cache des paquets
dateLastUpdate=$(ls -l /var/cache/apt/pkgcache.bin | cut -d' ' -f6,7,8)
# On converti cette date en timestamp
timeStampLastUpdate=$(date -d "$dateLastUpdate" '+%s')
# On récupère le timestamp actuel
timeStampNow=$(date '+%s')

# On compare les deux timestamp
if (( ($timeStampLastUpdate + $nbSecondeBtwUpdate) <= $timeStampNow));then
	apt update && apt upgrade -y
fi

## On installe les paquets nécessaires au fonctionnement de LAMP
apt install -y\
	php\
	php-mysql\
	apache2\
	mariadb-server\
	mariadb-client\
	certbot\
	python3-certbot-apache

# On récupère le fqdn de notre serveur à partir du premier argument passé au script
fqdn=$1
# Si aucun argument n'est passé, on demande à l'utilisateur de renseigner le fqdn
if [ -z $fqdn ];then
	read -p "Quelle FQDN dois-je configurer ? :" fqdn
fi

# On récupère le choix de l'utilisateur à partir du deuxième argument passé au script
userChoice=$2
# Si aucun argument n'est passé, on demande à l'utilisateur de renseigner le choix
if [ -z $userChoice ];then
	read -p "Que dois préparer ? [ vitrine|extranet|cloud|helpdesk| ]: " userChoice
fi

# On vérifie que le choix de l'utilisateur est valide
if [[ $userChoice != "vitrine" &&  $userChoice != "extranet" && $userChoice != "cloud" && $userChoice != "helpdesk" ]]; then
	echo "$userChoice n'est pas un choix valide!"
	exit
fi

## On teste si le fqdn est un CNAME
# On utilise la commande dig pour récupérer les informations DNS du fqdn
# On filtre les lignes qui contiennent le fqdn
# On filtre les lignes qui contiennent CNAME
# On compte le nombre de lignes
isCNAME=$(dig $fqdn|grep $fqdn|grep CNAME|wc -l)
# On initialise la variable host
host=""
## On test si le fqdn est un A
# On utilise la commande dig pour récupérer les informations DNS du fqdn
# On filtre les lignes qui contiennent le fqdn
# On filtre les lignes qui contiennent A
isA=$(dig $fqdn | grep "^$fqdn"|  grep '\<A\>' |wc -l)

# Si le nombre de lignes est supérieur à 0, alors le fqdn est un CNAME
# On récupère le nom d'hote cible du CNAME
if (( $isCNAME > 0 ));then
	host=$(dig $fqdn|grep $fqdn|grep CNAME | cut -f3)
fi

# Si le nombre de lignes est supérieur à 0, alors le fqdn est un A
# On récupère le nom d'hote cible du A
if (($isA > 0 && $isCNAME == 0)); then
	host=$fqdn
fi

# On récupère l'adresse ip de l'hote cible à partir des enregistrements DNS publiques
ipHost=$(dig $host | grep "^$host" | grep A |cut -f5)

# On cherche à l'aide de la commande IP si l'adresse IP récupérée est présente sur notre machine
recordOnMyMachine=$(ip addr| grep $ipHost | wc -l)

if (( $recordOnMyMachine == 0 ));then
	echo "Le nom de domaine $fqdn n'est pas résolu sur notre machine"
	exit
fi

# On vérifie que le dossier de destination n'existe pas déjà
destinationDir="/var/www/$fqdn"

if [ ! -d $destinationDir ];then
	mkdir "$destinationDir"
else
	# Si l'option -f est passée en troisième argument, on supprime le dossier de destination
	# On supprime également la base de données associée
	# On recrée le dossier de destination
	if [[ $3 == "-f" ]];then
		rm -rf $destinationDir
		echo $userChoice
		echo "DROP DATABASE $(echo $userChoice)_db;"
		mysql -e "DROP DATABASE $(echo $userChoice)_db;"
		mkdir "$destinationDir"
	else
		echo "Erreur, $destinationDir existe déjà!"
		exit
	fi
fi

echo "$host est sur $ipHost"

echo "Je configure $fqdn"
# Fonction de création de fichier de configuration Apache VirtualHost
function makeVirtualHost(){
	echo "<VirtualHost *:80>
        	ServerName $1
        	ServerAdmin webmaster@localhost
        	DocumentRoot $2
        	ErrorLog ${APACHE_LOG_DIR}/error.log
        	CustomLog ${APACHE_LOG_DIR}/access.log combined
		<Directory $2>
			AllowOverride All
		</Directory>
	</VirtualHost>" > /etc/apache2/sites-available/$1.conf
	a2ensite $1.conf
	systemctl reload apache2
}

makeVirtualHost $fqdn $destinationDir

# Fonction de création de certificat SSL
function makeSSL(){
	certbot --apache -d $1 -m $2 -n --agree-tos

}
makeSSL $fqdn $adminEmail

# Fonction de création de base de données et d'utilisateur MySQL
function makeDB(){
	dbName="$1_db"
	userName="$1_user"
	password=$1$(date +"%Y%m%d")
	mysql -e "CREATE DATABASE $dbName;"
	mysql -e "CREATE USER $userName IDENTIFIED BY '$password';"
	mysql -e "GRANT ALL PRIVILEGES ON $dbName.* TO $userName;"
	mysql -e "FLUSH PRIVILEGES;"

	echo "Création: Base de données : $dbName, utilisateur: $userName, mdp: $password"
}

tempDir="./temp"
# On créé un dossier temporaire
if [ ! -d $tempDir ];then
	mkdir $tempDir
fi

# Fonction de création du site vitrine 
# attend en argument l'emplacement dans le système de fichiers
function makeVitrine(){
	cp ./vitrine/* $1 -r
	chown www-data $1 -R
}

# Fonction de création du site extranet (Wordpress)
# attend en argument l'emplacement dans le système de fichiers
function makeExtranet(){
	makeDB wordpress
	echo "J'installe un wordpress"
	cd $tempDir
	version='6.2.2'
	wget https://wordpress.org/wordpress-$version.tar.gz
	tar -xvf wordpress-$version.tar.gz &> /dev/null
	cp ./wordpress/* $1 -r
	chown www-data $1 -R
}

# Fonction de création du site cloud (Nextcloud)
# attend en argument l'emplacement dans le système de fichiers
function makeCloud(){
	makeDB nextcloud
	echo "J'installe un nextcloud"
	cd temp
	wget https://download.nextcloud.com/server/releases/nextcloud-26.0.2.tar.bz2
	tar -xvf nextcloud-26.0.2.tar.bz2 &> /dev/null
	cp ./nextcloud/* $1 -r
	chown www-data $1 -R
	apt install -y\
		php-dompdf\
		php-xml\
		php-curl\
		php-gd\
		php-intl\
		php-zip\
		php-mbstring
	systemctl reload apache2
}

# Fonction de création du site helpdesk (GLPI)
# attend en argument l'emplacement dans le système de fichiers
function makeHelpdesk(){
	makeDB glpi
	echo "J'installe GLPI"
	cd temp
	wget https://github.com/glpi-project/glpi/releases/download/10.0.7/glpi-10.0.7.tgz
	tar -xvf glpi-10.0.7.tgz &> /dev/null
	cp ./glpi/* $1 -r
	chown www-data $1 -R
	apt install -y\
		php-dompdf\
		php-xml\
		php-curl\
		php-gd\
		php-intl
	systemctl reload apache2
}

case $userChoice in
	vitrine)
		makeVitrine $destinationDir
	;;
	extranet)
		makeExtranet $destinationDir
	;;
	cloud)
		makeCloud $destinationDir
	;;
	helpdesk)
		makeHelpdesk $destinationDir
	;;
esac
