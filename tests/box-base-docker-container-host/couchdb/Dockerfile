# creates a docker image based on ubuntu 12.04 that runs
# couchdb 1.5.1 listening on 0.0.0.0:5984.
#
# this seems like a pretty complicated Dockfile. where's all this
# complexity coming from? can you do a simple apt-get couchdb?
# apt-get couchdb installs version 1.2 of couchdb and we wanted
# version 1.5.1:-(
#
# create image
#
#   sudo docker build -t couchdb_img .
#
# once the image is built get key store running:
#
#   KEY_STORE=$(sudo docker run -d couchdb_img)
#
# now verify couchdb is running and accessible
#
#   KEY_STORE_IP=$(sudo docker inspect -format '{{ .NetworkSettings.IPAddress }}' $KEY_STORE)
#   curl http://$KEY_STORE_IP:5984
#
# very useful for interactive testing/debugging
#
#   sudo docker run -i -t ubuntu:12.04 /bin/bash
#   sudo docker run -i -t couchdb_img /bin/bash
#
# couchdb configuration files
#
#   /usr/local/etc/couchdb/local.ini - change this; won't be updated on server update
#   /usr/local/etc/couchdb/default.ini
#
# references
#
#   https://wiki.apache.org/couchdb/Installing_on_Ubuntu
#   http://deepuelenor.wordpress.com/2013/12/13/installing-latest-version-of-couchdb-1-5-0-on-ubuntu-12-04-lts/
#   https://www.digitalocean.com/community/articles/how-to-set-up-couchdb-with-elasticsearch-on-an-ubuntu-13-10-vps

FROM ubuntu:12.04

MAINTAINER Dave Simons

RUN apt-get update

# if a vagrant ubuntu 12.04 install has these packages
# installed why does a docker based install of ubuntu 12.04
# need to have them installed explicitly
RUN apt-get install -y curl
RUN apt-get install -y build-essential
RUN apt-get install -y erlang-base erlang-dev erlang-nox erlang-eunit
RUN apt-get install -y libmozjs185-dev libicu-dev libcurl4-gnutls-dev libtool

RUN curl -O http://mirror.csclub.uwaterloo.ca/apache/couchdb/source/1.5.1/apache-couchdb-1.5.1.tar.gz 
RUN tar -xvf apache-couchdb-1.5.1.tar.gz
RUN cd apache-couchdb-1.5.1; ./configure; make; make install

RUN adduser --gecos --disabled-login --disabled-password --no-create-home couchdb

ADD local.ini /usr/local/etc/couchdb/local.ini

RUN chown -R couchdb:couchdb /usr/local/var/log/couchdb
RUN chown -R couchdb:couchdb /usr/local/var/lib/couchdb
RUN chown -R couchdb:couchdb /usr/local/var/run/couchdb
RUN chown -R couchdb:couchdb /usr/local/etc/couchdb

EXPOSE 5984

USER couchdb

ENTRYPOINT couchdb
