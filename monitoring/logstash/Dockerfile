FROM docker.elastic.co/logstash/logstash:8.12.2

# 1) Плагины: S3 input и HTTP output
RUN bin/logstash-plugin install --no-verify logstash-integration-aws \
    && bin/logstash-plugin install --no-verify logstash-output-http 
# 2) Кладём корневой CA MinIO и доверяем ему на уровне JVM, встроенной в Logstash
COPY minio-rootCA.pem /usr/local/share/ca-certificates/minio-rootCA.crt
RUN update-ca-certificates || true

RUN /usr/share/logstash/jdk/bin/keytool -importcert -noprompt -trustcacerts \
  -keystore /usr/share/logstash/jdk/lib/security/cacerts \
  -storepass changeit \
  -alias minio-local \
  -file /usr/local/share/ca-certificates/minio-rootCA.crt