#!/bin/bash

# params: [configuration file]
# actions:
#  - install dependencies
#  - install custom package
#  - initiate deamons for send-email-when-smsd and internet-checkerd
#  - setup WiFi conf and initiate
#  - setup APN conf file
#  - setup email conf files (from & to)

## collect config data
if [ ! -z $1 ] && [ -f $1 ]; then
  echo "Configuration file found:" $1
else
  echo "Configuration file not found"
  echo "Usage: setup-config.sh [config-file]"
  exit
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

STAGE='PROD'

if [ $STAGE == 'PROD' ]
then
    # prod
    echo "Prod mode is activated..."
    WPA_CONF_FILE='/etc/wpa_supplicant/wpa_supplicant.conf'
else
    # test
    echo "Test mode is activated..."
    WPA_CONF_FILE='/home/user/wpa_supplicant.conf'
fi

SMSTOOL_CONF_PATH='/etc/smsd.conf'
CONFIG_PATH='/etc/sms-to-email.conf'
SMTP_CONF_PATH='/etc/ssmtp/ssmtp.conf'
SYS_DEAMON='/etc/systemd/system/'
EMAIL_DEAMON='/etc/init.d/send-email-when-smsd.sh'
EMAIL_SYSD='send-email-when-sms.service'
EMAIL_TEST='/usr/bin/send-test-email.sh'
INTERNET_DEAMON='/etc/init.d/start-modemd.sh'
INTERNET_SYSD='start-modem.service'

## install depencencies (internet needed)
if [ $STAGE == 'PROD' ]
then
    apt-get -y install smstools libqmi-utils udhcpc ssmtp mailutils vim ifmetric
fi

## copy files to locations
cp -f $1 $CONFIG_PATH

echo "Install configuration file: $CONFIG_PATH"

MODEM_TTY=`eval "grep \"^MODEM_TTY=\" $CONFIG_PATH | cut -d= -f2"`
INCOMING_SMS_P=`eval "grep \"^INCOMING_SMS_P=\" $CONFIG_PATH | cut -d= -f2"`
SSID=`eval "grep \"^SSID=\" $CONFIG_PATH | cut -d= -f2"`
WIFI_PWD=`eval "grep \"^WIFI_PWD=\" $CONFIG_PATH | cut -d= -f2"`
APN=`eval "grep \"^APN=\" $CONFIG_PATH | cut -d= -f2"`
FROM_EMAIL=`eval "grep \"^FROM_EMAIL=\" $CONFIG_PATH | cut -d= -f2"`
FROM_PWD=`eval "grep \"^FROM_PWD=\" $CONFIG_PATH | cut -d= -f2"`
FROM_HUB=`eval "grep \"^FROM_HUB=\" $CONFIG_PATH | cut -d= -f2"`
DEST_EMAIL=`eval "grep \"^DEST_EMAIL=\" $CONFIG_PATH | cut -d= -f2"`
HOST_NAME=`eval "grep \"^HOST_NAME=\" $CONFIG_PATH | cut -d= -f2"`

## smstools config
echo 'SMS TTY configuration:' $MODEM_TTY $INCOMING_SMS_P
cat << SMSEOF > $SMSTOOL_CONF_PATH
#
# /etc/smsd.conf
#
# Description: Main configuration file for the smsd
#

