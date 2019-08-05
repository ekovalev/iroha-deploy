FROM alpine:3.10

RUN apk add  --no-cache \
                bash \
                python3 \
                python3-dev \
                make \
                rsync \
                g++ \
                libffi-dev \
                openssl-dev \
                openssh-client && rm -rfv /var/cache/apk/* && \
ln -sf /usr/bin/python3 /usr/bin/python && \
pip3 install ansible==2.8.2 boto boto3 future

