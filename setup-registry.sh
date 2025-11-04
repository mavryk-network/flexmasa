#!/bin/sh

# docker run -d -p 5000:5000 --name registry registry:2
docker tag mavbox:latest localhost:5000/mavbox:latest
docker push localhost:5000/mavbox:latest