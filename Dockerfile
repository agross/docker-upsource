FROM frolvlad/alpine-glibc
MAINTAINER Alexander Groß <agross@therightstuff.de>

COPY ./docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["upsource", "run"]

EXPOSE 8080

WORKDIR /upsource

RUN UPSOURCE_VERSION=3.0.4237 && \
    \
    echo Creating upsource user and group with static ID of 6000 && \
    addgroup -g 6000 -S upsource && \
    adduser -g "JetBrains Upsource" -S -h "$(pwd)" -u 6000 -G upsource upsource && \
    \
    echo Installing packages && \
    apk add --update coreutils \
                     bash \
                     wget \
                     ca-certificates && \
    \
    DOWNLOAD_URL=https://download.jetbrains.com/upsource/upsource-$UPSOURCE_VERSION.zip && \
    echo Downloading $DOWNLOAD_URL to $(pwd) && \
    wget "$DOWNLOAD_URL" --no-verbose --output-document upsource.zip && \
    \
    echo Extracting to $(pwd) && \
    unzip ./upsource.zip -d . -x Upsource/internal/java/linux-amd64/man/* Upsource/internal/java/windows-amd64/* Upsource/internal/java/mac-x64/* && \
    rm -f upsource.zip && \
    mv Upsource/* . && \
    rm -rf Upsource/* && \
    \
    chown -R upsource:upsource . && \
    chmod +x /docker-entrypoint.sh

USER upsource
