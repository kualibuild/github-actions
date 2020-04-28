FROM debian:stretch-slim
RUN apt-get update && apt-get install -y curl jq
ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
