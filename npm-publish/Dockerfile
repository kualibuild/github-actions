FROM node:slim
RUN apt-get update && apt-get install -y jq
ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
