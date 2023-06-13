#!/bin/bash

# Script permettant la sauvegarde du serveur apache et des bases de données
# Auteur : Maxime ROLLAND
# Date : 13/06/2023

# Déclaration des variables
date=$(date +%Y-%m-%d-%H-%M-%S)
# permet de spécifier le mode de fonctionnement du script
# folder = sauvegarde d'un répertoire
# bdd = sauvegarde d'une base de données
# mixte = sauvegarde d'un répertoire et d'une base de données
mode=$1

# On vérifie si le mode est définit et correct
if [ $mode != "folder" ] && [ $mode != "bdd" ] && [ $mode != "mixte" ]; then
    echo "Veuillez saisir un mode de fonctionnement correct"
    exit 1
fi


emplacementSauvegarde="/var/backups/scriptAutoBackup"

if [ $mode == "folder" ];then

  # On vérifie si l'emplacement de sauvagarde existe
  if [ ! -d $emplacementSauvegarde ]; then
      mkdir $emplacementSauvegarde -p
  fi

  reperoiteASauvegarder=$2

  # On vérifie si l'emplacement à sauvegarder existe
  if [ ! -d $reperoiteASauvegarder ]; then
      echo "Le répertoire à sauvegarder n'existe pas"
      exit 1
  fi

  echo "###############################################"
  echo "$date - Backup FOLDER $reperoiteASauvegarder"


  # On créé un nom de fichier unique basé sur la date et le nom du répertoire à sauvegarder
  # On remplace les "/" par des "-" pour éviter les erreurs

  safeName=$(echo $reperoiteASauvegarder | sed 's/\//-/g')

  nomFichierSauvegarde="$date$safeName.tar.gz"


  # Fonction de sauvegarde des fichiers du serveur apache
  function sauvegarde_folder {
      # Création de l'archive
      tar -czf $emplacementSauvegarde/$date$safeName.tar.gz $1
      
  }

  sauvegarde_folder $reperoiteASauvegarder $nomFichierSauvegarde

fi

if [ $mode == "bdd" ]; then
  echo "###############################################"
  echo "$date - Backup BDD $2"
  mysqldump $2 > $emplacementSauvegarde/$date-bdd-$2.sql

fi