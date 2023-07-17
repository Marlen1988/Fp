#!/bin/bash

echo " Хотите поменять название хоста и IP адрес? Напишите да/нет, пожалуйста"

read VAR3
VAR1="нет"
VAR2="да"

if [ "$VAR3" = "$VAR2" ]; then
    echo "Укажите новое название хоста! РЕКОМЕНДОВАНО *master.fp* или *slave.fp*"
    echo "Укажите название хоста Вашего ПК:"
    read -r VAR4

sudo hostnamectl set-hostname  $VAR4
	hostnamectl
echo "********************************************************"	
echo "Укажите IP адрес ДРУГОЙ *FACEPLATE* ноды :"
     echo "Укажите IP:"
read -r VAR5
echo "Укажите название ДРУГОЙ *FACEPLATE* ноды :"
read -r VAR6
sudo sed -i "1s/^/$VAR5   $VAR6\n/" /etc/hosts

else
    echo "Название хоста не изменено"
    hostnamectl
fi
sleep 3
echo "*/etc/hosts* файл изменен"

echo "###########################################"
echo "Пожалуйста, укажите путь для размещения Faceplate!
#########################################
# ***РЕКОМЕНДОВАНО: /mnt/DATA/fp-pool/ *** #
#########################################
**В другом случае, пожалуйста, поменяйте **/etc/systemd/system/fp.service**"

sleep 2

read path
mkdir -p $path
DIR=$path
if [ -d "$DIR" ]; then
    echo "$DIR Директория успешно создана!"
else 
    echo "$DIR Директории не существует."
fi
echo "Copy in progres..."
sleep 2

echo $PWD
cp -R $PWD $path


sleep 2
echo "########################################################"
echo "Хотите запустить как Master? Напишите да/нет"
echo "выберите *да* чтобы запустить как *Master*"
echo "choose *нет* чтобы запустить как *Slave*"
read ms3
ms1="нет"
ms2="да"

if [ "$ms3" = "$ms1" ]; then

# Найти путь к файлу vm.args внутри проекта
file_path=$(find "$PWD" -name "vm.args" -type f)
echo "$file_path"

# Проверить, что файл найден
if [[ -f "$file_path" ]]; then
    sed -i "s/-name fp@master.fp/-name fp@slave.fp/g" "$file_path"
    
    echo "файл vm.args изменен!"
else
    echo "файл vm.args не найден"
    sleep 2
     echo "Данный ПК - *Master*"
fi
fi
sleep 3



cat > /etc/systemd/system/fp.service <<  EOF 
[Unit] 
Description=Faceplate service 
[Service]  
WorkingDirectory=/mnt/DATA/fp-pool/faceplate
Type=simple
Environment="HOME=/mnt/DATA/fp-pool/faceplate"
Environment="FORCE_START=true"
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
    echo "$FILE  файл fp.service успешно создан!"
else 
    echo "$FILE файл не существует! Пожалуйста, проверьте путь"
fi

chmod +x /etc/systemd/system/fp.service

echo "Включение fp.service..."
sudo systemctl enable fp.service
echo "fp.service во включенном режиме!"

sleep 5

chown -R user:user /mnt/DATA

echo "Хотите запустить Faceplate? да/нет"

read VAR7
VAR5="нет"
VAR6="да"

if [ "$VAR7" = "$VAR6" ]; then
   
    
    sudo systemctl start fp
    sleep 30
     echo "
     ################
     #**fp запущен**#
     ################
     
     Чтобы остановить faceplate напишите 
     **systemctl stop fp**"
else
    echo "**Все конфигурации окончены. Спасибо!**"

fi



Footer
© 2023 GitHub, Inc.
Footer navigation
Terms
Privacy
Security
Status
Docs
Contact GitHub
Pricing
API
Training
Blog
About
Fp/script.sh at main · Marlen1988/Fp
