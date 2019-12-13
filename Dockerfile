FROM frolvlad/alpine-glibc
LABEL maintainer "Alexander Groß <agross@therightstuff.de>"

COPY ./docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["upsource", "run"]

EXPOSE 8080

WORKDIR /upsource

HEALTHCHECK --start-period=2m \
            CMD wget --server-response --output-document=/dev/null http://localhost:8080 || exit 1

ARG VERSION=2019.1.1578
ARG DOWNLOAD_URL=https://download.jetbrains.com/upsource/upsource-$VERSION.zip
ARG SHA_DOWNLOAD_URL=https://download.jetbrains.com/upsource/upsource-$VERSION.zip.sha256


RUN echo Creating upsource user and group with static ID of 6000 && \
    addgroup -g 6000 -S upsource && \
    adduser -g "JetBrains Upsource" -S -h "$(pwd)" -u 6000 -G upsource upsource && \
    \
    apk add --update bash \
                     ca-certificates \
                     coreutils \
                     wget && \
    \
    echo Downloading $DOWNLOAD_URL to $(pwd) && \
    wget --progress bar:force:noscroll \
         "$DOWNLOAD_URL" && \
    \
    echo Verifying download && \
    wget --progress bar:force:noscroll \
         --output-document \
         download.sha256 \
         "$SHA_DOWNLOAD_URL" && \
    \
    sha256sum -c download.sha256 && \
    rm download.sha256 && \
    \
    echo Extracting to $(pwd) && \
    unzip ./upsource-$VERSION.zip \
          -d . \
          -x upsource-$VERSION/internal/java/linux-amd64/man/* \
             upsource-$VERSION/internal/java/windows-amd64/* \
             upsource-$VERSION/internal/java/mac-x64/* && \
    rm upsource-$VERSION.zip && \
    mv upsource-$VERSION/* . && \
    rm -r upsource-$VERSION && \
    \
    chown -R upsource:upsource . && \
    chmod +x /docker-entrypoint.sh

USER upsource