devices = GSM1
outgoing = /var/spool/sms/outgoing
checked = /var/spool/sms/checked
incoming = $INCOMING_SMS_P
logfile = /var/log/smstools/smsd.log
infofile = /var/run/smstools/smsd.working
pidfile = /var/run/smstools/smsd.pid
outgoing = /var/spool/sms/outgoing
checked = /var/spool/sms/checked
failed = /var/spool/sms/failed
incoming = $INCOMING_SMS_P
sent = /var/spool/sms/sent
stats = /var/log/smstools/smsd_stats
#loglevel = 7
#delaytime = 10
#errorsleeptime = 10
#blocktime = 3600
#stats = /var/log/smsd_stats
#stats_interval = 3600
#stats_no_zeroes = no
#checkhandler = /usr/local/bin/smscheck
receive_before_send = no
# autosplit 0=no 1=yes 2=with text numbers 3=concatenated
autosplit = 3
# store_received_pdu 0=no, 1=unsupported, 2=unsupported and 8bit, 3=all
#store_received_pdu = 1
#validity = 255
#decode_unicode_text = no
#internal_combine = no
# You can specify here an external program that is started whenever an alarm occurs.
# alarmhandler = /path/to/an/alarmhandler/script
# Specifies what levels start an alarmhandler. You can use value between 2 and 5.
# alarmlevel = 4
# eventhandler = @EVENTHANDLER@
#blacklist = /etc/smstools/blacklist
#whitelist = /etc/smstools/whitelist

[GSM1]
#init =
device = $MODEM_TTY
incoming = yes
#pin =
baudrate = 115200
memory_start = 0

SMSEOF

mkdir -p $INCOMING_SMS_P
if [ $STAGE == 'PROD' ]
then
    /etc/init.d/smstools restart
fi

## WiFi configuration
echo 'WiFi configuration:' $SSID $WIFI_PWD
cat << WPAEOF > $WPA_CONF_FILE
country=GB
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
ap_scan=1

update_config=1
network={
	ssid="$SSID"
	psk="$WIFI_PWD"
}

WPAEOF

