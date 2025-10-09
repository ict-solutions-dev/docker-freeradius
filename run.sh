#!/bin/bash

docker run -d --name freeradius -p 1812:1812/udp -p 1813:1813/udp ict-solutions-dev/freeradius:edge-freeradius-latest
