#!/usr/bin/env bash

apt-get update

# curl's a generally useful utility across SO many platforms ...
apt-get install -y curl

# we're going to need git to grab some utilities from github
apt-get install -y git

# JSON.sh is a json parser written in bash
cd /tmp
git clone https://github.com/dominictarr/JSON.sh.git
cd JSON.sh
mv JSON.sh /usr/local/bin/.
cd

# for apache benchmark
# http://httpd.apache.org/docs/2.2/programs/ab.html
apt-get install -y apache2-utils

# simple command line tools for poking @ memcached
apt-get install -y libmemcached-tools

# :TODO: reminder - docker recommends updating linux kernel - who to do this?

# http://docs.docker.io/en/latest/installation/ubuntulinux/#ubuntu-precise-12-04-lts-64-bit
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
sh -c "echo deb http://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list"
apt-get update
apt-get install -y lxc-docker
