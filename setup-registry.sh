#!/bin/sh

# docker run -d -p 5000:5000 --name registry registry:2
docker tag flexmasa:latest localhost:5000/flexmasa:latest
docker push localhost:5000/flexmasa:latest