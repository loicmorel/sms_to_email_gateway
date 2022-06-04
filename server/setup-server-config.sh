# installs on the Server
apt-get update
apt-get upgrade -y
apt-get install -y curl jq git tmux apt-transport-https ca-certificates gnupg-agent software-properties-common

# install docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
curl -L "https://github.com/docker/compose/releases/download/1.28.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# start FRP on the server
docker-compose up -d
docker-compose logs -f
docker-compose ps
