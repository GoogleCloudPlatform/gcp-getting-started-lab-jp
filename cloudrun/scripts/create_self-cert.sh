#!/bin/bash

openssl genrsa 2048 > private.key
openssl req -new -x509 -days 3650 -key private.key -sha512 -out sumservice.crt