# SMS TO EMAIL GATEWAY
- A simple SMS gateway to forward SMS received from a SIM card to an email address, with Raspberry Pi and LTE modem.

## Startup the project

- Go to `https://www.notion.so/SMS-Gateway-779235cd14384d9d9fe48c57626fce59` to see the project.

- The initial setup of the module and SD card first boot done. WiFi connected...

Connect to the module by ssh:
```bash
# from host [module has first boot done]
ping smsgw.local # => get module IP
ssh user@[IP]
```

Install sms_to_email_gateway package
```bash
# Download git project
cd /home/user
git clone https://github.com/loicmorel/sms_to_email_gateway

# Edit configuration file
sudo apt-get install vim
vim /home/user/sms_to_email_gateway/config.ini

# Install the package
cd /home/user/sms_to_email_gateway
sudo setup-config.sh config.ini
```

## Verify the module

```bash
# send a test email
send_test_email.sh

# check APN and SIM card caracteristics
qmicli -d /dev/cdc-wdm0 --nas-get-home-network
qmicli -d /dev/cdc-wdm0 --uim-get-card-status

# check logs
cat /var/log/start-modem.log
cat /var/log/send_test_email.log
```

# Configuration structure

```bash
# sms_to_email_gateway configuration
# run to initiate the config
# > setup-config.sh [config.ini]

# config sms wraper
MODEM_TTY=/dev/ttyUSB2
INCOMING_SMS_P=/var/spool/sms/incoming

# config wifi
SSID=[ssid]
WIFI_PWD=[pwd]

# config APN for LTE communication
APN=cmhk

# config email sender
FROM_EMAIL=loic@bemylab.com
FROM_PWD=[pwd]
FROM_HUB=ssl0.ovh.net:465

# config output email
DEST_EMAIL=loic.morel@gmail.com
HOST_NAME=HK
```

# Scripts usage

```bash
> setup-config.sh [config.ini]
# params: [configuration file]
# actions:
#  - install dependencies
#  - install custom package
#  - initiate deamons for send_email_when_sms and internet_manager
#  - setup WiFi conf and initiate
#  - setup APN conf file
#  - setup email conf files (from & to)

> systemctl [params] send-email-when-sms.service
# params: [start][stop][restart][status]
# actions: service that monitor the incoming sms and automatically send an email

> systemctl [params] internet-manager.service
# params: [start][stop][restart][status]
# actions: service that monitor and keep internet active between wlan0 and wwan0

> send_test_email.sh
# no params
# action: send a test email based on the current configuration
```
