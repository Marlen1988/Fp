#!/bin/bash

echo "Would you like to change hostname? yes/no"

read VAR3
VAR1="no"
VAR2="yes"

if [ "$VAR3" = "$VAR2" ]; then
    echo "Please define hostname! For example srv1"
    read VAR4
    sudo hostnamectl set-hostname $VAR4
     hostnamectl
else
    echo "Host name not changed"
    hostnamectl
fi
sleep 3

echo "###########################################"
echo "Please enter path to locate Faceplate! 
#########################################
# ***RECOMENDED: /mnt/DATA/fp-pool/!*** #
#########################################

**In other case please change **/etc/systemd/system/fp.service**"

sleep 2

read path
mkdir -p $path
DIR=$path
if [ -d "$DIR" ]; then
    echo "$DIR Directory created sucsessfully!"
else 
    echo "$DIR Directory does not exist."
fi
echo "Copy in progres..."
sleep 2

echo $PWD
cp -R $PWD $path


sleep 2

cat > /etc/systemd/system/fp.service <<  EOF 
[Unit] 
Description=Faceplate service 
[Service]  
WorkingDirectory=/mnt/DATA/fp-pool/faceplate
Type=simple
Environment="HOME=/mnt/DATA/fp-pool/faceplate"
RemainAfterExit=true
LimitNOFILE=200000
ExecStart=/bin/bash /mnt/DATA/fp-pool/faceplate/bin/faceplate foreground
ExecStop=/mnt/DATA/fp-pool/faceplate/bin/faceplate foreground
#Restart=always
#RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
FILE=/etc/systemd/system/fp.service 

if [ -f "$FILE" ]; then
    echo "$FILE  file fp.service  created sucsessfully!"
else 
    echo "$FILE does not exist!Please check path"
fi

chmod +x /etc/systemd/system/fp.service

echo "Enabling fp.service..."
sudo systemctl enable fp.service
echo "fp.service in enable mode!"

sleep 5

chown -R user:user /mnt/DATA

echo "Would you like to start Faceplate? yes/no"

read VAR7
VAR5="no"
VAR6="yes"

if [ "$VAR7" = "$VAR6" ]; then
   
    
    sudo systemctl start fp
    sleep 30
     echo "
     ################
     #**fp started**#
     ################
     
     To stop faceplate please type 
     **systemctl stop fp**"
else
    echo "**Thanks all configuration finished!**"

fi



