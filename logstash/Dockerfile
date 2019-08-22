FROM docker.elastic.co/logstash/logstash:7.3.0

RUN set -x \
    && /usr/share/logstash/bin/logstash-plugin install logstash-output-syslog

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
