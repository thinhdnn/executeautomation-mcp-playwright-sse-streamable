#!/bin/bash

# This script sets up a complete development environment by installing necessary packages,
# configuring services, and starting them. It is intended for use on a fresh Ubuntu system.

sh port-http-server.sh

sh install-build.sh

sh start-server.sh