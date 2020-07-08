FROM debian:stretch-slim
RUN apt-get -y update && apt-get -y install git
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