if [ $STAGE == 'PROD' ]
then
  chmod 600 $WPA_CONF_FILE
  rfkill unblock wifi
  for filename in /var/lib/systemd/rfkill/*:wlan ; do
    echo 0 > $filename
  done
  rm -f /var/run/wpa_supplicant/*
  wpa_supplicant -B -i wlan0 -c $WPA_CONF_FILE
  ifconfig wwan0 up
  udhcpc -i wlan0
fi

## smtp configuration
echo 'SMTP configuration:' $FROM_EMAIL $FROM_PWD $FROM_HUB
cat << SMTPEOF > $SMTP_CONF_PATH
#
# Config file for sSMTP sendmail
#
# The person who gets all mail for userids < 1000
# Make this empty to disable rewriting.
root=postmaster

# The place where the mail goes. The actual machine name is required no
# MX records are consulted. Commonly mailhosts are named mail.domain.com
mailhub=mail

# Where will the mail seem to come from?
#rewriteDomain=

# The full hostname
hostname=smsgw

# Are users allowed to set their own From: address?
# YES - Allow the user to specify their own From: address
# NO - Use the system generated From: address
FromLineOverride=YES

AuthUser=$FROM_EMAIL
AuthPass=$FROM_PWD
mailhub=$FROM_HUB
UseTLS=Yes

SMTPEOF

## create send_test_email script
echo 'create EMAIL test script:' $DEST_EMAIL $HOST_NAME $FROM_EMAIL
cat << EMAILTESTEOF > $EMAIL_TEST
#!/bin/bash

# no params
# action: send a test email based on the current configuration

echo "test email from $HOST_NAME" | mail -s "$HOST_NAME>test email" -a "From: SMSBot <$FROM_EMAIL>"  $DEST_EMAIL

EMAILTESTEOF
chmod +x $EMAIL_TEST

## create send_email_when_sms script
echo 'EMAIL configuration:' $DEST_EMAIL $HOST_NAME $FROM_EMAIL
cat << EMAILDEOF > $EMAIL_DEAMON
#!/bin/bash

# params: [start][stop][restart]
# actions: service that monitor the incoming sms and automatically send an email

while true; do
  ls -1 $INCOMING_SMS_P | while read file; do
    echo 'found new sms:' $INCOMING_SMS_P/\$file >> /var/log/send-email-when-smsd.log

    # send email with content as file
    echo 'send email:' $INCOMING_SMS_P/\$file >> /var/log/send-email-when-smsd.log
    echo -e '\n\n### modem status: --\n' >> $INCOMING_SMS_P/\$file
    qmicli -d /dev/cdc-wdm0 --nas-get-home-network &>> $INCOMING_SMS_P/\$file
    qmicli -d /dev/cdc-wdm0 --uim-get-card-status &>> $INCOMING_SMS_P/\$file
    cat $INCOMING_SMS_P/\$file >> /var/log/send-email-when-smsd.log
    cat $INCOMING_SMS_P/\$file | mail -s "$HOST_NAME> new sms" -a "From: SMSBot <$FROM_EMAIL>"  $DEST_EMAIL &>> /var/log/send-email-when-smsd.log

    # remove file if success
    if [ \$? -eq 0 ]; then
      echo 'remove file:' $INCOMING_SMS_P/\$file >> /var/log/send-email-when-smsd.log
      rm -f $INCOMING_SMS_P/\$file
    fi

  done
  sleep 1
done

EMAILDEOF
chmod +x $EMAIL_DEAMON


## initiate service deamon for send_email_when_sms
echo 'Setup autostart send-email-when-sms deamon:' $EMAIL_SYSD
cat << EMAILSYSD > $SYS_DEAMON$EMAIL_SYSD
[Unit]
Description=Setup autostart email deamo unit file.

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/bin/bash $EMAIL_DEAMON

[Install]
WantedBy=multi-user.target

EMAILSYSD
chmod +x $SYS_DEAMON$EMAIL_SYSD
systemctl daemon-reload
systemctl enable $EMAIL_SYSD
systemctl start $EMAIL_SYSD
systemctl status $EMAIL_SYSD

## create internet-checker script
echo 'Internet-checker configuration:' $APN
cat << INTERNETDEOF > $INTERNET_DEAMON
#!/bin/bash

# params: [start][stop][restart]
# actions: service that monitor and keep internet active between wlan0 and wwan0

# remove previous log
rm -f /var/log/start-modem.log

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" >> /var/log/start-modem.log
   exit 1
fi

# reset wwan0
ifconfig wwan0 down

while true; do
  echo "test modem connection..." >> /var/log/start-modem.log
  route | grep wwan0
  if [ \$? -eq 0 ]; then
    echo "internet ok..." >> /var/log/start-modem.log
  else
    # start LTE communication
    echo "start LTE modem..." >> /var/log/start-modem.log
    ifconfig wwan0 down
    sh -c "echo Y > /sys/class/net/wwan0/qmi/raw_ip"
    ifconfig wwan0 up &>> /var/log/start-modem.log
    sleep 1
    qmicli -d /dev/cdc-wdm0 --dms-set-operating-mode='online' &>> /var/log/start-modem.log
    if [ \$? -eq 0 ]; then
      sleep 1
      qmicli -d /dev/cdc-wdm0 --device-open-net="net-raw-ip|net-no-qos-header" --wds-start-network="apn='$APN',ip-type=4" --client-no-release-cid &>> /var/log/start-modem.log
      if [ \$? -eq 0 ]; then
        sleep 1
        udhcpc -i wwan0 &>> /var/log/start-modem.log
        sleep 1
        #udhcpc -i wlan0 &>> /var/log/start-modem.log
        #sleep 1
        ifmetric wwan0 500 &>> /var/log/start-modem.log
        route &>> /var/log/start-modem.log
      fi
    fi
  fi

  sleep 30
done

INTERNETDEOF
chmod +x $INTERNET_DEAMON

## initiate service deamon for internet-checker
echo 'Setup autostart internet-checker deamon:' $INTERNET_SYSD
cat << INTERNETSYSD > $SYS_DEAMON$INTERNET_SYSD
[Unit]
Description=Setup autostart setup model unit file.

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/bin/bash $INTERNET_DEAMON

[Install]
WantedBy=multi-user.target

INTERNETSYSD
chmod +x $SYS_DEAMON$INTERNET_SYSD
systemctl daemon-reload
systemctl enable $INTERNET_SYSD
systemctl start $INTERNET_SYSD
systemctl status $INTERNET_SYSD
