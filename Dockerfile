# Small Alpine base image, pinned so builds are repeatable.
FROM alpine:3.20

LABEL maintainer="Robert Olwoch" \
      description="Bash diagnostic app built and tested by GitHub Actions"

# bash is the only package needed. Alpine's busybox already has
# hostname, awk, nslookup and timeout. --no-cache keeps the apk index out of the image.
# Also create a normal user so the app does not run as root.
RUN apk add --no-cache bash \
    && adduser -D -H -s /sbin/nologin appuser

WORKDIR /app

# only the application is copied (see .dockerignore)
COPY app/app.sh /app/app.sh
RUN chmod 755 /app/app.sh

USER appuser

# "docker run devops-tool <command>" runs app.sh <command>, default is help
ENTRYPOINT ["/app/app.sh"]
CMD ["help"]
