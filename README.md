# docker-upsource

[![](https://imagelayers.io/badge/agross/upsource:latest.svg)](https://imagelayers.io/?images=agross/upsource:latest 'Get your own badge on imagelayers.io')

This Dockerfile allows you to build images to deploy your own [Upsource](http://www.jetbrains.com/upsource/) instance. It has been tested on [Fedora 23](https://getfedora.org/) and [CentOS 7](https://www.centos.org/).

*Please remember to back up your data directories often, especially before upgrading to a newer version.*

## Test it

1. [Install docker.](http://docs.docker.io/en/latest/installation/)
2. Run the container. (Stop with CTRL-C.)

  ```sh
  docker run -it -p 8080:8080 agross/upsource
  ```

3. Open your browser and navigate to `http://localhost:8080`.

## Run it as service on systemd

1. Decide where to put Upsource data and logs. Set domain name/server name and the public port.

  ```sh
  UPSOURCE_DATA="/var/data/upsource"
  UPSOURCE_LOGS="/var/log/upsource"

  DOMAIN=example.com
  PORT=8013
  ```

2. Create directories to store data and logs outside of the container.

  ```sh
  mkdir --parents "$UPSOURCE_DATA/backups" \
                  "$UPSOURCE_DATA/conf" \
                  "$UPSOURCE_DATA/data" \
                  "$UPSOURCE_LOGS"
  ```

3. Set permissions.

  The Dockerfile creates a `upsource` user and group. This user has a `UID` and `GID` of `6000`. Make sure to add a user to your host system with this `UID` and `GID` and allow this user to read and write to `$UPSOURCE_DATA` and `$UPSOURCE_LOGS`. The name of the host user and group in not important.

  ```sh
  # Create upsource group and user in docker host, e.g.:
  groupadd --gid 6000 --system upsource
  useradd --uid 6000 --gid 6000 --system --shell /sbin/nologin --comment "JetBrains Upsource" upsource

  # 6000 is the ID of the upsource user and group created by the Dockerfile.
  chown -R 6000:6000 "$UPSOURCE_DATA" "$UPSOURCE_LOGS"
  ```

4. Create your container.

  *Note:* The `:z` option on the volume mounts makes sure the SELinux context of the directories are [set appropriately.](http://www.projectatomic.io/blog/2015/06/using-volumes-with-docker-can-cause-problems-with-selinux/)

  ```sh
  docker create -it -p $PORT:8080 \
                    -v "$UPSOURCE_DATA/backups:/upsource/backups:z" \
                    -v "$UPSOURCE_DATA/conf:/upsource/conf:z" \
                    -v "$UPSOURCE_DATA/data:/upsource/data:z" \
                    -v "$UPSOURCE_LOGS:/upsource/logs:z" \
                    --name upsource \
                    agross/upsource
  ```

5. Create systemd unit, e.g. `/etc/systemd/system/upsource.service`.

  ```sh
  cat <<EOF > "/etc/systemd/system/upsource.service"
  [Unit]
  Description=JetBrains Upsource
  Requires=docker.service
  After=docker.service

  [Service]
  Restart=always
  # When docker stop is executed, the docker-entrypoint.sh trap + wait combination
  # will generate an exit status of 143 = 128 + 15 (SIGTERM).
  # More information: http://veithen.github.io/2014/11/16/sigterm-propagation.html
  SuccessExitStatus=143
  PrivateTmp=true
  ExecStart=/usr/bin/docker start --attach=true upsource
  ExecStop=/usr/bin/docker stop --time=10 upsource

  [Install]
  WantedBy=multi-user.target
  EOF

  systemctl enable upsource.service
  systemctl start upsource.service
  ```

6. Setup logrotate, e.g. `/etc/logrotate.d/upsource`.

  ```sh
  cat <<EOF > "/etc/logrotate.d/upsource"
  $UPSOURCE_LOGS/*.log
  $UPSOURCE_LOGS/cassandra/*.log
  $UPSOURCE_LOGS/hub/*.log
  $UPSOURCE_LOGS/internal/services/bundleProcess/*.log
  $UPSOURCE_LOGS/upsource-analyzer/*.log
  $UPSOURCE_LOGS/upsource-cluster-init/*.log
  $UPSOURCE_LOGS/upsource-frontend/*.log
  $UPSOURCE_LOGS/upsource-monitoring/*.log
  $UPSOURCE_LOGS/upsource-psi/*.log
  {
    rotate 7
    daily
    dateext
    missingok
    notifempty
    sharedscripts
    copytruncate
    compress
  }
  EOF
  ```
7. Add nginx configuration, e.g. `/etc/nginx/conf.d/upsource.conf`.

  ```sh
  cat <<EOF > "/etc/nginx/conf.d/upsource.conf"
  upstream upsource {
    server localhost:$PORT;
  }

  server {
    listen           80;
    listen      [::]:80;

    server_name $DOMAIN;

    access_log  /var/log/nginx/$DOMAIN.access.log;
    error_log   /var/log/nginx/$DOMAIN.error.log;

    # Do not limit upload.
    client_max_body_size 0;

    # Required to avoid HTTP 411: see issue #1486 (https://github.com/dotcloud/docker/issues/1486)
    chunked_transfer_encoding on;

    location / {
      proxy_pass http://upsource;

      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-Host \$http_host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_http_version 1.1;

      # Support WebSockets.
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_pass_header Sec-Websocket-Extensions;
    }
  }
  EOF

  nginx -s reload
  ```

  Make sure SELinux policy allows nginx to access port `$PORT` (the first part of `-p $PORT:8080` of step 3).

  ```sh
  if [ $(semanage port --list | grep --count "^http_port_t.*$PORT") -eq 0 ]; then
    if semanage port --add --type http_port_t --proto tcp $PORT; then
      echo Added port $PORT as a valid port for nginx:
      semanage port --list | grep ^http_port_t
    else
      >&2 echo Could not add port $PORT as a valid port for nginx. Please add it yourself. More information: http://axilleas.me/en/blog/2013/selinux-policy-for-nginx-and-gitlab-unix-socket-in-fedora-19/
    fi
  else
    echo Port $PORT is already a valid port for nginx:
    semanage port --list | grep ^http_port_t
  fi
  ```

8. Configure Upsource.

  Follow the steps of the installation [instructions for JetBrains Upsource](https://confluence.jetbrains.com/display/YTD65/Installing+Upsource+with+ZIP+Distribution) using paths inside the docker container located under

    * `/upsource/backups`,
    * `/upsource/data`,
    * `/upsource/logs` and
    * `/upsource/temp`.

9. Update to a newer version.

  ```sh
  docker pull agross/upsource

  systemctl stop upsource.service

  # Back up $UPSOURCE_DATA.
  tar -zcvf "upsource-data-$(date +%F-%H-%M-%S).tar.gz" "$UPSOURCE_DATA"

  docker rm upsource

  # Repeat step 4 and create a new image.
  docker create ...

  systemctl start upsource.service
  ```

## Building and testing the `Dockerfile`

1. Build the `Dockerfile`.

  ```sh
  docker build --tag agross/upsource:testing .

  docker images
  # Should contain:
  # REPOSITORY                        TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
  # agross/upsource                   testing             0dcb8bf6093f        49 seconds ago      405.4 MB

  ```

2. Prepare directories for testing.

  ```sh
  TEST_DIR="/tmp/upsource-testing"

  mkdir --parents "$TEST_DIR/backups" \
                  "$TEST_DIR/conf" \
                  "$TEST_DIR/data" \
                  "$TEST_DIR/logs"
  chown -R 6000:6000 "$TEST_DIR"
  ```

3. Run the container built in step 1.

  *Note:* The `:z` option on the volume mounts makes sure the SELinux context of the directories are [set appropriately.](http://www.projectatomic.io/blog/2015/06/using-volumes-with-docker-can-cause-problems-with-selinux/)

  ```sh
  docker run -it --rm \
                 --name upsource-testing \
                 -p 8080:8080 \
                 -v "$TEST_DIR/backups:/upsource/backups:z" \
                 -v "$TEST_DIR/conf:/upsource/conf:z" \
                 -v "$TEST_DIR/data:/upsource/data:z" \
                 -v "$TEST_DIR/logs:/upsource/logs:z" \
                 agross/upsource:testing
  ```

4. Open a shell to your running container.

  ```sh
  docker exec -it upsource-testing bash
  ```

5. Run bash instead of starting Upsource.

  *Note:* The `:z` option on the volume mounts makes sure the SELinux context of the directories are [set appropriately.](http://www.projectatomic.io/blog/2015/06/using-volumes-with-docker-can-cause-problems-with-selinux/)

  ```sh
  docker run -it -v "$TEST_DIR/backups:/upsource/backups:z" \
                 -v "$TEST_DIR/conf:/upsource/conf:z" \
                 -v "$TEST_DIR/data:/upsource/data:z" \
                 -v "$TEST_DIR/logs:/upsource/logs:z" \
                 agross/upsource:testing bash
  ```

  Without mounted data directories:

  ```sh
  docker run -it agross/upsource:testing bash
  ```

6. Clean up after yourself.

  ```sh
  docker ps -aq --no-trunc --filter ancestor=agross/upsource:testing | xargs --no-run-if-empty docker rm
  docker images -q --no-trunc agross/upsource:testing | xargs --no-run-if-empty docker rmi
  rm -rf "$TEST_DIR"
  ```
