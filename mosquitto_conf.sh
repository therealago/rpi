#!/bin/bash

cd
sudo echo
sudo echo listener 1883 >> /etc/mosquitto/mosquitto.conf
sudo echo allow_anonymous true >> /etc/mosquitto/mosquitto.c
