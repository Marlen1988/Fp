#!/bin/bash

echo "Would you like to install postgre? yes/no"

read VAR3
VAR1="no"
VAR2="yes"

if [ "$VAR3" = "$VAR2" ]; then
    echo "Updating repositories and installing postgreSQL DB..."
    read VAR4
    sudo apt update
    sleep 2
    sudo apt install postgresql postgresql-contrib
    sleep 2
    sudo systemctl start postgresql.service
    sleep 2
    echo "entering to postgreSQL DB...."
    sleep 3
    sudo -u postgres psql
    echo "to exit from postgre print' \q'"
      
else
    echo "repositoruies not updated"

fi



